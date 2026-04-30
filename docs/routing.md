# Routing

NimMax uses a pattern-based routing engine that matches incoming requests against registered route patterns.

## Basic Routes

Register routes for specific HTTP methods:

```nim
app.get("/hello", handler)
app.post("/submit", handler)
app.put("/update", handler)
app.delete("/remove", handler)
app.patch("/modify", handler)
app.head("/info", handler)
app.options("/check", handler)
app.all("/catch-everything", handler)  # all methods
```

## Route Patterns

### Literal Routes

Match exact paths:

```nim
app.get("/", homeHandler)
app.get("/about", aboutHandler)
app.get("/api/users", usersHandler)
```

### Named Parameters

Capture segments of the URL path:

```nim
# Matches /user/1, /user/42, /user/abc
app.get("/user/{id}", proc(ctx: Context) {.async.} =
  let id = ctx.getPathParam("id")
  ctx.text("User: " & id)
)
```

Multiple parameters:

```nim
# Matches /user/42/posts/7
app.get("/user/{userId}/posts/{postId}", proc(ctx: Context) {.async.} =
  let userId = ctx.getPathParam("userId")
  let postId = ctx.getPathParam("postId")
  ctx.json(%*{"user": userId, "post": postId})
)
```

### Wildcard Routes

Match any remaining path:

```nim
# Matches /files/anything/here
app.get("/files/*", proc(ctx: Context) {.async.} =
  let path = ctx.getPathParam("*")
  ctx.text("File path: " & path)
)
```

### Typed Parameter Access

Access parameters as specific types, returning `Option[T]`:

```nim
app.get("/product/{id}", proc(ctx: Context) {.async.} =
  let idOpt = ctx.getInt("id")  # Option[int]
  if idOpt.isNone:
    ctx.abortRequest(Http400, "Invalid product ID")
    return

  let id = idOpt.get
  ctx.json(%*{"product_id": id})
)
```

Available typed accessors:

| Method | Return Type | Source |
|---|---|---|
| `ctx.getInt(key)` | `Option[int]` | path params |
| `ctx.getFloat(key)` | `Option[float]` | path params |
| `ctx.getBool(key)` | `Option[bool]` | query params |
| `ctx.getInt(key, "query")` | `Option[int]` | query params |
| `ctx.getInt(key, "post")` | `Option[int]` | POST params |

## Route Groups

Groups allow you to share a common path prefix and middleware across multiple routes.

### Basic Groups

```nim
let api = app.newGroup("/api")

api.get("/users", listUsers)        # GET /api/users
api.post("/users", createUser)      # POST /api/users
api.get("/users/{id}", getUser)     # GET /api/users/{id}
api.put("/users/{id}", updateUser)  # PUT /api/users/{id}
api.delete("/users/{id}", deleteUser) # DELETE /api/users/{id}
```

### Nested Groups

Groups can be nested, and prefixes are accumulated:

```nim
let api = app.newGroup("/api")
let v1 = api.newGroup("/v1")
let users = v1.newGroup("/users")

users.get("/", listUsers)           # GET /api/v1/users
users.get("/{id}", getUser)         # GET /api/v1/users/{id}
```

### Groups with Middleware

Apply middleware to all routes in a group:

```nim
let adminMiddleware = basicAuthMiddleware("Admin", verifyAdmin)

let admin = app.newGroup("/admin", middlewares = @[adminMiddleware])
admin.get("/dashboard", dashboardHandler)   # requires auth
admin.get("/settings", settingsHandler)     # requires auth
```

Middleware inheritance flows through nested groups:

```nim
let api = app.newGroup("/api", middlewares = @[loggingMiddleware()])
let auth = api.newGroup("/auth", middlewares = @[authMiddleware()])

auth.get("/profile", profileHandler)  # has both logging + auth
```

## Named Routes

Assign names to routes for URL generation:

```nim
app.get("/user/{id}", userHandler, name = "user_detail")
app.get("/post/{slug}", postHandler, name = "post")
app.get("/", homeHandler, name = "home")
```

### URL Building

Generate URLs from route names:

```nim
proc userHandler(ctx: Context) {.async.} =
  let userId = "42"
  let profileUrl = ctx.urlFor("user_detail", @[("id", userId)])
  # profileUrl = "/user/42"

  ctx.json(%*{
    "user_id": userId,
    "profile_url": profileUrl
  })
```

This is especially useful in templates where you want to avoid hardcoded URLs.

## Route Matching Order

Routes are matched in the order they are registered within each HTTP method. The first matching route wins.

1. Routes for the specific HTTP method are checked first
2. If no match is found, the 404 error handler is invoked
3. If the path matches a route for a *different* method, a 404 is returned (not 405)

## Error Handling for Routes

```nim
app.registerErrorHandler(Http404, proc(ctx: Context) {.async.} =
  ctx.html("<h1>Page Not Found</h1>", Http404)
)

app.registerErrorHandler(Http500, proc(ctx: Context) {.async.} =
  ctx.html("<h1>Internal Server Error</h1>", Http500)
)
```
