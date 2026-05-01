# Request & Response

## Request

The `Request` object contains all information about the incoming HTTP request.

### Properties

| Property | Type | Description |
|---|---|---|
| `httpMethod` | `HttpMethod` | GET, POST, PUT, DELETE, etc. |
| `url` | `Uri` | Full URL |
| `headers` | `HttpHeaders` | Request headers |
| `body` | `string` | Raw request body |
| `cookies` | `TableRef[string, string]` | Parsed cookies |
| `queryParams` | `TableRef[string, string]` | Query string parameters |
| `postParams` | `TableRef[string, string]` | POST form parameters |
| `pathParams` | `TableRef[string, string]` | Route path parameters |
| `formParams` | `FormPart` | Multipart form data |

### Helper Procedures

```nim
# Path
ctx.request.url.path          # "/user/42"
ctx.request.url.query         # "page=1&sort=name"
ctx.request.url.scheme        # "http" or "https"

# Headers
ctx.request.headers.getHeader("Authorization")
ctx.request.headers.getHeader("Content-Type", "application/json")
ctx.request.userAgent()
ctx.request.hostName()
ctx.request.contentType()

# Method
ctx.request.httpMethod        # HttpGet, HttpPost, etc.
ctx.request.secure            # true if HTTPS

# Cookies
ctx.request.getCookie("session_id")
ctx.request.hasCookie("session_id")
```

### Typed Parameter Access (via Context)

The recommended way to access parameters is through Context helper methods:

```nim
proc handler(ctx: Context) {.async.} =
  # Path parameters (from route patterns like /user/{id})
  let id = ctx.getPathParam("id")         # string
  let idInt = ctx.getInt("id")            # Option[int]
  let price = ctx.getFloat("price")       # Option[float]

  # Query parameters (from ?key=value)
  let page = ctx.getQueryParam("page")    # string
  let pageInt = ctx.getQueryParamInt("page")  # Option[int]
  let active = ctx.getQueryParamBool("active") # Option[bool]

  # POST parameters (from form submission)
  let name = ctx.getPostParam("name")     # string

  # Generic typed access with source selection
  let id2 = ctx.getInt("id", "path")      # from path params
  let pg = ctx.getInt("page", "query")    # from query params
  let age = ctx.getInt("age", "post")     # from POST params

  # Bracket access (tries path → query → post)
  let value = ctx.request["key"]
```

### Reading JSON Body

#### Built-in Context Helper

```nim
proc handler(ctx: Context) {.async.} =
  # Parse JSON body into JsonNode
  let data = ctx.getJsonBody()
  let name = data["name"].getStr()

  # Or parse directly into a typed object
  type User = object
    name: string
    age: int
  let user = ctx.getJsonBody(User)
  ctx.json(%*{"name": user.name, "age": user.age})
```

#### With Middleware

For automatic parsing on every request, use the built-in middleware:

```nim
app.use(jsonBodyMiddleware())

app.post("/api/users", proc(ctx: Context) {.async.} =
  let data = ctx.getJsonBody()
  let name = data["name"].getStr()
  ctx.json(%*{"created": name})
)
```

The middleware checks `Content-Type: application/json` and only parses matching requests. Parsing errors return HTTP 400.

#### Manual Parsing

```nim
import json

proc handler(ctx: Context) {.async.} =
  let data = parseJson(ctx.request.body)
  let name = data["name"].getStr()
  let age = data["age"].getInt()
```

### Form Data (Multipart)

For `multipart/form-data` submissions (file uploads):

```nim
proc uploadHandler(ctx: Context) {.async.} =
  let form = ctx.request.formParams

  # Get form field value
  let title = form.getFormValue("title")

  # Get uploaded file
  let file = form.getFormFile("avatar")
  if file.filename.len > 0:
    writeFile("uploads/" & file.filename, file.body)
    ctx.json(%*{"uploaded": file.filename})
  else:
    ctx.abortRequest(Http400, "No file uploaded")
```

### Form Data (URL-Encoded)

For `application/x-www-form-urlencoded` submissions:

```nim
proc formHandler(ctx: Context) {.async.} =
  let name = ctx.getPostParam("name")
  let email = ctx.getPostParam("email")
  ctx.json(%*{"name": name, "email": email})
```

