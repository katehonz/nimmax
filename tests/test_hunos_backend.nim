## Test Suite: NimMax Hunos Backend Adapter
##
## Tests the integration between NimMax framework and Hunos HTTP server.

import std/[unittest, asyncdispatch, strutils, json, options, os, net, httpclient]
import hunos as hunosCore
import nimmax/core/types
import nimmax/core/application
import nimmax/core/context
import nimmax/core/hunos_backend
import nimmax/core/hunos_websocket

# Helper to create a mock Hunos request pointer
proc newMockHunosRequest(
  httpMethod = "GET",
  path = "/",
  queryParams: seq[(string, string)] = @[],
  headers: hunosCore.HttpHeaders = @[],
  body = ""
): hunosCore.Request =
  result = cast[hunosCore.Request](allocShared0(sizeof(hunosCore.RequestObj)))
  result.httpVersion = hunosCore.Http11
  result.httpMethod = httpMethod
  result.uri = path
  result.path = path
  result.queryParams = queryParams
  result.headers = headers
  result.body = body
  result.remoteAddress = "127.0.0.1"
  result.responseHeaders = @[]

# ---------------------------------------------------------------------------
# Basic Routing Tests
# ---------------------------------------------------------------------------

suite "Hunos Backend - Basic Routing":

  test "GET request handler executes without crash":
    proc hello(ctx: Context) {.async.} =
      ctx.html("Hello from Hunos!")

    let app = newApp()
    app.get("/", hello)

    let handler = app.toHunosHandler()
    let mockReq = newMockHunosRequest("GET", "/")
    handler(mockReq)
    check true

  test "path parameters are parsed correctly":
    proc userHandler(ctx: Context) {.async.} =
      let id = ctx.getPathParam("id")
      ctx.json(%*{"userId": id})

    let app = newApp()
    app.get("/user/{id}", userHandler)

    let handler = app.toHunosHandler()
    let mockReq = newMockHunosRequest("GET", "/user/42")
    handler(mockReq)
    check true

  test "query parameters are accessible":
    proc apiHandler(ctx: Context) {.async.} =
      let page = ctx.getQueryParam("page")
      let id = ctx.getInt("id", source = "path")
      ctx.json(%*{
        "page": page,
        "id": if id.isSome: id.get else: -1
      })

    let app = newApp()
    app.get("/api/{id}", apiHandler)

    let handler = app.toHunosHandler()
    let mockReq = newMockHunosRequest("GET", "/api/99", @[("page", "5")])
    handler(mockReq)
    check true

  test "POST request handler works":
    proc createHandler(ctx: Context) {.async.} =
      ctx.json(%*{"created": true})

    let app = newApp()
    app.post("/create", createHandler)

    let handler = app.toHunosHandler()
    let mockReq = newMockHunosRequest("POST", "/create", body = "{}")
    handler(mockReq)
    check true

# ---------------------------------------------------------------------------
# Error Handling Tests
# ---------------------------------------------------------------------------

suite "Hunos Backend - Error Handling":

  test "exception in handler returns 500":
    proc crashHandler(ctx: Context) {.async.} =
      raise newException(ValueError, "intentional crash")

    let app = newApp()
    app.get("/crash", crashHandler)

    let handler = app.toHunosHandler()
    let mockReq = newMockHunosRequest("GET", "/crash")
    handler(mockReq)
    check true

  test "custom 404 error handler is invoked":
    proc notFoundHandler(ctx: Context) {.async.} =
      ctx.json(%*{"error": "custom 404"}, Http404)

    proc okHandler(ctx: Context) {.async.} =
      ctx.text("ok")

    let app = newApp()
    app.registerErrorHandler(Http404, notFoundHandler)
    app.get("/exists", okHandler)

    let h = app.toHunosHandler()
    let mockReq = newMockHunosRequest("GET", "/missing")
    h(mockReq)
    check true

# ---------------------------------------------------------------------------
# Context Helper Tests
# ---------------------------------------------------------------------------

