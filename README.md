# NimMax

**A modern, high-performance web framework for [Nim](https://nim-lang.org/).**

NimMax is designed for building fast, scalable web applications and APIs with an elegant, type-safe API. It draws inspiration from frameworks like Express.js, FastAPI, and Sinatra while leveraging Nim's unique strengths — compile-time efficiency, zero-cost abstractions, and native performance.

[![Nim](https://img.shields.io/badge/Nim-%3E%3D2.0.0-FFE000?logo=nim&logoColor=white)](https://nim-lang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Features

- **Fast Routing** — Pattern-based routing with named parameters, wildcards, and route groups (sorted by specificity for optimal matching)
- **Middleware Pipeline** — Onion-model middleware with composition support
- **Type-Safe Parameters** — `ctx.getInt("id")`, `ctx.getFloat("price")`, `ctx.getBool("active")` returning `Option[T]`
- **Session Management** — In-memory and signed-cookie session backends
- **CSRF Protection** — Built-in CSRF token middleware
- **CORS Support** — Configurable Cross-Origin Resource Sharing
- **Form Validation** — Declarative validation with 15+ built-in validators
- **Static File Serving** — ETag, Last-Modified, Range requests, If-None-Match, If-Modified-Since
- **WebSocket Support** — Full RFC 6455 implementation with frame encoding/decoding, ping/pong, binary/text messages
- **JSON Body Parsing** — Built-in middleware for automatic JSON request body parsing
- **Response Streaming** — Chunked transfer encoding for streaming SSR and large responses
- **Response Compression** — Real gzip/deflate compression via zippy (pure Nim)
- **OpenAPI / Swagger** — Auto-generate API documentation from your code
- **LRU/LFU Cache** — In-memory caching with TTL expiration
- **Cryptographic Signing** — Sign and verify data with timed expiration
- **Password Hashing** — PBKDF2-based password hashing and verification
- **Rate Limiting** — Sliding window rate limiter with configurable limits
- **Request ID Tracing** — Automatic request ID generation and propagation
- **Response Compression** — Gzip/Deflate compression for responses
- **Graceful Shutdown** — Clean shutdown with active request draining and configurable timeout
- **i18n** — Internationalization support
- **Testing Utilities** — Mock requests, run-once testing, debug response output
- **Environment Config** — `.env` files, JSON config, environment variables
- **Hunos Backend** — Optional high-performance multi-threaded HTTP/1.1 + HTTP/2 server backend
- **Security Headers** — Built-in middleware for HSTS, CSP, X-Frame-Options, and more

---

## Quick Start

### Prerequisites

- [Nim](https://nim-lang.org/) >= 2.0.0
- [Nimble](https://github.com/nim-lang/nimble) package manager

### Installation

```bash
nimble install nimmax
```

Or add to your `.nimble` file:

```nim
requires "nimmax >= 1.0.0"
```

### Hello World

```nim
import nimmax

proc hello(ctx: Context) {.async.} =
  ctx.html("<h1>Hello, NimMax!</h1>")

proc main() =
  let app = newApp()
  app.get("/", hello)
  app.run()

main()
```

Run it:

```bash
nim c -r app.nim
# Server starts on http://0.0.0.0:8080
```

### Hunos Backend (Multi-threaded)

For maximum performance on multi-core CPUs, use the optional Hunos backend:

```nim
import nimmax/hunos  # <-- use Hunos backend

proc hello(ctx: Context) {.async.} =
  ctx.html("<h1>Hello from Hunos!</h1>")

let app = newApp()
app.get("/", hello)
app.runHunos(port = Port(8080))
```

Compile with threads and ARC:

```bash
nim c --threads:on --mm:arc -r app.nim
```

---

## Routing

### Basic Routes

```nim
app.get("/hello", handler)
app.post("/submit", handler)
app.put("/update", handler)
app.delete("/remove", handler)
app.patch("/modify", handler)
app.all("/catch-all", handler)  # matches all HTTP methods
```

### Named Parameters

```nim
app.get("/user/{id}", proc(ctx: Context) {.async.} =
  let id = ctx.getPathParam("id")
  ctx.json(%*{"user_id": id})
)
```

### Wildcard Routes

```nim
app.get("/files/*", proc(ctx: Context) {.async.} =
  let filePath = ctx.getPathParam("*")
  ctx.text("Requested file: " & filePath)
)
```

### Route Groups

```nim
let api = app.newGroup("/api/v1")
api.get("/users", listUsers)         # GET /api/v1/users
api.post("/users", createUser)       # POST /api/v1/users
api.get("/users/{id}", getUser)      # GET /api/v1/users/{id}
```

Groups support nesting and middleware inheritance:

```nim
let api = app.newGroup("/api", middlewares = @[authMiddleware()])
let admin = api.newGroup("/admin")
admin.get("/dashboard", dashboardHandler)  # requires auth
```

### Named Routes & URL Building

```nim
app.get("/user/{id}", handler, name = "user_detail")

# Build URL from route name
let url = ctx.urlFor("user_detail", @[("id", "42")])
# Returns: "/user/42"
```

---

## Middleware

### Global Middleware

```nim
let app = newApp()
app.use(loggingMiddleware())
app.use(corsMiddleware())
```

### Route-Level Middleware

```nim
app.get("/admin", adminHandler, middlewares = @[authMiddleware()])
```

### Writing Custom Middleware

```nim
proc timerMiddleware(): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let start = cpuTime()
    await switch(ctx)  # call next middleware / handler
    let elapsed = cpuTime() - start
    echo "Request took " & formatFloat(elapsed * 1000, ffDecimal, 2) & "ms"
```

### Built-in Middleware

| Middleware | Description |
|---|---|
| `loggingMiddleware()` | Logs method, path, status code, and elapsed time |
| `debugRequestMiddleware()` | Prints full request details |
| `debugResponseMiddleware()` | Prints full response details |
| `stripPathMiddleware()` | Removes trailing slashes from paths |
| `corsMiddleware()` | Cross-Origin Resource Sharing |
| `csrfMiddleware()` | CSRF token validation |
| `basicAuthMiddleware()` | HTTP Basic Authentication |
| `staticFileMiddleware()` | Serves static files from directories |
| `sessionMiddleware()` | Session management (memory & signed cookie) |
| `rateLimitMiddleware()` | Rate limiting with sliding window |
| `requestIdMiddleware()` | Request ID tracing |
| `compressionMiddleware()` | Real gzip/deflate compression (zippy) |
| `jsonBodyMiddleware()` | Automatic JSON body parsing |
| `securityHeadersMiddleware()` | HSTS, CSP, X-Frame-Options, XSS protection |

---

## Rate Limiting

```nim
import nimmax/middlewares

let limiter = newRateLimiter(maxRequests = 100, windowSeconds = 60)
app.use(rateLimitMiddleware(limiter))

app.get("/api", proc(ctx: Context) {.async.} =
  ctx.json(%*{"message": "Rate limited API"})
)
```

### Custom Key Extractor

```nim
app.use(rateLimitMiddleware(limiter,
  keyExtractor = proc(ctx: Context): string {.gcsafe.} =
    return ctx.request.headers.getHeader("X-User-ID", ctx.request.ip)
))
```

---

## Request ID Tracing

```nim
app.use(requestIdMiddleware())

app.get("/api", proc(ctx: Context) {.async.} =
  let requestId = ctx["X-Request-ID"].getStr("")
  ctx.json(%*{"requestId": requestId})
)
```

---

## Response Compression

Real gzip/deflate compression using the [zippy](https://github.com/guzba/zippy) library (pure Nim, no system dependencies):

```nim
app.use(compressionMiddleware(minSize = 1024, level = clBestSpeed))
```

| Parameter | Default | Description |
|---|---|---|
| `minSize` | 1024 | Minimum response size in bytes to compress |
| `level` | `clDefault` | Compression level: `clNone`, `clBestSpeed`, `clDefault`, `clBestCompression` |
| `excludePaths` | `@[]` | Paths to exclude from compression |

---

## Graceful Shutdown

The server supports graceful shutdown with configurable timeout:

```nim
let settings = newSettings(shutdownTimeout = 30)
let app = newApp(settings = settings)
app.run()
```

On shutdown signal (Ctrl+C), the server:
1. Stops accepting new connections
2. Waits for active requests to complete (up to timeout)
3. Runs shutdown event handlers
4. Exits cleanly

---

## Static File Improvements

- **ETag support** — Automatically generated based on file modification time and size
- **Last-Modified** — Returns file modification time
- **If-None-Match** — Caching support with ETag
- **If-Modified-Since** — Alternative caching check
- **Range requests** — Partial content support for resumable downloads
- **Accept-Ranges** — Advertises byte-range support

---

## Route Specificity Optimization

Routes are now automatically sorted by specificity for optimal matching:

```
/users/{id}     (specificity: 150) — matched first
/users/*        (specificity: 101) — matched second
/{any}          (specificity: 51)  — matched last
```

This ensures `/users/123` correctly matches `/users/{id}` instead of `/users/*`.

---

## Request

### Accessing Parameters

```nim
proc handler(ctx: Context) {.async.} =
  # Path parameters
  let id = ctx.getPathParam("id")
  let idInt = ctx.getInt("id")           # Option[int]
  let price = ctx.getFloat("price")      # Option[float]

  # Query parameters
  let page = ctx.getQueryParam("page")
  let active = ctx.getQueryParamBool("active")  # Option[bool]

  # POST parameters
  let name = ctx.getPostParam("name")

  # Cookies
  let token = ctx.getCookie("session")

  # Headers
  let auth = ctx.request.headers.getHeader("Authorization")

  # Body
  let body = ctx.request.body
```

### Typed Parameter Access

All typed accessors return `Option[T]` for safe handling:

```nim
let userId = ctx.getInt("id")        # Option[int]
if userId.isSome:
  echo "User ID: " & $userId.get
else:
  ctx.abortRequest(Http400, "Invalid user ID")
```

---

## Response

### Convenience Methods

```nim
proc handler(ctx: Context) {.async.} =
  ctx.html("<h1>Hello</h1>")                          # text/html
  ctx.json(%*{"status": "ok"})                         # application/json
  ctx.text("Plain text response")                      # text/plain
  ctx.redirect("/new-location")                        # 301 redirect
  ctx.temporaryRedirect("/temp")                       # 302 redirect
```

### Setting Cookies

```nim
ctx.setCookie("session", "abc123",
  path = "/",
  maxAge = 86400,
  httpOnly = true,
  secure = true,
  sameSite = "Strict"
)

ctx.deleteCookie("session")
```

### Custom Response

```nim
ctx.response.code = Http200
ctx.response.body = "Custom body"
ctx.response.headers["X-Custom"] = "value"
```

---

## Sessions

### In-Memory Sessions

```nim
let app = newApp()
app.use(sessionMiddleware(backend = sbMemory, maxAge = 86400))

app.get("/login", proc(ctx: Context) {.async.} =
  ctx.session["user"] = "alice"
  ctx.session["role"] = "admin"
  ctx.html("Logged in!")
)

app.get("/profile", proc(ctx: Context) {.async.} =
  let user = ctx.session["user"]
  ctx.html("Hello, " & user & "!")
)
```

### Signed Cookie Sessions

```nim
app.use(sessionMiddleware(
  backend = sbSignedCookie,
  secretKey = SecretKey("my-secret-key"),
  maxAge = 86400
))
```

### Flash Messages

```nim
# Set flash message
ctx.flash("Item created successfully!", flSuccess)

# Get and clear flash messages
let msgs = ctx.getFlashedMsgs()
for msg in msgs:
  echo msg

# With categories
let categorized = ctx.getFlashedMsgsWithCategory()
for (level, msg) in categorized:
  echo $level & ": " & msg
```

---

## Validation

```nim
import nimmax/validater

let validator = newFormValidator()
validator.addRule("email", required())
validator.addRule("email", isEmail())
validator.addRule("age", required())
validator.addRule("age", isInt())
validator.addRule("age", minValue(0))
validator.addRule("age", maxValue(150))
validator.addRule("name", required())
validator.addRule("name", minLength(2))
validator.addRule("name", maxLength(100))

app.post("/register", proc(ctx: Context) {.async.} =
  let errors = validator.validateForm(ctx.request.postParams)
  if errors.len > 0:
    ctx.json(%*{"errors": errors}, Http422)
    return
  ctx.json(%*{"status": "ok"})
)
```

### Built-in Validators

| Validator | Description |
|---|---|
| `required()` | Field must not be empty |
| `isInt()` | Must be a valid integer |
| `isFloat()` | Must be a valid float |
| `isBool()` | Must be a boolean value |
| `isEmail()` | Must be a valid email address |
| `isUrl()` | Must be a valid URL |
| `minValue(n)` | Minimum numeric value |
| `maxValue(n)` | Maximum numeric value |
| `minLength(n)` | Minimum string length |
| `maxLength(n)` | Maximum string length |
| `matchPattern(re)` | Must match regex pattern |
| `equals(s)` | Must equal string |
| `oneOf(list)` | Must be one of the given values |

---

## Security

### CSRF Protection

```nim
app.use(csrfMiddleware())

app.get("/form", proc(ctx: Context) {.async.} =
  let tokenInput = ctx.csrfTokenInput()
  ctx.html("""
    <form method="POST" action="/submit">
      """ & tokenInput & """
      <input type="text" name="name">
      <button type="submit">Submit</button>
    </form>
  """)
)
```

### CORS

```nim
app.use(corsMiddleware(
  allowOrigins = @["https://example.com"],
  allowMethods = @["GET", "POST", "PUT", "DELETE"],
  allowHeaders = @["Content-Type", "Authorization"],
  allowCredentials = true,
  maxAge = 3600
))
```

### Security Headers

```nim
import nimmax/middlewares

app.use(securityHeadersMiddleware())
```

Defaults include:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 1; mode=block`
- `Strict-Transport-Security: max-age=63072000; includeSubDomains`
- `Content-Security-Policy: default-src 'self'`
- `Referrer-Policy: strict-origin-when-cross-origin`

Custom configuration:

```nim
app.use(securityHeadersMiddleware(SecurityConfig(
  frameOptions: "SAMEORIGIN",
  csp: "default-src 'self'; script-src 'self' 'unsafe-inline'",
  hsts: "max-age=31536000"
)))
```

### Basic Auth

```nim
app.use(basicAuthMiddleware(
  realm = "Admin Area",
  verifyHandler = proc(username, password: string): bool {.gcsafe.} =
    return username == "admin" and password == "secret"
))
```

### Password Hashing

```nim
import nimmax/security

let hashed = hashPassword("my-secret-password")
let valid = verifyPassword("my-secret-password", hashed)  # true
```

### Cryptographic Signing

```nim
import nimmax/security

let signer = newSigner(SecretKey("my-key"))
let signed = signer.sign("important-data")
let valid = signer.validate(signed)  # true
let original = signer.unsign(signed)  # "important-data"

# Timed signing (expires after 3600 seconds)
let timedSigner = newTimedSigner(SecretKey("my-key"), maxAge = 3600)
let timedSigned = timedSigner.sign("temp-data")
```

---

## JSON Body Parsing

```nim
import nimmax/middlewares

app.use(jsonBodyMiddleware())

app.post("/api/users", proc(ctx: Context) {.async.} =
  let data = ctx.getJsonBody()
  let name = data["name"].getStr()
  ctx.json(%*{"created": name})
)
```

### Typed JSON Parsing

```nim
type User = object
  name: string
  email: string

app.post("/api/users", proc(ctx: Context) {.async.} =
  let user = ctx.getJsonBody(User)
  ctx.json(%*{"created": user.name})
)
```

---

## Response Streaming

Stream responses using chunked transfer encoding — useful for SSR, large file downloads, or real-time data.

```nim
app.get("/stream", proc(ctx: Context) {.async.} =
  ctx.startChunked()

  for i in 1 .. 5:
    await ctx.writeChunk("Chunk " & $i & "\n")
    await sleepAsync(500)

  await ctx.endChunked()
)
```

Streaming integrates naturally with **NimLeptos** SSR for progressive page rendering.

---

## NimLeptos Integration

NimMax is the recommended backend for [NimLeptos](https://github.com/katehonz/brenan/tree/main/nimleptos), a fine-grained reactive web framework for Nim (Leptos port).

```nim
import nimleptos/server

let app = newNimLeptosApp(title = "My App")

app.get("/", proc(ctx: Context) {.async.} =
  ctx.render(buildHtml(
    tdiv(class = "container"):
      h1("Hello from NimLeptos!")
      p("Rendered on the server with NimMax")
  ), app)
)

app.run()
```

NimMax provides the HTTP layer (routing, middleware, sessions, CSRF, compression, WebSocket), while NimLeptos handles the reactive UI with signals, effects, and SSR hydration.

---

## Configuration

### Programmatic

```nim
let settings = newSettings(
  address = "0.0.0.0",
  port = Port(8080),
  debug = true,
  appName = "MyApp",
  secretKey = "my-secret-key",
  shutdownTimeout = 30
)
let app = newApp(settings = settings)
```

### From JSON Config

Create `.config/config.json`:

```json
{
  "address": "0.0.0.0",
  "port": 8080,
  "debug": true,
  "nimmax": {
    "secretKey": "my-secret-key",
    "appName": "MyApp"
  }
}
```

```nim
let settings = loadSettings(".config/config.json")
let app = newApp(settings = settings)
```

### Environment Variables

Create `.env`:

```
DATABASE_URL=postgres://localhost/mydb
API_KEY=abc123
```

```nim
import nimmax/configure

let env = loadEnv()
let dbUrl = env.get("DATABASE_URL")
let apiKey = env.get("API_KEY", "default-key")
```

### Per-Environment Configs

```
.config/
  config.json           # default
  config.debug.json     # development
  config.production.json # production
```

Set `NIMMAX_ENV=production` to load `config.production.json`.

---

## Static Files

### Via Middleware

```nim
app.use(staticFileMiddleware("public", "assets"))
```

### In Handlers

```nim
app.get("/download/{file}", proc(ctx: Context) {.async.} =
  let filename = ctx.getPathParam("file")
  ctx.staticFileResponse("uploads/" & filename, downloadName = filename)
)
```

---

## WebSocket

Full RFC 6455 implementation with support for text and binary messages, ping/pong, and graceful close.

```nim
import nimmax/websocket

app.get("/ws", wsRoute(proc(ws: WebSocket) {.async.} =
  echo "Client connected"

  while ws.readyState == wsOpen:
    let msg = await ws.receiveStrPacket()
    if msg.len > 0:
      echo "Received: " & msg
      await ws.sendText("Echo: " & msg)

  echo "Client disconnected, code: " & $ws.closeCode
))
```

### Key API

| Method | Description |
|---|---|
| `ws.sendText(msg)` | Send a text frame |
| `ws.sendBinary(data)` | Send a binary frame |
| `ws.sendPing(data)` | Send a ping frame |
| `ws.receiveStrPacket()` | Receive a text message |
| `ws.receiveBinaryPacket()` | Receive a binary message |
| `ws.close(code, reason)` | Close the connection gracefully |
| `ws.loopMessages(handler)` | Continuous message loop |
| `ws.readyState` | Current state: `wsConnecting`, `wsOpen`, `wsClosing`, `wsClosed` |
| `ws.closeCode` | Close code received from client |

---

## OpenAPI / Swagger

```nim
import nimmax/openapi

let spec = newOpenApiSpec(
  title = "My API",
  description = "A sample API",
  version = "1.0.0"
)
spec.addPath("/users", "GET", "List all users", tags = @["users"])
spec.addPath("/users/{id}", "GET", "Get user by ID", tags = @["users"])

app.serveDocs(spec)  # Adds /docs and /openapi.json endpoints
```

---

## Caching

### LRU Cache

```nim
import nimmax/cache

var cache = initLRUCache[string, JsonNode](capacity = 1000, defaultTimeout = 3600)
cache.put("user:1", %*{"name": "Alice"})
let user = cache.get("user:1")  # Option[JsonNode]
```

### LFU Cache

```nim
var cache = initLFUCache[string, string](capacity = 500, defaultTimeout = 1800)
cache.put("key", "value")
let val = cache.get("key")  # Option[string]
```

---

## Testing

```nim
import nimmax/mocking

let app = mockApp()

# Add your routes
app.get("/hello", proc(ctx: Context) {.async.} =
  ctx.html("Hello!")
)

# Test a request
let ctx = app.runOnce(HttpGet, "/hello")
assert ctx.response.code == Http200
assert ctx.response.body == "Hello!"

# Debug output
debugResponse(ctx)
```

---

## Error Handling

### Custom Error Pages

```nim
app.registerErrorHandler(Http404, proc(ctx: Context) {.async.} =
  ctx.html("<h1>404 - Page Not Found</h1>", Http404)
)

app.registerErrorHandler(Http500, proc(ctx: Context) {.async.} =
  ctx.html("<h1>500 - Something went wrong</h1>", Http500)
)
```

### Abort Requests

```nim
app.get("/admin", proc(ctx: Context) {.async.} =
  if not isAdmin(ctx):
    ctx.abortRequest(Http403, "Forbidden")
  ctx.html("Admin panel")
)
```

---

## Application Lifecycle

### Startup & Shutdown Events

```nim
app.onStart(proc() =
  echo "Server is starting..."
  initDatabase()
)

app.onStop(proc() =
  echo "Server is shutting down..."
  closeDatabase()
)
```

---

## Project Structure (Recommended)

```
myapp/
├── .config/
│   └── config.json
├── .env
├── myapp.nimble
├── src/
│   └── myapp.nim
├── public/
│   ├── css/
│   ├── js/
│   └── images/
├── templates/
└── tests/
    └── test_api.nim
```

---

## API Reference

See [docs/api-reference.md](docs/api-reference.md) for the complete API reference.

### Core Modules

| Module | Description |
|---|---|
| `nimmax` | Main entry point — re-exports all core modules |
| `nimmax/core/types` | Core types: Context, Request, Response, HandlerAsync |
| `nimmax/core/application` | Application object and route registration |
| `nimmax/core/context` | Context helpers: params, cookies, flash, response |
| `nimmax/core/request` | Request helpers: typed parameter access |
| `nimmax/core/response` | Response helpers: html, json, redirect |
| `nimmax/core/route` | Routing engine |
| `nimmax/core/middleware` | Middleware chain and composition |
| `nimmax/core/settings` | Settings and configuration |
| `nimmax/core/group` | Route grouping |
| `nimmax/core/form` | Multipart form parsing |
| `nimmax/core/exceptions` | Exception hierarchy |

### Plugin Modules

| Module | Description |
|---|---|
| `nimmax/middlewares` | All built-in middlewares |
| `nimmax/security` | Signing and password hashing |
| `nimmax/validater` | Form validation |
| `nimmax/cache` | LRU and LFU caches |
| `nimmax/websocket` | WebSocket support |
| `nimmax/openapi` | OpenAPI/Swagger docs |
| `nimmax/i18n` | Internationalization |
| `nimmax/mocking` | Testing utilities |

---

## Comparison with Prologue

| Feature | Prologue | NimMax |
|---|---|---|
| Routing | CritBitTree | Pattern-based with groups + specificity sorting |
| Middleware | Manual switch() | Onion model with compose |
| Path params | String only | Typed: `getInt`, `getFloat`, `getBool` → `Option[T]` |
| Sessions | Memory, Redis, Cookie | Memory, Signed Cookie |
| Validation | Basic validators | 15+ validators with `Option` returns |
| Caching | LRU, LFU | LRU, LFU with TTL |
| Testing | `mockApp`, `runOnce` | `mockContext`, `runOnce`, `debugResponse` |
| OpenAPI | Swagger/ReDoc serving | Spec generation + Swagger UI |
| WebSocket | Delegates to websocketx | Full RFC 6455 (frames, ping/pong, binary) |
| Config | JSON, env vars | JSON, `.env`, environment prefix |
| Error pages | HTML templates | Styled responsive pages |
| Async backend | asynchttpserver / httpx | asynchttpserver (stdlib) |
| Rate limiting | No | Sliding window with custom key extractor |
| Request ID | No | Automatic generation + propagation |
| Compression | No | Real gzip/deflate (zippy) |
| Graceful shutdown | No | Configurable timeout with draining |
| JSON body parsing | No | Built-in middleware + typed deserialization |
| Response streaming | No | Chunked transfer encoding |
| NimLeptos integration | No | First-class SSR + realtime support |

---

## License

MIT License. See [LICENSE](LICENSE) for details.
