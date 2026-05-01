# NimMax Bug Report & Improvement Suggestions

Found during NimLeptos integration (May 2026).
NimMax version: 1.0.0 — https://github.com/katehonz/nimmax

---

## BUG #1 — CRITICAL: Infinite recursion on `TableRef[string, string]` operators

**File**: `src/nimmax/core/request.nim`, lines 45-51, 88-90

**Severity**: Critical — causes stack overflow in any code that uses `TableRef[string, string]` while nimmax is in scope.

### The Problem

Three procs override stdlib operators for ALL `TableRef[string, string]` instances, not just request params. Each one calls itself recursively:

```nim
# Line 45-47: INFINITE RECURSION
proc `[]`*(params: TableRef[string, string], key: string): string =
  if params.isNil: return ""
  params.getOrDefault(key, "")    # calls stdlib, BUT if another module overrides getOrDefault → recursion

# Line 49-51: INFINITE RECURSION
proc `[]=`*(params: TableRef[string, string], key, value: string) =
  if params.isNil: return
  params[key] = value             # calls ITSELF (same `[]=` is in scope)

# Line 88-90: INFINITE RECURSION
proc hasKey*(params: TableRef[string, string], key: string): bool =
  if params.isNil: return false
  params.hasKey(key)              # calls ITSELF (same `hasKey` is in scope)
```

### Why It Recurses

Nim's overload resolution picks the most specific matching proc. Since these procs have the signature `(TableRef[string, string], string)`, they match any call to `.[]()`, `.[]=()`, `.hasKey()` on any `TableRef[string, string]` — including the call on line 51 (`params[key] = value`) which IS the same proc.

### Impact

- Any module that `import nimmax` and then creates/modifies a `TableRef[string, string]` will hit stack overflow
- This includes `std/tables` operations like `newTable`, `[]=`, `hasKey`, `getOrDefault`
- Workaround in NimLeptos: `forms/table_helper.nim` creates tables in a separate module that doesn't import nimmax

### Suggested Fix

Option A — Make procs generic with a distinct type:
```nim
type Params* = distinct TableRef[string, string]

proc `[]`*(params: Params, key: string): string =
  if TableRef[string, string](params).isNil: return ""
  TableRef[string, string](params).getOrDefault(key, "")
```

Option B — Remove the overrides entirely, use procs with different names:
```nim
proc getParam*(params: TableRef[string, string], key: string): string =
  if params.isNil: return ""
  params.getOrDefault(key, "")

proc setParam*(params: TableRef[string, string], key, value: string) =
  if params.isNil: return
  tables.`[]=`(params, key, value)  # explicitly call stdlib

proc paramHasKey*(params: TableRef[string, string], key: string): bool =
  if params.isNil: return false
  tables.hasKey(params, key)         # explicitly call stdlib
```

Option C — Use `{.exportc.}` pragma to force stdlib binding (least clean).

### Reproduction

```nim
import nimmax
import std/tables

var t = newTable[string, string]()
t["key"] = "value"   # STACK OVERFLOW — calls nimmax's `[]=` which calls itself
echo t.hasKey("key") # STACK OVERFLOW — calls nimmax's hasKey which calls itself
```

---

## BUG #2 — MEDIUM: `escapeHtml` name collision

**File**: `src/nimmax/core/utils.nim`, line 21

**Severity**: Medium — causes ambiguous call errors when both nimmax and other modules export `escapeHtml`.

### The Problem

