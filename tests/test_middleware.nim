import std/[unittest, asyncdispatch, httpcore, json, options]
import nimmax/core/types
import nimmax/core/context
import nimmax/core/application
import nimmax/middlewares/utils
import nimmax/middlewares/cors
import nimmax/middlewares/csrf
import nimmax/middlewares/requestid
import nimmax/middlewares/compression
import nimmax/security
import nimmax/validater
import nimmax/cache
import nimmax/testing/mocking

suite "Middleware Chain":
  test "global middleware runs with handler":
    let app = mockApp()
    app.use(stripPathMiddleware())
    app.get("/test", proc(ctx: Context) {.async.} =
      ctx.text("ok")
    )
    let ctx = app.runOnce(HttpGet, "/test")
    check ctx.response.code == Http200
    check ctx.response.body == "ok"

  test "logging middleware doesn't break handler":
    let app = mockApp()
    app.use(loggingMiddleware())
    app.get("/logtest", proc(ctx: Context) {.async.} =
      ctx.text("logged")
    )
    let ctx = app.runOnce(HttpGet, "/logtest")
    check ctx.response.code == Http200
    check ctx.response.body == "logged"

suite "Strip Path Middleware":
  test "removes trailing slash":
    let app = mockApp()
    app.use(stripPathMiddleware())
    app.get("/hello", proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.text("ok")
    )
    let ctx = app.runOnce(HttpGet, "/hello/")
    check ctx.response.code == Http200
    check ctx.response.body == "ok"

suite "CORS Middleware":
  test "adds CORS headers for allowed origin":
    let app = mockApp()
    app.use(corsMiddleware(allowOrigins = @["https://example.com"]))
    app.get("/api", proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.json(%*{"status": "ok"})
    )
    let headers = newHttpHeaders([("Origin", "https://example.com")])
    let ctx = app.runOnce(HttpGet, "/api", headers)
    check ctx.response.headers.hasKey("Access-Control-Allow-Origin")
    check ctx.response.headers["Access-Control-Allow-Origin"] == "https://example.com"

  test "wildcard CORS":
    let app = mockApp()
    app.use(corsMiddleware())
    app.get("/api", proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.json(%*{"status": "ok"})
    )
    let headers = newHttpHeaders([("Origin", "https://any.com")])
    let ctx = app.runOnce(HttpGet, "/api", headers)
    check ctx.response.headers["Access-Control-Allow-Origin"] == "*"

  test "preflight returns 204":
    let app = mockApp()
    app.use(corsMiddleware(allowOrigins = @["https://example.com"]))
    app.options("/api", proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.text("ok")
    )
    let headers = newHttpHeaders([
      ("Origin", "https://example.com"),
      ("Access-Control-Request-Method", "POST")
    ])
    let ctx = app.runOnce(HttpOptions, "/api", headers)
    check ctx.response.code == Http204

suite "CSRF Middleware":
  test "sets CSRF cookie on GET":
    let app = mockApp()
    app.use(csrfMiddleware())
    app.get("/form", proc(ctx: Context) {.async.} =
      ctx.html("<form></form>")
    )
    let ctx = app.runOnce(HttpGet, "/form")
    check ctx.response.code == Http200
    var hasCsrfCookie = false
    for k, v in ctx.response.headers:
      if k == "set-cookie" and "nimmax_csrf" in v:
        hasCsrfCookie = true
    check hasCsrfCookie

suite "Request ID Middleware":
  test "generates request ID":
    let app = mockApp()
    app.use(requestIdMiddleware())
    app.get("/test", proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.text("ok")
    )
    let ctx = app.runOnce(HttpGet, "/test")
    check ctx.response.headers.hasKey("X-Request-ID")
    check ctx.response.headers["X-Request-ID"].len > 0

  test "propagates existing request ID":
    let app = mockApp()
    app.use(requestIdMiddleware())
    app.get("/test", proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.text("ok")
    )
    let headers = newHttpHeaders([("X-Request-ID", "my-custom-id")])
    let ctx = app.runOnce(HttpGet, "/test", headers)
    check ctx.response.headers["X-Request-ID"] == "my-custom-id"

suite "Compression Middleware":
  test "sets Vary header when encoding supported":
    let app = mockApp()
    app.use(compressionMiddleware(minSize = 0))
    app.get("/test", proc(ctx: Context): Future[void] {.async, gcsafe.} =
      ctx.text("hello world")
    )
    let headers = newHttpHeaders([("Accept-Encoding", "gzip")])
    let ctx = app.runOnce(HttpGet, "/test", headers)
    check ctx.response.headers.hasKey("Vary")
    check ctx.response.headers["Vary"] == "Accept-Encoding"