---

## Response

The `Response` object contains the HTTP response to send back to the client.

### Convenience Methods

```nim
# HTML response (Content-Type: text/html)
ctx.html("<h1>Hello</h1>")
ctx.html("<h1>Not Found</h1>", Http404)

# JSON response (Content-Type: application/json)
ctx.json(%*{"status": "ok"})
ctx.json(%*{"error": "bad request"}, Http400)

# Plain text response (Content-Type: text/plain)
ctx.text("Hello, World!")

# Redirect
ctx.redirect("/new-location")           # 301 Permanent
ctx.temporaryRedirect("/temp")          # 302 Temporary
ctx.seeOther("/other")                  # 303 See Other

# Abort (raises AbortError)
ctx.abortRequest(Http403, "Forbidden")
ctx.abortRequest(Http401, "Unauthorized")
```

### Static File Response

Serve a file from disk with automatic Content-Type detection:

```nim
ctx.staticFileResponse("public/image.png")

# As a download with custom filename
ctx.staticFileResponse("data/report.pdf", downloadName = "report-2024.pdf")
```

Features:
- Automatic MIME type detection from file extension
- ETag header generation
- If-None-Match support (returns 304 Not Modified)

### Chunked Response Streaming

For streaming responses — SSR, large files, real-time data — use chunked transfer encoding:

```nim
app.get("/stream", proc(ctx: Context) {.async.} =
  ctx.startChunked()

  for i in 1 .. 5:
    await ctx.writeChunk("Chunk " & $i & "\n")
    await sleepAsync(500)

  await ctx.endChunked()
)
```

Streaming integrates with NimLeptos SSR for progressive page rendering:

```nim
import nimleptos/server

app.get("/", proc(ctx: Context) {.async.} =
  ctx.startChunked()

  # Render header immediately
  await ctx.writeChunk("<!DOCTYPE html><html><head><title>App</title></head><body>")

  # Stream SSR chunks
  for i in 1 .. 10:
    await ctx.writeChunk("<div>Item " & $i & "</div>")
    await sleepAsync(100)

  await ctx.writeChunk("</body></html>")
  await ctx.endChunked()
)
```

**Note**: Streaming uses `writeChunk` which sends data directly to the client socket. Headers must already be set in `ctx.response.headers` before calling `startChunked()`.

### Setting Response Properties

```nim
# Status code
ctx.response.code = Http200

# Headers
ctx.response.headers["X-Custom-Header"] = "value"
ctx.response.headers["Cache-Control"] = "no-cache"

# Body
ctx.response.body = "<html>...</html>"
```

### Response Object Helpers

Create Response objects directly:

```nim
let resp = htmlResponse("<h1>Hello</h1>", Http200)
let resp = plainTextResponse("OK")
let resp = jsonResponse(%*{"items": @[1, 2, 3]})
let resp = redirect("/login")
let resp = abort(Http403)
let resp = errorPage(Http404, "Not Found", "The page you requested does not exist.")
```

### Cookies

```nim
# Set a cookie
ctx.setCookie("theme", "dark",
  path = "/",
  maxAge = 86400,      # 24 hours in seconds
  httpOnly = true,
  secure = true,       # only send over HTTPS
  sameSite = "Strict"  # Lax, Strict, or None
)

# Delete a cookie
ctx.deleteCookie("theme")

# Read a cookie
let theme = ctx.getCookie("theme")
let hasTheme = ctx.hasCookie("theme")  # on Request
```

### Custom Error Pages

Register custom error handlers:

```nim
app.registerErrorHandler(Http404, proc(ctx: Context) {.async.} =
  let body = "<h1>404</h1><p>Page not found: " & escapeHtml(ctx.request.url.path) & "</p>"
  ctx.html(body, Http404)
)

app.registerErrorHandler({Http500, Http502, Http503}, proc(ctx: Context) {.async.} =
  ctx.html("<h1>Server Error</h1><p>Please try again later.</p>", Http500)
)
```

Built-in error pages are styled HTML with responsive design. The default handlers are registered for `Http404` and `Http500`.
