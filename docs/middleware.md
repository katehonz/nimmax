# Middleware

Middleware functions process requests before they reach your route handlers, and can process responses after handlers complete. NimMax uses an onion-model middleware system.

## How Middleware Works

Each middleware receives the `Context` and a `switch` proc. Calling `await switch(ctx)` passes control to the next middleware in the chain. Code before `switch` runs before the handler; code after runs after.

```
Request → Middleware1 (pre) → Middleware2 (pre) → Handler → Middleware2 (post) → Middleware1 (post) → Response
```

## Global Middleware

Applied to every request:

```nim
let app = newApp()
app.use(loggingMiddleware())
app.use(corsMiddleware())
```

## Route-Level Middleware

Applied only to specific routes:

```nim
app.get("/admin", adminHandler, middlewares = @[authMiddleware()])
app.post("/api/data", dataHandler, middlewares = @[rateLimitMiddleware()])
```

## Writing Custom Middleware

### Basic Pattern

```nim
proc myMiddleware(): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    # Pre-processing (before handler)
    echo "Incoming request: " & ctx.request.url.path

    await switch(ctx)  # Call next middleware / handler

    # Post-processing (after handler)
    echo "Response code: " & $ctx.response.code.int
```

### Middleware with Configuration

```nim
proc rateLimitMiddleware(maxRequests: int, windowSeconds: int): HandlerAsync =
  var requestCounts = initTable[string, (int, float)]()

  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let ip = ctx.request.headers.getHeader("X-Forwarded-For", "unknown")
    let now = epochTime()

    if requestCounts.hasKey(ip):
      let (count, windowStart) = requestCounts[ip]
      if now - windowStart > windowSeconds.float:
        requestCounts[ip] = (1, now)
      elif count >= maxRequests:
        ctx.abortRequest(Http429, "Too many requests")
        return
      else:
        requestCounts[ip] = (count + 1, windowStart)
    else:
      requestCounts[ip] = (1, now)

    await switch(ctx)
```

### Conditional Middleware

```nim
proc onlyPaths(paths: seq[string], middleware: HandlerAsync): HandlerAsync =
  let p = paths
  let m = middleware
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    var matched = false
    for path in p:
      if ctx.request.url.path.startsWith(path):
        matched = true
        break
    if matched:
      await m(ctx)
    else:
      await switch(ctx)
```

## Built-in Middleware Reference

### loggingMiddleware

Logs request method, path, status code, and elapsed time.

```nim
app.use(loggingMiddleware(appName = "MyApp"))
# Output: MyApp | GET /hello -> 200 (0.05ms)
```

### debugRequestMiddleware

Prints full request details to stdout.

```nim
app.use(debugRequestMiddleware())
```

### debugResponseMiddleware

Prints full response details to stdout after the handler runs.

```nim
app.use(debugResponseMiddleware())
```

### stripPathMiddleware

Removes trailing slashes from request paths.

```nim
app.use(stripPathMiddleware())
# /hello/ → /hello
```

### httpRedirectMiddleware

Redirects requests from one path to another.

```nim
app.use(httpRedirectMiddleware("/old-page", "/new-page"))
```

### corsMiddleware

Handles Cross-Origin Resource Sharing (CORS).

```nim
app.use(corsMiddleware(
  allowOrigins = @["https://example.com", "https://app.example.com"],
  allowMethods = @["GET", "POST", "PUT", "DELETE", "PATCH"],
  allowHeaders = @["Content-Type", "Authorization", "X-Requested-With"],
  exposeHeaders = @["X-Total-Count"],
  allowCredentials = true,
  maxAge = 3600,                     # preflight cache duration (seconds)
  excludePaths = @["/health", "/api/public"]  # skip CORS for these paths
))
```

### csrfMiddleware

Provides CSRF protection using double-submit cookie pattern.

```nim
app.use(csrfMiddleware(
  tokenName = "nimmax_csrf_token",   # form field name
  cookieName = "nimmax_csrf"         # cookie name
))
```

