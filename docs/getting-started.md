# Getting Started

This guide walks you through setting up NimMax and building your first application.

## Prerequisites

- [Nim](https://nim-lang.org/) >= 2.0.0
- [Nimble](https://github.com/nim-lang/nimble) package manager (comes with Nim)

Verify your installation:

```bash
nim --version
nimble --version
```

## Installation

### Via Nimble

```bash
nimble install nimmax
```

### From Source

```bash
git clone https://github.com/your-org/nimmax.git
cd nimmax
nimble install
```

### As a Dependency

Add to your `.nimble` file:

```nim
requires "nimmax >= 1.0.0"
```

Or create a new project:

```bash
nimble init myapp
cd myapp
nimble add nimmax
```

## Project Setup

Create the following structure:

```
myapp/
├── myapp.nimble
├── src/
│   └── myapp.nim
└── config.nims
```

### myapp.nimble

```nim
# Package
version       = "0.1.0"
author        = "Your Name"
description   = "My NimMax application"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.0.0"
requires "nimmax >= 1.0.0"
```

### config.nims

```nim
switch("path", "$projectDir/../src")
```

## Hello World

Create `src/myapp.nim`:

```nim
import nimmax

proc hello(ctx: Context) {.async.} =
  ctx.html("<h1>Hello, NimMax!</h1><p>Welcome to your first NimMax app.</p>")

proc main() =
  let settings = newSettings(
    address = "0.0.0.0",
    port = Port(8080),
    debug = true,
    appName = "MyApp"
  )

  let app = newApp(settings = settings)
  app.get("/", hello)
  app.run()

main()
```

Build and run:

```bash
nim c -r src/myapp.nim
```

Visit `http://localhost:8080` in your browser.

## Adding Routes

```nim
import nimmax, json

proc home(ctx: Context) {.async.} =
  ctx.html("<h1>Home</h1>")

proc apiUsers(ctx: Context) {.async.} =
  ctx.json(%*{"users": @["Alice", "Bob", "Charlie"]})

proc apiUser(ctx: Context) {.async.} =
  let id = ctx.getPathParam("id")
  ctx.json(%*{"user_id": id})

proc main() =
  let app = newApp()
  app.get("/", home)
  app.get("/api/users", apiUsers)
  app.get("/api/users/{id}", apiUser)
  app.run()

main()
```

## Using Middleware

```nim
import nimmax

proc main() =
  let app = newApp()

  # Add logging middleware globally
  app.use(loggingMiddleware())

  # Add CORS middleware
  app.use(corsMiddleware(
    allowOrigins = @["*"],
    allowMethods = @["GET", "POST"]
  ))

  app.get("/", proc(ctx: Context) {.async.} =
    ctx.html("<h1>Hello!</h1>")
  )

  app.run()

main()
```

## Serving Static Files

```nim
import nimmax

proc main() =
  let app = newApp()

  # Serve files from the "public" directory
  app.use(staticFileMiddleware("public"))

  app.get("/", proc(ctx: Context) {.async.} =
    ctx.html("<h1>Home</h1><link rel='stylesheet' href='/style.css'>")
  )

  app.run()

main()
```

Create `public/style.css`:

```css
body {
  font-family: sans-serif;
  max-width: 800px;
  margin: 0 auto;
  padding: 20px;
}
```

## Configuration from File

Create `.config/config.json`:

```json
{
  "address": "0.0.0.0",
  "port": 3000,
  "debug": true,
  "nimmax": {
    "secretKey": "change-me-in-production",
    "appName": "MyApp"
  }
}
```

Load in code:

```nim
import nimmax

proc main() =
  let settings = loadSettings(".config/config.json")
  let app = newApp(settings = settings)

  app.get("/", proc(ctx: Context) {.async.} =
    ctx.html("<h1>Hello from " & ctx.getSettings().appName & "!</h1>")
  )

  app.run()

main()
```

## Next Steps

- [Routing](routing.md) — Advanced routing patterns
- [Middleware](middleware.md) — Building and using middleware
- [Request & Response](request-response.md) — Working with HTTP
- [Sessions](sessions.md) — Session management
- [Validation](validation.md) — Form validation
- [Security](security.md) — CSRF, CORS, auth, signing
- [Configuration](configuration.md) — App configuration
- [Testing](testing.md) — Testing your application
