# NimMax Deficiencies Discovered During NimForum Migration

This document lists bugs, API gaps, and design deficiencies found in NimMax while migrating NimForum from Jester.

**Status: FIXED in v1.1.0** — Deficiencies #1, #2, #3, #4, #5, #6, #7, #8 have been addressed.

---

## 1. No Built-in `makeUri` / URL Builder

**Status: FIXED** — `ctx.makeUri(address, absolute)` is now available in context.nim.

**Problem:** Jester provides `makeUri(request, address, absolute)` to build URLs relative to the current request's scheme/host. NimMax has no equivalent.

**Solution:** Added `makeUri` proc to Context:
```nim
proc makeUri*(ctx: Context, address = "", absolute = true): string
```

Respects `X-Forwarded-Proto` header for reverse proxy setups.

**Severity:** Medium — breaks every project that generates absolute URLs (RSS feeds, emails, OAuth redirects).

---

## 2. `setCookie` Takes `sameSite` as Raw String Instead of stdlib Enum

**Status: FIXED** — `ctx.setCookieEnum()` now accepts stdlib `SameSite` enum.

**Problem:** Nim's stdlib `cookies.nim` defines `SameSite {.pure.} = enum Default, Lax, Strict, None`. NimMax's `setCookie` takes `sameSite = "Lax"` as a raw string.

This is:
- Type-unsafe (typos silently accepted)
- Inconsistent with stdlib
- Breaks code that uses `SameSite.Strict` from stdlib

**Solution:** Added `setCookieEnum` overload that accepts the stdlib `SameSite` enum:
```nim
ctx.setCookieEnum("session", "abc123",
  path = "/",
  maxAge = 86400,
  httpOnly = true,
  secure = true,
  sameSite = cookies.SameSite.Strict
)
```

Original `setCookie` with string parameter is preserved for backward compatibility.

**Severity:** Low-Medium — easy workaround but poor API design.

---

## 3. `loadConfig` Causes Global Naming Collision

**Status: FIXED** — Renamed to `loadNimmaxConfig`, old name kept as deprecated alias.

**Problem:** `nimmax/core/configure.nim` exports `loadConfig(configDir = ".config", envName = ""): JsonNode` at module top level. This collides with the forum's own `utils.loadConfig(filename: string): Config`.

**Solution:** Renamed to `loadNimmaxConfig`. The old `loadConfig` is kept as a deprecated alias:
```nim
proc loadNimmaxConfig*(configDir = ".config", envName = ""): JsonNode
proc loadConfig*(configDir = ".config", envName = ""): JsonNode {.deprecated: "Use loadNimmaxConfig instead".}
```

**Severity:** Medium — any project with its own config loader will hit this.

---

## 4. No Built-in Client IP Accessor

**Status: FIXED** — `ctx.clientIP()` is now available in context.nim.

**Problem:** Jester's `request.ip` returns the client IP string. NimMax requires digging through `ctx.request.nativeRequest.hostname` (which is `asynchttpserver.Request.hostname`).

**Solution:** Added `clientIP` proc to Context that respects `X-Forwarded-For` and `X-Real-IP` headers:
```nim
proc clientIP*(ctx: Context): string
```

**Severity:** Low — one-liner workaround but should be built-in.

---

## 5. No Unified `params` Accessor (Path/Query/Post Merged)

**Status: FIXED** — `ctx.getParam()` and typed variants are now available.

**Problem:** Jester's `request.params` merges path params, query params, and POST body params into one `StringTableRef`. NimMax has separate `getPathParam()`, `getQueryParam()`, `getPostParam()` with no merged view.

**Solution:** Added unified accessor procs that try path → query → post in order:
```nim
proc getParam*(ctx: Context, key: string): string
proc getParamInt*(ctx: Context, key: string): Option[int]
proc getParamFloat*(ctx: Context, key: string): Option[float]
proc getParamBool*(ctx: Context, key: string): Option[bool]
```

**Severity:** Medium — every route handler that accepts form data needs this boilerplate.

---

## 6. No `cond`, `pass`, `halt` Control Flow Helpers

**Status: FIXED** — `cond()` and `halt()` are now available. `pass()` remains impossible.

**Problem:** Jester provides:
- `cond(condition)` — aborts with Http400 if false
- `pass()` — skips to next matching route
- `halt()` — stops request processing

