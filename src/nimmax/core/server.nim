import std/[asynchttpserver, asyncdispatch, net, strutils, os, locks, times]
import ./types, ./application, ./context, ./constants, ./utils

var
  gApp: Application
  gServer: AsyncHttpServer
  gShutdownRequested: bool
  gActiveRequests: int
  gShutdownLock: Lock

proc shutdownHandler() {.noconv.} =
  echo "\nShutdown signal received..."
  gShutdownRequested = true
  if not gApp.isNil:
    gApp.shutdown()
  echo "Waiting for active requests to finish..."
  let timeout = if gApp.isNil: 30 else: gApp.gScope.settings.shutdownTimeout
  let startTime = epochTime()
  while gActiveRequests > 0:
    let elapsed = epochTime() - startTime
    if elapsed > float(timeout):
      echo "Shutdown timeout reached. Forcing exit with " & $gActiveRequests & " active requests."
      break
    sleep(100)
  echo "Shutdown complete."
  quit(0)

proc createHandler(app: Application): proc(req: asynchttpserver.Request): Future[void] {.closure, gcsafe.} =
  result = proc(req: asynchttpserver.Request): Future[void] {.async, gcsafe.} =
    if gShutdownRequested:
      await req.respond(Http503, "Service Unavailable", newHttpHeaders([("Retry-After", "30")]))
      return

    atomicInc(gActiveRequests)
    try:
      let contentLength = parseInt(req.headers.getHeader("Content-Length", "0"))
      var body = ""
      if contentLength > 0 and contentLength <= app.gScope.settings.bufSize:
        body = req.body

      let ctx = newContext(app.gScope, req, body)

      await app.handleContext(ctx)

      await req.respond(ctx.response.code, ctx.response.body, ctx.response.headers)
    finally:
      atomicDec(gActiveRequests)

proc serve*(app: Application) =
  app.prepareRun()

  let settings = app.gScope.settings
  let address = settings.address
  let port = settings.port

  gApp = app
  gShutdownRequested = false
  gActiveRequests = 0
  initLock(gShutdownLock)

  gServer = newAsyncHttpServer()

  echo "NimMax " & nimMaxVersion & " starting on " & address & ":" & $int(port)
  echo "Debug mode: " & $settings.debug
  echo "Shutdown timeout: " & $settings.shutdownTimeout & "s"

  if settings.debug:
    echo "Registered routes:"
    for methodKey, routes in app.gScope.router.routes:
      for route in routes:
        echo "  " & methodKey & " " & route.pattern &
             (if route.name.len > 0: " (" & route.name & ")" else: "")

  setControlCHook(shutdownHandler)

  waitFor gServer.serve(port, createHandler(app), address)

proc run*(
  app: Application,
  address = "",
  port: Port = Port(0),
  debug = true
) =
  if address.len > 0:
    app.gScope.settings.address = address
  if port != Port(0):
    app.gScope.settings.port = port
  app.gScope.settings.debug = debug
  serve(app)

proc closeServer*(timeout: int = 30) =
  echo "Closing server gracefully..."
  gShutdownRequested = true
  let startTime = epochTime()
  while gActiveRequests > 0:
    let elapsed = epochTime() - startTime
    if elapsed > float(timeout):
      echo "Force closing with " & $gActiveRequests & " active requests."
      break
    sleep(100)
  if not gServer.isNil:
    gServer.close()
  echo "Server closed."
