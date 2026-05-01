import std/[unittest, asyncdispatch, httpcore, json]
import nimmax/core/types
import nimmax/core/route
import nimmax/core/context
import nimmax/core/application
import nimmax/core/exceptions
import nimmax/core/group
import nimmax/testing/mocking

suite "Route Parsing":
  test "parsePattern - root path":
    let parts = parsePattern("/")
    check parts.len == 0

  test "parsePattern - simple literal":
    let parts = parsePattern("/hello")
    check parts.len == 1
    check parts[0].kind == rpkLiteral
    check parts[0].literal == "hello"

  test "parsePattern - multiple segments":
    let parts = parsePattern("/api/users")
    check parts.len == 2
    check parts[0].literal == "api"
    check parts[1].literal == "users"

  test "parsePattern - named parameter":
    let parts = parsePattern("/user/{id}")
    check parts.len == 2
    check parts[0].kind == rpkLiteral
    check parts[0].literal == "user"
    check parts[1].kind == rpkParam
    check parts[1].paramName == "id"

  test "parsePattern - wildcard":
    let parts = parsePattern("/files/*")
    check parts.len == 2
    check parts[0].kind == rpkLiteral
    check parts[1].kind == rpkWildcard

  test "parsePattern - multiple params":
    let parts = parsePattern("/user/{id}/post/{postId}")
    check parts.len == 4
    check parts[1].paramName == "id"
    check parts[3].paramName == "postId"

suite "Route Specificity":
  test "literal has highest specificity":
    let parts = parsePattern("/users/list")
    check routeSpecificity(parts) == 200

  test "param has medium specificity":
    let parts = parsePattern("/users/{id}")
    check routeSpecificity(parts) == 150

  test "wildcard has lowest specificity":
    let parts = parsePattern("/files/*")
    check routeSpecificity(parts) == 101

suite "Path Matching":
  test "match exact path":
    let parts = parsePattern("/hello")
    let (matched, params) = matchPath(parts, "/hello")
    check matched == true
    check params.len == 0

  test "match path with parameter":
    let parts = parsePattern("/user/{id}")
    let (matched, params) = matchPath(parts, "/user/42")
    check matched == true
    check params.len == 1
    check params[0].name == "id"
    check params[0].value == "42"

  test "match path with wildcard":
    let parts = parsePattern("/files/*")
    let (matched, params) = matchPath(parts, "/files/docs/readme.txt")
    check matched == true
    check params.len == 1
    check params[0].name == "*"
    check params[0].value == "docs/readme.txt"

  test "no match on different path":
    let parts = parsePattern("/hello")
    let (matched, _) = matchPath(parts, "/world")
    check matched == false

  test "no match on different segment count":
    let parts = parsePattern("/hello")
    let (matched, _) = matchPath(parts, "/hello/world")
    check matched == false

  test "match root path":
    let parts = parsePattern("/")
    let (matched, _) = matchPath(parts, "/")
    check matched == true

suite "Router":
  test "add and find route":
    let router = newRouter()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} = discard
    router.addRoute(HttpGet, "/hello", handler)
    let found = router.findRoute(HttpGet, "/hello")
    check found.isSome

  test "route not found":
    let router = newRouter()
    let found = router.findRoute(HttpGet, "/nonexistent")
    check found.isNone

  test "method mismatch":
    let router = newRouter()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} = discard
    router.addRoute(HttpGet, "/hello", handler)
    let found = router.findRoute(HttpPost, "/hello")
    check found.isNone

  test "matchRoute returns params":
    let router = newRouter()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} = discard
    router.addRoute(HttpGet, "/user/{id}", handler)
    let result = router.matchRoute(HttpGet, "/user/42")
    check result.matched == true
    check result.pathParams.len == 1
    check result.pathParams[0].name == "id"
    check result.pathParams[0].value == "42"

  test "named route and url building":
    let router = newRouter()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} = discard
    router.addRoute(HttpGet, "/user/{id}", handler, name = "user_detail")
    let url = router.buildUrl("user_detail", @[("id", "42")])
    check url == "/user/42"

  test "duplicate route name raises":
    let router = newRouter()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} = discard
    router.addRoute(HttpGet, "/a", handler, name = "test")
    expect DuplicatedRouteError:
      router.addRoute(HttpGet, "/b", handler, name = "test")

  test "specificity sorting - literal beats param":
    let router = newRouter()
    let literalHandler = proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.text("literal")
    let paramHandler = proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.text("param")
    router.addRoute(HttpGet, "/users/list", literalHandler)
    router.addRoute(HttpGet, "/users/{id}", paramHandler)

    let result = router.matchRoute(HttpGet, "/users/list")
    check result.matched == true

suite "Application Routes":
  test "app.get registers GET route":
    let app = mockApp()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.text("hello")
    app.get("/hello", handler)
    let ctx = app.runOnce(HttpGet, "/hello")
    check ctx.response.code == Http200
    check ctx.response.body == "hello"

  test "app.post registers POST route":
    let app = mockApp()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.text("posted")
    app.post("/submit", handler)
    let ctx = app.runOnce(HttpPost, "/submit")
    check ctx.response.code == Http200
    check ctx.response.body == "posted"

  test "404 for unmatched route":
    let app = mockApp()
    let ctx = app.runOnce(HttpGet, "/nonexistent")
    check ctx.response.code == Http404

  test "path parameters accessible":
    let app = mockApp()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} =
      let id = ctx.getPathParam("id")
      ctx.text("id=" & id)
    app.get("/user/{id}", handler)
    let ctx = app.runOnce(HttpGet, "/user/42")
    check ctx.response.body == "id=42"

  test "query parameters accessible":
    let app = mockApp()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} =
      let page = ctx.getQueryParam("page")
      ctx.text("page=" & page)
    app.get("/search", handler)
    let ctx = app.runOnce(HttpGet, "/search?page=5")
    check ctx.response.body == "page=5"

  test "typed path param accessors":
    let app = mockApp()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} =
      let idInt = ctx.getInt("id")
      check idInt.isSome
      check idInt.get == 42
      ctx.text("ok")
    app.get("/item/{id}", handler)
    let ctx = app.runOnce(HttpGet, "/item/42")
    check ctx.response.body == "ok"

  test "typed path param - invalid int":
    let app = mockApp()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} =
      let idInt = ctx.getInt("id")
      check idInt.isNone
      ctx.text("ok")
    app.get("/item/{id}", handler)
    let ctx = app.runOnce(HttpGet, "/item/abc")
    check ctx.response.body == "ok"

suite "Groups":
  test "group adds prefix":
    let app = mockApp()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.json(%*{"status": "ok"})
    let api = app.newGroup("/api/v1")
    api.get("/users", handler)
    let ctx = app.runOnce(HttpGet, "/api/v1/users")
    check ctx.response.code == Http200

  test "nested groups":
    let app = mockApp()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.text("admin")
    let api = app.newGroup("/api")
    let admin = api.app.newGroup("/admin", parent = api)
    admin.get("/dashboard", handler)
    let ctx = app.runOnce(HttpGet, "/api/admin/dashboard")
    check ctx.response.code == Http200
    check ctx.response.body == "admin"

suite "URL Building":
  test "buildUrl with params":
    let app = mockApp()
    let handler = proc(ctx: Context): Future[void] {.async, gcsafe.} = discard
    app.get("/user/{id}/post/{postId}", handler, name = "user_post")
    let ctx = mockContextWithApp(app)
    let url = ctx.urlFor("user_post", @[("id", "1"), ("postId", "99")])
    check url == "/user/1/post/99"