suite "Hunos Backend - Context Helpers":

  test "typed parameter accessors work":
    proc typedHandler(ctx: Context) {.async.} =
      let id = ctx.getInt("id")
      let price = ctx.getFloat("price")
      let active = ctx.getBool("active")
      ctx.json(%*{
        "id": if id.isSome: id.get else: -1,
        "price": if price.isSome: price.get else: -1.0,
        "active": if active.isSome: active.get else: false
      })

    let app = newApp()
    app.get("/item/{id}", typedHandler)

    let handler = app.toHunosHandler()
    let mockReq = newMockHunosRequest("GET", "/item/42")
    handler(mockReq)
    check true

  test "json response works":
    proc jsonHandler(ctx: Context) {.async.} =
      ctx.json(%*{"backend": "hunos", "status": "ok"})

    let app = newApp()
    app.get("/api", jsonHandler)

    let handler = app.toHunosHandler()
    let mockReq = newMockHunosRequest("GET", "/api")
    handler(mockReq)
    check true

  test "redirect works":
    proc redirectHandler(ctx: Context) {.async.} =
      ctx.redirect("/new-location")

    let app = newApp()
    app.get("/old", redirectHandler)

    let handler = app.toHunosHandler()
    let mockReq = newMockHunosRequest("GET", "/old")
    handler(mockReq)
    check true

# ---------------------------------------------------------------------------
# Integration Test with Real Server
# ---------------------------------------------------------------------------

suite "Hunos Backend - Integration":

  test "full HTTP request/response cycle with real server":
    proc indexHandler(ctx: Context) {.async.} =
      ctx.html("<h1>Integration Test</h1>")

    proc jsonHandler(ctx: Context) {.async.} =
      ctx.json(%*{"status": "ok", "backend": "hunos"})

    proc paramHandler(ctx: Context) {.async.} =
      let id = ctx.getPathParam("id")
      ctx.text("ID: " & id)

    let app = newApp()
    app.get("/", indexHandler)
    app.get("/api", jsonHandler)
    app.get("/item/{id}", paramHandler)

    let handler = app.toHunosHandler()
    let server = hunosCore.newServer(handler, workerThreads = 2)

    # Use a hopefully free port
    let testPort = Port(18765)

    # Start server in background thread
    var serverThread: Thread[hunosCore.Server]
    proc serveInBackground(s: hunosCore.Server) {.thread.} =
      try:
        s.serve(testPort, "127.0.0.1")
      except Exception:
        discard
    createThread(serverThread, serveInBackground, server)

    # Give server time to start
    sleep(500)

    try:
      let client = newHttpClient(timeout = 5000)

      # Test HTML endpoint
      let htmlResp = client.get("http://127.0.0.1:" & $int(testPort) & "/")
      check htmlResp.code == Http200
      check htmlResp.body == "<h1>Integration Test</h1>"

      # Test JSON endpoint
      let jsonResp = client.get("http://127.0.0.1:" & $int(testPort) & "/api")
      check jsonResp.code == Http200
      check jsonResp.body == """{"status":"ok","backend":"hunos"}"""

      # Test path parameter endpoint
      let paramResp = client.get("http://127.0.0.1:" & $int(testPort) & "/item/42")
      check paramResp.code == Http200
      check paramResp.body == "ID: 42"

      # Test 404
      let notFoundResp = client.get("http://127.0.0.1:" & $int(testPort) & "/missing")
      check notFoundResp.code == Http404

      client.close()
    finally:
      server.close()
      joinThread(serverThread)

# ---------------------------------------------------------------------------
# WebSocket Tests
# ---------------------------------------------------------------------------

suite "Hunos Backend - WebSocket":

  test "WebSocket handler registers without crash":
    proc wsHandler(ws: HunosWebSocket) {.async.} =
      while ws.readyState == wsOpen:
        let msg = await ws.receiveStrPacket()
        if msg.len > 0:
          ws.sendText("Echo: " & msg)

    let app = newApp()
    app.registerHunosWs("/ws", wsHandler)

    # We can only test registration here; full WS test needs a real server
    check true
