import nimmax
import nimmax/middlewares

proc helloHandler(ctx: Context) {.async.} =
  ctx.html("<h1>Hello, NimMax!</h1><p>Welcome to the NimMax web framework.</p>")

proc jsonHandler(ctx: Context) {.async.} =
  ctx.json(%*{"message": "Hello, NimMax!", "version": nimMaxVersion})

proc userHandler(ctx: Context) {.async.} =
  let userId = ctx.getPathParam("id")
  ctx.json(%*{"user_id": userId})

proc submitHandler(ctx: Context) {.async.} =
  let name = ctx.getPostParam("name")
  let email = ctx.getPostParam("email")
  ctx.json(%*{"name": name, "email": email, "status": "received"})

proc aboutHandler(ctx: Context) {.async.} =
  ctx.html("<h1>About NimMax</h1><p>A modern web framework for Nim.</p>")

when isMainModule:
  let settings = newSettings(
    address = "0.0.0.0",
    port = Port(8080),
    debug = true,
    appName = "NimMax Example"
  )

  var app = newApp(settings = settings)

  app.use(loggingMiddleware())

  app.get("/", helloHandler, name = "home")
  app.get("/api/json", jsonHandler, name = "api_json")
  app.get("/user/{id}", userHandler, name = "user")
  app.post("/submit", submitHandler, name = "submit")
  app.get("/about", aboutHandler, name = "about")

  let api = app.newGroup("/api/v1")
  api.get("/users", proc(ctx: Context) {.async.} =
    ctx.json(%*{"users": @["Alice", "Bob", "Charlie"]})
  , name = "api_users")

  api.get("/users/{id}", proc(ctx: Context) {.async.} =
    let id = ctx.getPathParam("id")
    ctx.json(%*{"user_id": id, "name": "User " & id})
  , name = "api_user_detail")

  app.run()
