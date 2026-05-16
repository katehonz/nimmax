## NimMax Hunos Backend Adapter
##
## Provides a Hunos HTTP server backend for the NimMax framework.
## Usage:
##   import nimmax/hunos
##   let app = newApp()
##   app.get("/", handler)
##   app.runHunos(port = Port(8080))

when not defined(nimmaxHunos):
  {.error: "Hunos backend requires the Hunos package. Install with: nimble install hunos, then compile with -d:nimmaxHunos. If you don't need the Hunos backend, use 'import nimmax' instead.".}

import std/[asynchttpserver, asyncdispatch, uri, tables, strutils, options, json, httpcore, locks]
import hunos
import ./types, ./application, ./context, ./request, ./response, ./settings, ./route, ./exceptions, ./utils
import ./hunos_websocket

# ---------------------------------------------------------------------------
# WebSocket route registry
# ---------------------------------------------------------------------------

var gHunosWsHandlers: Table[string, WSHandler]
var gHunosWsLock: Lock
initLock(gHunosWsLock)

proc registerHunosWs*(app: Application, path: string, handler: WSHandler) =
  ## Register a WebSocket handler for a given path on the Hunos backend.
  ## Usage:
  ##   app.registerHunosWs("/ws", proc(ws: HunosWebSocket) {.async.} = ...)
  withLock gHunosWsLock:
    gHunosWsHandlers[path] = handler

# ---------------------------------------------------------------------------
# Request Conversion
# ---------------------------------------------------------------------------

proc parseHunosHttpMethod*(methodStr: string): HttpMethod =
  ## Convert Hunos string HTTP method to NimMax HttpMethod enum.
  case methodStr.toUpperAscii()
  of "GET":     HttpGet
  of "POST":    HttpPost
  of "PUT":     HttpPut
  of "DELETE":  HttpDelete
  of "PATCH":   HttpPatch
  of "HEAD":    HttpHead
  of "OPTIONS": HttpOptions
  of "TRACE":   HttpTrace
  of "CONNECT": HttpConnect
  else:         HttpGet  # fallback

proc newNimMaxRequest*(hunosReq: hunos.Request): types.Request =
  ## Build a NimMax Request from a Hunos Request.
  let httpMethod = parseHunosHttpMethod(hunosReq.httpMethod)
  let url = parseUri(hunosReq.uri)

  # Convert query params
  var queryParams = newTable[string, string]()
  for (k, v) in hunosReq.queryParams:
    queryParams[k] = v

  # Convert path params
  var pathParams = newTable[string, string]()
  for (k, v) in hunosReq.pathParams.toBase:
    pathParams[k] = v

  # Convert headers
  var headers = newHttpHeaders()
  for (k, v) in hunosReq.headers:
    headers[k] = v

  result = types.Request(
    nativeRequest: default(asynchttpserver.Request),
    httpMethod: httpMethod,
    url: url,
    headers: headers,
    body: hunosReq.body,
    cookies: parseCookies(headers.getHeader("Cookie")),
    queryParams: queryParams,
    postParams: newTable[string, string](),
    pathParams: pathParams,
    formParams: FormPart(
      data: newTable[string, seq[string]](),
      files: newTable[string, seq[FormFile]]()
    )
  )

# ---------------------------------------------------------------------------
# Context Factory
# ---------------------------------------------------------------------------

proc newHunosContext*(app: Application, hunosReq: hunos.Request): types.Context =
  ## Create a NimMax Context wired to a Hunos request.
  let req = newNimMaxRequest(hunosReq)
  let resp = newResponse()
  result = types.Context(
    request: req,
    response: resp,
    handled: false,
    upgraded: false,
    session: nil,
    ctxData: newTable[string, JsonNode](),
    gScope: app.gScope,
    middlewares: @[],
    middlewareIdx: 0,
    first: true
  )

# ---------------------------------------------------------------------------
# Handler Adapter
# ---------------------------------------------------------------------------

proc toHunosHandler*(app: Application): RequestHandler =
  ## Convert a NimMax Application into a Hunos RequestHandler.
  result = proc(hunosReq: hunos.Request) {.gcsafe.} =
    # Check for WebSocket upgrade requests first
    let upgrade = hunosReq.headers["Upgrade"].toLowerAscii()
    if upgrade == "websocket":
      var wsHandler: WSHandler
      {.gcsafe.}:
        withLock gHunosWsLock:
          wsHandler = gHunosWsHandlers.getOrDefault(hunosReq.path, nil)
      if wsHandler != nil:
        startHunosWs(hunosReq, wsHandler)
        return

    let ctx = newHunosContext(app, hunosReq)

    try:
      waitFor app.handleContext(ctx)
    except AbortError:
      discard  # abortRequest already sets ctx.response
    except Exception as e:
      ctx.response.code = Http500
      ctx.response.body = e.msg
      if app.errorHandlerTable.hasKey(Http500):
        try:
          waitFor app.errorHandlerTable[Http500](ctx)
        except Exception:
          discard

    # Send response back through Hunos unless WebSocket upgraded
    if not ctx.upgraded and not hunosReq.server.isNil:
      var respHeaders: hunos.HttpHeaders = @[]
      for k, v in ctx.response.headers:
        respHeaders.add((k, v))
      hunosReq.respond(ctx.response.code.int, respHeaders, ctx.response.body)

# ---------------------------------------------------------------------------
# Server Lifecycle
# ---------------------------------------------------------------------------

proc runHunos*(
  app: Application,
  address = "",
  port: Port = Port(0),
  debug = true
) =
  ## Start the NimMax application on the Hunos multi-threaded backend.
  app.prepareRun()

  let settings = app.gScope.settings
  let actualAddress = if address.len > 0: address else: settings.address
  let actualPort = if port.int != 0: port else: settings.port

  if debug:
    echo "NimMax (Hunos backend) starting on " & actualAddress & ":" & $int(actualPort)
    if settings.debug:
      echo "Debug mode: true"
      echo "Registered routes:"
      for methodKey, routes in app.gScope.router.routes:
        for route in routes:
          echo "  " & methodKey & " " & route.pattern &
               (if route.name.len > 0: " (" & route.name & ")" else: "")

  let handler = app.toHunosHandler()
  let server = hunos.newServer(handler, websocketHandler = hunosWebSocketHandler)

  try:
    server.serve(actualPort, actualAddress)
  finally:
    app.shutdown()

proc serveHunos*(app: Application) =
  ## Start serving with Hunos backend using settings from the app.
  let settings = app.gScope.settings
  app.runHunos(address = settings.address, port = settings.port, debug = settings.debug)