### basicAuthMiddleware

HTTP Basic Authentication.

```nim
proc verifyUser(username, password: string): bool {.gcsafe.} =
  return username == "admin" and password == "secret"

app.use(basicAuthMiddleware(
  realm = "Admin Area",
  verifyHandler = verifyUser
))
```

### staticFileMiddleware

Serves static files from one or more directories.

```nim
app.use(staticFileMiddleware("public", "assets"))
```

Features:
- Automatic Content-Type detection
- ETag generation and If-None-Match (304 responses)
- Cache-Control headers (1 hour default)

### compressionMiddleware

Real gzip/deflate response compression using the [zippy](https://github.com/guzba/zippy) library (pure Nim, no system dependencies).

```nim
app.use(compressionMiddleware(
  minSize = 1024,
  level = clDefault,
  excludePaths = @["/ws", "/stream"]
))
```

Parameters:
- `minSize` (default: 1024) — Minimum response size in bytes to compress
- `level` — Compression level: `clNone`, `clBestSpeed`, `clDefault` (6), `clBestCompression` (9)
- `excludePaths` — Paths to exclude from compression (e.g., WebSocket, streaming)

The middleware:
1. Checks `Accept-Encoding` header for `gzip` or `deflate`
2. After the handler runs, compresses the response body if it exceeds `minSize`
3. Skips already-compressed content types (images, audio, video, zip)
4. Sets `Content-Encoding`, `Content-Length`, and `Vary: Accept-Encoding` headers
5. Only applies compression if it actually reduces the response size

### jsonBodyMiddleware

Automatically parses JSON request bodies and stores the result accessible via `ctx.getJsonBody()`.

```nim
app.use(jsonBodyMiddleware())

app.post("/api/data", proc(ctx: Context) {.async.} =
  let data = ctx.getJsonBody()
  let name = data["name"].getStr()
  ctx.json(%*{"received": name})
)
```

The middleware checks `Content-Type: application/json` and only parses when the header matches.

See also: `ctx.getJsonBody()` and `ctx.getJsonBody(T)` in [Request & Response](request-response.md).

### formBodyMiddleware

Automatically parses `application/x-www-form-urlencoded` and `multipart/form-data` POST/PUT/PATCH bodies, populating `ctx.request.postParams`.

```nim
app.use(formBodyMiddleware())

app.post("/submit", proc(ctx: Context) {.async.} =
  let name = ctx.getPostParam("name")
  let email = ctx.getPostParam("email")
  ctx.json(%*{"name": name, "email": email})
)
```

After the middleware runs, `ctx.getParam()` (unified accessor) is also automatically populated with form values.

### sessionMiddleware

Session management with pluggable backends.

```nim
# In-memory sessions
app.use(sessionMiddleware(
  backend = sbMemory,
  sessionName = "nimmax_session",
  maxAge = 86400,        # 24 hours
  path = "/",
  httpOnly = true,
  secure = false,        # set true in production with HTTPS
  sameSite = "Lax"
))

# Signed cookie sessions (no server-side storage)
app.use(sessionMiddleware(
  backend = sbSignedCookie,
  secretKey = SecretKey("my-secret-key"),
  sessionName = "nimmax_session",
  maxAge = 86400
))
```

## Middleware Composition

### compose

Combine multiple middleware into one:

```nim
let securityMiddleware = compose(@[
  corsMiddleware(),
  csrfMiddleware(),
  loggingMiddleware()
])
app.use(securityMiddleware)
```

### chain

Run middleware before and after a handler:

```nim
let wrappedHandler = chain(loggingMiddleware(), errorHandlerMiddleware())
app.use(wrappedHandler)
```

## Middleware with Group

Apply middleware to a group of routes:

```nim
let api = app.newGroup("/api", middlewares = @[corsMiddleware()])
let secure = api.newGroup("/admin", middlewares = @[authMiddleware()])

secure.get("/dashboard", handler)  # has CORS + auth
```
