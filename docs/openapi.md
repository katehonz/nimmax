# OpenAPI / Swagger

NimMax can generate OpenAPI specifications and serve interactive API documentation using Swagger UI.

## Basic Usage

```nim
import nimmax
import nimmax/openapi

# Create an OpenAPI spec
let spec = newOpenApiSpec(
  title = "My API",
  description = "A sample REST API built with NimMax",
  version = "1.0.0"
)

# Document your endpoints
spec.addPath("/users", "GET", "List all users", tags = @["users"])
spec.addPath("/users/{id}", "GET", "Get user by ID", tags = @["users"])
spec.addPath("/users", "POST", "Create a new user", tags = @["users"])
spec.addPath("/posts", "GET", "List all posts", tags = @["posts"])
spec.addPath("/posts/{id}", "GET", "Get post by ID", tags = @["posts"])

# Serve the docs
let app = newApp()
app.serveDocs(spec)  # Adds /docs (Swagger UI) and /openapi.json

# Your routes
app.get("/users", listUsersHandler)
app.get("/users/{id}", getUserHandler)

app.run()
```

### Accessing Documentation

- **Swagger UI**: `http://localhost:8080/docs`
- **OpenAPI JSON**: `http://localhost:8080/openapi.json`

## Configuration

```nim
app.serveDocs(
  spec,
  path = "/docs",              # Swagger UI path
  openApiPath = "/openapi.json", # OpenAPI spec path
  onlyDebug = true              # only serve in debug mode (default: true)
)
```

Setting `onlyDebug = true` (default) means documentation endpoints are only available when `settings.debug = true`. This prevents exposing API docs in production.

## Generated JSON

The `toJson` method generates a valid OpenAPI 3.0.0 specification:

```nim
let jsonSpec = spec.toJson()
echo jsonSpec.pretty()
```

Output:

```json
{
  "openapi": "3.0.0",
  "info": {
    "title": "My API",
    "description": "A sample REST API built with NimMax",
    "version": "1.0.0"
  },
  "paths": {
    "/users": {
      "get": {
        "summary": "List all users",
        "tags": ["users"],
        "responses": {
          "200": {"description": "Successful response"}
        }
      }
    }
  }
}
```

## Example: Full API Documentation

```nim
import nimmax
import nimmax/openapi

proc main() =
  let spec = newOpenApiSpec(
    title = "Blog API",
    description = "A blog platform API",
    version = "1.0.0"
  )

  # Auth endpoints
  spec.addPath("/auth/login", "POST", "Login with credentials", tags = @["auth"])
  spec.addPath("/auth/register", "POST", "Register a new account", tags = @["auth"])
  spec.addPath("/auth/logout", "POST", "Logout current session", tags = @["auth"])

  # User endpoints
  spec.addPath("/users", "GET", "List all users", tags = @["users"])
  spec.addPath("/users/{id}", "GET", "Get user profile", tags = @["users"])
  spec.addPath("/users/{id}", "PUT", "Update user profile", tags = @["users"])

  # Post endpoints
  spec.addPath("/posts", "GET", "List all posts", tags = @["posts"])
  spec.addPath("/posts", "POST", "Create a new post", tags = @["posts"])
  spec.addPath("/posts/{id}", "GET", "Get post by ID", tags = @["posts"])
  spec.addPath("/posts/{id}", "PUT", "Update a post", tags = @["posts"])
  spec.addPath("/posts/{id}", "DELETE", "Delete a post", tags = @["posts"])

  # Comment endpoints
  spec.addPath("/posts/{id}/comments", "GET", "List comments for a post", tags = @["comments"])
  spec.addPath("/posts/{id}/comments", "POST", "Add a comment", tags = @["comments"])

  let settings = newSettings(debug = true)
  let app = newApp(settings = settings)
  app.serveDocs(spec)

  # Register your handlers...
  app.run()

main()
```
