# Testing

NimMax provides built-in testing utilities that let you test your application without starting an HTTP server.

## Mock Application

Create a test application:

```nim
import nimmax/mocking

let app = mockApp()

# Register your routes
app.get("/hello", proc(ctx: Context) {.async.} =
  ctx.html("<h1>Hello!</h1>")
)

app.post("/submit", proc(ctx: Context) {.async.} =
  let name = ctx.getPostParam("name")
  ctx.json(%*{"received": name})
)
```

## Run Once

Test a single request synchronously:

```nim
# Test GET request
let ctx = app.runOnce(HttpGet, "/hello")
assert ctx.response.code == Http200
assert ctx.response.body == "<h1>Hello!</h1>"

# Test POST request with body
let headers = newHttpHeaders({"Content-Type": "application/x-www-form-urlencoded"})
let ctx2 = app.runOnce(HttpPost, "/submit", headers = headers, body = "name=Alice")
assert ctx2.response.code == Http200
```

## Mock Context

Create a context directly for unit testing:

```nim
import nimmax/mocking

# Basic mock context
let ctx = mockContext(
  httpMethod = HttpGet,
  path = "/user/42"
)

# With query parameters
let queryParams = {"page": "1", "sort": "name"}.newTable
let ctx = mockContext(
  httpMethod = HttpGet,
  path = "/users",
  queryParams = queryParams
)

# With POST data
let postParams = {"email": "test@example.com", "name": "Test"}.newTable
let ctx = mockContext(
  httpMethod = HttpPost,
  path = "/register",
  postParams = postParams
)

# With custom headers
let headers = newHttpHeaders({
  "Authorization": "Bearer token123",
  "Accept": "application/json"
})
let ctx = mockContext(
  httpMethod = HttpGet,
  path = "/api/me",
  headers = headers
)
```

## Mock Request

Create a Request object directly:

```nim
import nimmax/mocking

let req = mockRequest(
  httpMethod = HttpGet,
  path = "/hello",
  headers = newHttpHeaders({"Accept": "text/html"})
)

assert req.httpMethod == HttpGet
assert req.url.path == "/hello"
```

## Debug Response

Print a formatted response for debugging:

```nim
let ctx = app.runOnce(HttpGet, "/hello")
debugResponse(ctx)
```

Output:

```
=== Response ===
Status: 200
Headers:
  Content-Type: text/html; charset=utf-8
Body:
<h1>Hello!</h1>
================
```

## Testing with Settings

```nim
let settings = newSettings(
  debug = true,
  appName = "TestApp",
  secretKey = "test-secret"
)
let app = mockApp(settings)
```

## Example: Full Test Suite

```nim
import nimmax
import nimmax/mocking
import nimmax/validater
import json

# Setup
let app = mockApp()

let validator = newFormValidator()
validator.addRule("email", required())
validator.addRule("email", isEmail())

app.get("/health", proc(ctx: Context) {.async.} =
  ctx.json(%*{"status": "ok"})
)

app.post("/register", proc(ctx: Context) {.async.} =
  let errors = validator.validateForm(ctx.request.postParams)
  if errors.len > 0:
    ctx.json(%*{"errors": errors}, Http422)
    return
  ctx.json(%*{"status": "registered"}, Http201)
)

# Tests
proc testHealth() =
  let ctx = app.runOnce(HttpGet, "/health")
  assert ctx.response.code == Http200
  let body = parseJson(ctx.response.body)
  assert body["status"].getStr() == "ok"
  echo "PASS: testHealth"

proc testRegisterValid() =
  let headers = newHttpHeaders({"Content-Type": "application/x-www-form-urlencoded"})
  let ctx = app.runOnce(HttpPost, "/register", headers = headers,
    body = "email=test@example.com")
  assert ctx.response.code == Http201
  echo "PASS: testRegisterValid"

proc testRegisterInvalid() =
  let headers = newHttpHeaders({"Content-Type": "application/x-www-form-urlencoded"})
  let ctx = app.runOnce(HttpPost, "/register", headers = headers,
    body = "email=invalid")
  assert ctx.response.code == Http422
  let body = parseJson(ctx.response.body)
  assert body["errors"].len > 0
  echo "PASS: testRegisterInvalid"

proc testNotFound() =
  let ctx = app.runOnce(HttpGet, "/nonexistent")
  assert ctx.response.code == Http404
  echo "PASS: testNotFound"

# Run tests
testHealth()
testRegisterValid()
testRegisterInvalid()
testNotFound()
echo "All tests passed!"
```

## Running Tests

```bash
nim c -r tests/test_app.nim
```

### With Nimble

Add a test task to your `.nimble` file:

```nim
task test, "Run the tests":
  exec "nim c -r tests/test_app.nim"
```

Run with:

```bash
nimble test
```

## Testing Tips

1. **Use `mockApp()`** instead of `newApp()` — no server needed
2. **Use `runOnce()`** for integration tests — tests the full request pipeline
3. **Use `mockContext()`** for unit tests — test individual handlers
4. **Use `debugResponse()`** during development — see exactly what's returned
5. **Test error cases** — 404, 422, 500 responses
6. **Test middleware** — add middleware to your mock app and verify behavior