suite "Security - Signing":
  test "sign and validate":
    let signer = newSigner(SecretKey("test-key"))
    let signed = signer.sign("hello")
    check signer.validate(signed) == true

  test "unsign returns original value":
    let signer = newSigner(SecretKey("test-key"))
    let signed = signer.sign("hello")
    let original = signer.unsign(signed)
    check original == "hello"

  test "validate fails with wrong key":
    let signer1 = newSigner(SecretKey("key1"))
    let signer2 = newSigner(SecretKey("key2"))
    let signed = signer1.sign("hello")
    check signer2.validate(signed) == false

  test "timed signing and unsigning":
    let signer = newTimedSigner(SecretKey("test-key"), maxAge = 3600)
    let signed = signer.sign("temp-data")
    let original = signer.unsign(signed)
    check original == "temp-data"

  test "timed signing validates":
    let signer = newTimedSigner(SecretKey("test-key"), maxAge = 3600)
    let signed = signer.sign("temp-data")
    check signer.validate(signed) == true

suite "Security - Password Hashing":
  test "hash and verify password":
    let hashed = hashPassword("my-password")
    check verifyPassword("my-password", hashed) == true

  test "wrong password fails verification":
    let hashed = hashPassword("my-password")
    check verifyPassword("wrong-password", hashed) == false

suite "Validation":
  test "required validator":
    let v = newFormValidator()
    v.addRule("name", required())
    let data = newTable[string, string]()
    data["name"] = ""
    let errors = v.validateForm(data)
    check errors.len > 0

  test "required validator passes with value":
    let v = newFormValidator()
    v.addRule("name", required())
    let data = newTable[string, string]()
    data["name"] = "Alice"
    let errors = v.validateForm(data)
    check errors.len == 0

  test "isInt validator":
    let v = newFormValidator()
    v.addRule("age", isInt())
    let data = newTable[string, string]()
    data["age"] = "abc"
    let errors = v.validateForm(data)
    check errors.len > 0

  test "isInt validator passes":
    let v = newFormValidator()
    v.addRule("age", isInt())
    let data = newTable[string, string]()
    data["age"] = "25"
    let errors = v.validateForm(data)
    check errors.len == 0

  test "minValue validator":
    let v = newFormValidator()
    v.addRule("age", minValue(0))
    let data = newTable[string, string]()
    data["age"] = "-1"
    let errors = v.validateForm(data)
    check errors.len > 0

  test "maxValue validator":
    let v = newFormValidator()
    v.addRule("age", maxValue(150))
    let data = newTable[string, string]()
    data["age"] = "200"
    let errors = v.validateForm(data)
    check errors.len > 0

  test "isEmail validator":
    let v = newFormValidator()
    v.addRule("email", isEmail())
    let data = newTable[string, string]()
    data["email"] = "not-an-email"
    let errors = v.validateForm(data)
    check errors.len > 0

  test "isEmail validator passes":
    let v = newFormValidator()
    v.addRule("email", isEmail())
    let data = newTable[string, string]()
    data["email"] = "user@example.com"
    let errors = v.validateForm(data)
    check errors.len == 0

  test "minLength validator":
    let v = newFormValidator()
    v.addRule("name", minLength(2))
    let data = newTable[string, string]()
    data["name"] = "a"
    let errors = v.validateForm(data)
    check errors.len > 0

  test "maxLength validator":
    let v = newFormValidator()
    v.addRule("name", maxLength(5))
    let data = newTable[string, string]()
    data["name"] = "toolongname"
    let errors = v.validateForm(data)
    check errors.len > 0

  test "oneOf validator":
    let v = newFormValidator()
    v.addRule("color", oneOf(@["red", "green", "blue"]))
    let data = newTable[string, string]()
    data["color"] = "yellow"
    let errors = v.validateForm(data)
    check errors.len > 0

suite "LRU Cache":
  test "put and get":
    var cache = initLRUCache[string, string](capacity = 10)
    cache.put("key1", "value1")
    let val = cache.get("key1")
    check val.isSome
    check val.get == "value1"

  test "get missing key returns none":
    var cache = initLRUCache[string, string](capacity = 10)
    let val = cache.get("missing")
    check val.isNone

  test "eviction when capacity exceeded":
    var cache = initLRUCache[string, string](capacity = 2)
    cache.put("a", "1")
    cache.put("b", "2")
    cache.put("c", "3")
    check cache.get("a").isNone
    check cache.get("b").isSome
    check cache.get("c").isSome

  test "del removes entry":
    var cache = initLRUCache[string, string](capacity = 10)
    cache.put("key1", "value1")
    cache.del("key1")
    check cache.get("key1").isNone

  test "clear removes all":
    var cache = initLRUCache[string, string](capacity = 10)
    cache.put("a", "1")
    cache.put("b", "2")
    cache.clear()
    check cache.len == 0

  test "len returns count":
    var cache = initLRUCache[string, string](capacity = 10)
    cache.put("a", "1")
    cache.put("b", "2")
    check cache.len == 2

  test "hasKey":
    var cache = initLRUCache[string, string](capacity = 10)
    cache.put("key1", "value1")
    check cache.hasKey("key1") == true
    check cache.hasKey("missing") == false

