import nimmax
import nimmax/jwt        # <-- optional extension, NOT imported by default
import std/[json, asyncdispatch]

# ---------------------------------------------------------------------------
# Example: JWT authentication with nimmax/jwt + jwt-nim-baraba
#
# Prerequisites:
#   nimble install https://github.com/katehonz/jwt-nim-baraba
#
# This example uses the built-in `barabaJwtVerifier` helper which wraps
# jwt-nim-baraba (yglukhov/jwt) in a NimMax-compatible `JwtVerifier`.
# ---------------------------------------------------------------------------

proc publicHandler(ctx: Context) {.async.} =
  ctx.json(%*{"message": "This endpoint is public"})

proc protectedHandler(ctx: Context) {.async.} =
  # Claims are automatically attached to ctx["jwt_claims"] by the middleware
  let userId   = ctx["jwt_claims"]{"sub"}.getStr("anonymous")
  let userName = ctx["jwt_claims"]{"name"}.getStr("Unknown")
  let role     = ctx["jwt_claims"]{"role"}.getStr("guest")

  ctx.json(%*{
    "message": "Welcome to the protected area",
    "user_id": userId,
    "name": userName,
    "role": role
  })

proc adminHandler(ctx: Context) {.async.} =
  let role = ctx["jwt_claims"]{"role"}.getStr("guest")
  if role != "admin":
    ctx.response.code = Http403
    ctx.response.body = "Forbidden: admins only"
    return

  ctx.json(%*{"message": "Admin panel", "secrets": @["foo", "bar"]})

when isMainModule:
  let settings = newSettings(
    address = "0.0.0.0",
    port = Port(8080),
    debug = true,
    appName = "NimMax JWT Example"
  )

  var app = newApp(settings = settings)

  # Public routes (no JWT required)
  app.get("/", publicHandler)
  app.get("/public", publicHandler)

  # ---------------------------------------------------------------------------
  # Protected group: all routes under /api require a valid JWT
  # ---------------------------------------------------------------------------
  let jwtSecret = "my-super-secret-key"   # load from env in production!
  let jwtMw = jwtMiddleware(barabaJwtVerifier(jwtSecret, HS256))

  let api = app.newGroup("/api", middlewares = @[jwtMw])
  api.get("/profile", protectedHandler)
  api.get("/admin", adminHandler)

  echo "Server running on http://localhost:8080"
  echo ""
  echo "1. Generate a token (use your own Nim script with jwt-nim-baraba)"
  echo "2. Test public:   curl http://localhost:8080/public"
  echo "3. Test protected: curl -H 'Authorization: Bearer <TOKEN>' http://localhost:8080/api/profile"

  app.run()