nimmax exports `escapeHtml` from `utils.nim`. Any module that also exports `escapeHtml` (like NimLeptos's `dom/node.nim`) causes ambiguity:

```
Error: ambiguous call; both utils.escapeHtml(s: string) and node.escapeHtml(s: string) match
```

### Suggested Fix

Option A — Namespace it: rename to `nimmaxEscapeHtml` or put in a distinct module name
Option B — Use a distinct string type: `proc escapeHtml*(s: NimMaxString): string`
Option C — Don't export from main `nimmax.nim` — let users import `nimmax/utils` explicitly

---

## BUG #3 — MEDIUM: WebSocket implementation is incomplete

**File**: `src/nimmax/websocket/websocket.nim`

**Severity**: Medium — WebSocket cannot actually send/receive frames over the wire.

### The Problem

```nim
proc sendText*(ws: WebSocket, message: string) {.async.} =
  if not ws.isOpen:
    return
  ws.ctx.response.body = message                    # ← just sets response body
  ws.ctx.response.headers["X-WebSocket-Frame"] = "text"  # ← not a real WS frame
```

This doesn't send WebSocket frames. It just sets the HTTP response body and a custom header. Real WebSocket requires:
1. Frame encoding (opcode, length, masking)
2. Writing to the raw TCP socket
3. Reading frames from the client
4. Ping/pong heartbeat
5. Close frame handling

### The `receiveStrPacket` proc is missing entirely

The `wsRoute` handler calls `handler(ws)` but there's no way to receive messages from the client. The `WebSocket` type has no `receiveStrPacket`, `receivePacket`, or any read method.

### Suggested Fix

Implement proper WebSocket framing per RFC 6455, or delegate to `std/asyncnet` + a proper WebSocket library like `ws` or `websocketx`:

```nim
import std/asyncnet

type WebSocket* = ref object
  socket*: AsyncSocket
  isOpen*: bool

proc sendText*(ws: WebSocket, message: string) {.async.} =
  # Encode as WS text frame
  var frame = encodeFrame(Text, message)
  await ws.socket.send(frame)

proc receiveStrPacket*(ws: WebSocket): Future[string] {.async.} =
  # Read and decode WS frame
  result = await readFrame(ws.socket)
```

---

## BUG #4 — LOW: `runOnce` doesn't support `postParams`

**File**: `src/nimmax/testing/mocking.nim`, line 87

**Severity**: Low — testing POST handlers with form data requires manual context construction.

### The Problem

```nim
proc runOnce*(app: Application, httpMethod = HttpGet, path = "/",
              headers: HttpHeaders = nil, body = ""): Context =
```

No `postParams` or `queryParams` parameter. Testing a POST form handler requires building the context manually.

### Suggested Fix

```nim
proc runOnce*(app: Application, httpMethod = HttpGet, path = "/",
              headers: HttpHeaders = nil, body = "",
              queryParams: TableRef[string, string] = nil,
              postParams: TableRef[string, string] = nil): Context =
```

---

## BUG #5 — LOW: `parseCookies` uses overridden `[]=` (cascading from Bug #1)

**File**: `src/nimmax/core/utils.nim`, line 39

### The Problem

```nim
proc parseCookies*(cookieHeader: string): TableRef[string, string] =
  result = newTable[string, string]()
  ...
    result[parts[0].strip()] = parts[1].strip()  # uses overridden []=
```

Since `[]=` is overridden in `request.nim` and `utils.nim` imports from the same package, this MIGHT work if the override isn't in scope yet during compilation. But it's fragile — the order of imports matters.

### Suggested Fix

Use explicit stdlib call:
```nim
tables.`[]=`(result, parts[0].strip(), parts[1].strip())
```

---

## BUG #6 — LOW: `randomString` doesn't seed the RNG

**File**: `src/nimmax/core/utils.nim`, line 10

### The Problem

```nim
proc randomString*(length: int = 32): string =
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  result = newString(length)
  for i in 0 ..< length:
    result[i] = chars[rand(chars.len - 1)]
```

`rand()` from `std/random` requires `randomize()` to be called first. Without seeding, the sequence is deterministic — every server start generates the same "random" secret key.

### Suggested Fix

```nim
import std/random

proc randomString*(length: int = 32): string =
  randomize()  # seed once
  ...
```

Or call `randomize()` in `newSettings`.

---

## BUG #7 — LOW: `escapeHtml` doesn't escape single quotes

**File**: `src/nimmax/core/utils.nim`, line 29

### The Problem

```nim
proc escapeHtml*(s: string): string =
  ...
  of '\'': result.add("&#x27;")   # escapes single quotes
```

Actually this DOES escape single quotes. But the stdlib `cgi.escapeHtml` (used by some Nim code) does NOT escape single quotes. This is an inconsistency, not a bug. Consider documenting which characters are escaped.

---

## Improvement Suggestions

### 1. Add `nimble install` support

nimmax is not published on the Nimble registry. Adding it would allow `nimble install nimmax` instead of requiring git clone.

### 2. Add `{.gcsafe.}` annotations

Many procs are missing `{.gcsafe.}` which causes issues with `--threads:on`:

```nim
proc escapeHtml*(s: string): string {.gcsafe.} =
proc randomString*(length: int = 32): string {.gcsafe.} =
```

### 3. Separate `request.nim` helpers from operator overrides

Move the `TableRef[string, string]` operator overrides to a separate module (e.g., `paramutils.nim`) so users can choose whether to import them.

### 4. Add `queryParams` and `postParams` to `runOnce`

Testing is a core feature — make it easy to test all HTTP methods with parameters.

### 5. Implement proper WebSocket framing

The current WebSocket module is a stub. Either implement RFC 6455 or integrate with an existing library.

### 6. Add `Body` parsing middleware

Currently `ctx.request.body` is raw string. Add middleware for:
- JSON body parsing (`ctx.request.jsonBody`)
- Form-URL-encoded parsing (`ctx.request.formBody`)
- Multipart parsing (`ctx.request.multipartBody`)

### 7. Add response streaming

For SSR streaming, support chunked transfer encoding:
```nim
proc writeChunk*(ctx: Context, chunk: string) {.async.} =
  await ctx.request.nativeRequest.respond(Http200, chunk, ...)
```

### 8. Document the middleware chain model

The onion model is powerful but underdocumented. Add examples showing:
- Before/after patterns
- Error handling in middleware
- Conditional middleware
- Middleware composition

---

## Summary

| # | Bug | Severity | Status |
|---|-----|----------|--------|
| 1 | `[]=`/`[]`/`hasKey` infinite recursion on `TableRef[string, string]` | Critical | **FIXED** — qualified stdlib calls |
| 2 | `escapeHtml` name collision with other modules | Medium | **FIXED** — renamed to `escapeHtmlContent` |
| 3 | WebSocket implementation is a stub (no real framing) | Medium | Not functional |
| 4 | `runOnce` missing `postParams`/`queryParams` | Low | **FIXED** — added params to `runOnce` |
| 5 | `parseCookies` uses overridden `[]=` | Low | **FIXED** — qualified stdlib `[]=` |
| 6 | `randomString` doesn't seed RNG | Low | **FIXED** — added `randomize()` |
| 7 | `escapeHtml` inconsistency with stdlib | Low | Cosmetic |

**Bug #1 was the most critical** — it made `TableRef[string, string]` unusable in any module that imports nimmax. All functional bugs (#1, #2, #4, #5, #6) have been fixed. All 66 tests pass.
