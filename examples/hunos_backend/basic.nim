## NimMax with Hunos Backend - Basic Example
##
## Compile with:
##   nim c --threads:on --mm:arc -r examples/hunos_backend/basic.nim
##
## This example demonstrates using NimMax with the Hunos multi-threaded
## HTTP server backend instead of the default asynchttpserver.

import nimmax/hunos

proc index(ctx: Context) {.async.} =
  ctx.html("""
  <!DOCTYPE html>
  <html>
  <head><title>NimMax on Hunos</title></head>
  <body>
    <h1>Hello from NimMax + Hunos!</h1>
    <p>This server uses the Hunos multi-threaded backend.</p>
    <ul>
      <li><a href="/api">JSON API</a></li>
      <li><a href="/user/42">Path params</a></li>
    </ul>
  </body>
  </html>
  """)

proc api(ctx: Context) {.async.} =
  ctx.json(%*{
    "framework": "NimMax",
    "backend": "Hunos",
    "features": [
      "Multi-threaded workers",
      "HTTP/1.1 & HTTP/2 (h2c)",
      "Trie-based routing",
      "Built-in compression"
    ]
  })

proc user(ctx: Context) {.async.} =
  let id = ctx.getInt("id")
  if id.isSome:
    ctx.json(%*{"userId": id.get})
  else:
    ctx.json(%*{"error": "Invalid ID"}, Http400)

proc main() =
  let app = newApp()

  app.get("/", index)
  app.get("/api", api)
  app.get("/user/{id}", user)

  echo "Starting server on http://0.0.0.0:8080"
  echo "Try these endpoints:"
  echo "  GET /"
  echo "  GET /api"
  echo "  GET /user/42"
  app.runHunos(address = "0.0.0.0", port = Port(8080))

main()