suite "LFU Cache":
  test "put and get":
    var cache = initLFUCache[string, string](capacity = 10)
    cache.put("key1", "value1")
    let val = cache.get("key1")
    check val.isSome
    check val.get == "value1"

  test "get missing key returns none":
    var cache = initLFUCache[string, string](capacity = 10)
    let val = cache.get("missing")
    check val.isNone

  test "eviction when capacity exceeded":
    var cache = initLFUCache[string, string](capacity = 2)
    cache.put("a", "1")
    cache.put("b", "2")
    cache.put("c", "3")
    check cache.len == 2

  test "del removes entry and cleans freqTable":
    var cache = initLFUCache[string, string](capacity = 10)
    cache.put("key1", "value1")
    discard cache.get("key1")
    cache.del("key1")
    check cache.get("key1").isNone
    check cache.len == 0

  test "clear removes all":
    var cache = initLFUCache[string, string](capacity = 10)
    cache.put("a", "1")
    cache.put("b", "2")
    cache.clear()
    check cache.len == 0

suite "Response Helpers":
  test "html sets content type":
    let ctx = mockContext()
    ctx.html("<h1>Hello</h1>")
    check ctx.response.code == Http200
    check ctx.response.body == "<h1>Hello</h1>"
    check ctx.response.headers["Content-Type"] == "text/html; charset=utf-8"

  test "json sets content type":
    let ctx = mockContext()
    ctx.json(%*{"status": "ok"})
    check ctx.response.code == Http200
    check ctx.response.headers["Content-Type"] == "application/json; charset=utf-8"

  test "text sets content type":
    let ctx = mockContext()
    ctx.text("plain text")
    check ctx.response.code == Http200
    check ctx.response.body == "plain text"
    check ctx.response.headers["Content-Type"] == "text/plain; charset=utf-8"

  test "redirect sets location":
    let ctx = mockContext()
    ctx.redirect("/new-location")
    check ctx.response.code == Http301
    check ctx.response.headers["Location"] == "/new-location"

  test "temporary redirect":
    let ctx = mockContext()
    ctx.temporaryRedirect("/temp")
    check ctx.response.code == Http302

suite "Cookies":
  test "set and get cookie":
    let ctx = mockContext()
    ctx.setCookie("session", "abc123")
    var hasCookie = false
    for k, v in ctx.response.headers:
      if k == "set-cookie" and "session=abc123" in v:
        hasCookie = true
    check hasCookie

  test "delete cookie":
    let ctx = mockContext()
    ctx.deleteCookie("session")
    var hasCookie = false
    for k, v in ctx.response.headers:
      if k == "set-cookie" and "session=" in v:
        hasCookie = true
    check hasCookie

suite "Context Data":
  test "set and get context data":
    let ctx = mockContext()
    ctx["mykey"] = %"myvalue"
    check ctx["mykey"].getStr == "myvalue"

  test "get missing key returns JNull":
    let ctx = mockContext()
    check ctx["missing"].kind == JNull

suite "Error Handlers":
  test "custom 404 handler":
    let app = mockApp()
    app.registerErrorHandler(Http404, proc(ctx: Context) {.async.} =
      ctx.html("Custom 404", Http404)
    )
    let ctx = app.runOnce(HttpGet, "/nonexistent")
    check ctx.response.code == Http404
    check ctx.response.body == "Custom 404"

suite "Mocking Utilities":
  test "mockContext creates valid context":
    let ctx = mockContext(HttpGet, "/test")
    check ctx.request.httpMethod == HttpGet
    check ctx.request.url.path == "/test"
    check ctx.response.code == Http200

  test "mockApp creates valid application":
    let app = mockApp()
    check app != nil

  test "runOnce executes handler":
    let app = mockApp()
    app.get("/test", proc(ctx: Context) {.async.} =
      ctx.text("result")
    )
    let ctx = app.runOnce(HttpGet, "/test")
    check ctx.response.body == "result"