NimMax only has `abortRequest(code, body)` which raises an exception. There is no `pass` equivalent (can't skip to next route), and no concise `cond`.

**Solution:** Added `cond` and `halt` helpers:
```nim
proc cond*(ctx: Context, condition: bool) =
  if not condition: ctx.abortRequest(Http400, "Bad Request")

proc halt*(ctx: Context, code = Http404, body = "") =
  ctx.abortRequest(code, body)
```

Note: `pass()` is architecturally impossible in NimMax's routing model.

**Severity:** Medium — `pass()` is impossible to implement; `cond()` is common in Jester routes.

---

## 7. `resp` Has Different Parameter Order Than Jester

**Status: FIXED** — `ctx.resp()` with Jester-compatible parameter order is now available.

**Problem:** Jester's `resp` signatures:
```nim
resp(body)                           # 200 + auto content-type
resp(code, body)                     # custom code
resp(code, body, contentType)        # full control
```

NimMax's equivalents are fragmented:
```nim
ctx.send(body, code, contentType)    # different order!
ctx.respond(body, code, headers)     # different again
ctx.html(body, code)
ctx.json(body, code)
```

There is no single `resp(code, body, contentType)` with Jester's parameter order.

**Solution:** Added Jester-compatible `resp` procs:
```nim
proc resp*(ctx: Context, body: string, code = Http200, contentType = "")
proc resp*(ctx: Context, code: HttpCode, body: string, contentType = "")
```

**Severity:** Low — compat layer fixes it, but migration friction.

---

## 8. POST Body Params Not Auto-Parsed

**Status: FIXED** — `formBodyMiddleware()` now auto-parses POST bodies.

**Problem:** Jester automatically parses `application/x-www-form-urlencoded` and `multipart/form-data` POST bodies into `request.params`. NimMax's `request.postParams` TableRef exists but is **not** populated automatically.

**Solution:** Added `formBodyMiddleware()` that automatically parses POST/PUT/PATCH bodies:
```nim
import nimmax/middlewares

let app = newApp()
app.use(formBodyMiddleware())  # Auto-parses form bodies
```

The middleware populates `ctx.request.postParams` and `ctx.request.formParams` automatically.

**Severity:** Medium — every form-handling route needs explicit parsing.

---

## 9. Router Doesn't Support Regex Patterns in Routes

**Problem:** Jester supports regex routes like:
```nim
get re"/like|unlike":
  # handles both /like and /unlike
```

NimMax only supports `:param` style path parameters. No regex matching in route patterns.

**Workaround in forum:** Split regex routes into separate explicit routes:
```nim
app.get("/like", ...)
app.get("/unlike", ...)
```

**Severity:** Low-Medium — workaround is verbose but functional.

---

## 10. No Route-Level `before`/`after` Hooks

**Problem:** Jester's `routes:` DSL allows `before` and `after` blocks scoped to specific routes or route groups. NimMax only has a global middleware chain.

**Workaround in forum:** Moved per-route setup (like `createTFD`) into each handler manually.

**Severity:** Low — middleware chain is the modern pattern anyway.

---

## 11. `getCookie` Returns Empty String for Missing Cookies

**Problem:** `ctx.request.getCookie(name)` returns `""` if the cookie doesn't exist. This is because it uses `strtabs.StringTableRef` internally. However, `ctx.request.cookies` is exposed as `TableRef[string, string]`, which would raise `KeyError` on missing keys.

The inconsistency between `getCookie()` (returns "") and direct `cookies[]` access (raises) is confusing.

**Workaround in forum:** Used `hasKey()` check before accessing cookies.

**Severity:** Low — documented behavior but inconsistent types.

---

## 12. Session Object Is Not Auto-Attached to Context

**Problem:** Jester has a simple session system via `setSession` / `getSession`. NimMax's `Context.session` field exists but is `nil` by default. The sessions middleware must be explicitly added and configured.

**Workaround in forum:** Wrote our own session handling via `checkLoggedIn()` reading the `sid` cookie directly from the DB.

**Severity:** Medium — every project needs to re-implement session logic or figure out the middleware setup.

---

## 13. No Built-in Static File SPA Fallback

**Problem:** For Single Page Applications, you need a catch-all route (`/*`) that serves `index.html` for non-API paths. Jester's static file handler is simple. NimMax's static files middleware doesn't seem to have a built-in "fallback to index.html" option.

**Workaround in forum:** Added explicit catch-all route:
```nim
app.get("/*", proc(ctx: Context) {.async.} =
  ctx.send(karaxHtml, Http200, "text/html")
)
```

**Severity:** Low — one route fixes it.

---

## 14. Request Body Is Always a String (No Streaming)

**Problem:** `ctx.request.body` is a `string`, meaning large file uploads are fully buffered in memory. Jester has the same limitation, but modern frameworks usually expose a stream or `FormPart` iterator.

**Severity:** Low — existing limitation inherited from asynchttpserver.
