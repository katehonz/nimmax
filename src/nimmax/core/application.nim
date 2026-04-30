import std/[asyncdispatch, httpcore, tables, json, strutils]
import ./types, ./settings, ./route, ./pages, ./exceptions

proc newApp*(
  settings: Settings = newSettings(),
  middlewares: seq[HandlerAsync] = @[],
  startup: seq[AppEvent] = @[],
  shutdown: seq[AppEvent] = @[],
  errorHandlerTable: Table[HttpCode, ErrorHandler] = newErrorHandlerTable()
): Application =
  result = Application(
    gScope: newGlobalScope(settings),
    globalMiddlewares: middlewares,
    startupEvents: startup,
    shutdownEvents: shutdown,
    errorHandlerTable: errorHandlerTable
  )

proc addRoute*(app: Application, httpMethod: HttpMethod, pattern: string,
               handler: HandlerAsync, middlewares: seq[HandlerAsync] = @[],
               name = "") =
  app.gScope.router.addRoute(httpMethod, pattern, handler, middlewares, name)

proc get*(app: Application, path: string, handler: HandlerAsync,
          middlewares: seq[HandlerAsync] = @[], name = "") =
  app.addRoute(HttpGet, path, handler, middlewares, name)

proc post*(app: Application, path: string, handler: HandlerAsync,
           middlewares: seq[HandlerAsync] = @[], name = "") =
  app.addRoute(HttpPost, path, handler, middlewares, name)

proc put*(app: Application, path: string, handler: HandlerAsync,
          middlewares: seq[HandlerAsync] = @[], name = "") =
  app.addRoute(HttpPut, path, handler, middlewares, name)

proc delete*(app: Application, path: string, handler: HandlerAsync,
             middlewares: seq[HandlerAsync] = @[], name = "") =
  app.addRoute(HttpDelete, path, handler, middlewares, name)

proc patch*(app: Application, path: string, handler: HandlerAsync,
            middlewares: seq[HandlerAsync] = @[], name = "") =
  app.addRoute(HttpPatch, path, handler, middlewares, name)

proc head*(app: Application, path: string, handler: HandlerAsync,
           middlewares: seq[HandlerAsync] = @[], name = "") =
  app.addRoute(HttpHead, path, handler, middlewares, name)

proc options*(app: Application, path: string, handler: HandlerAsync,
              middlewares: seq[HandlerAsync] = @[], name = "") =
  app.addRoute(HttpOptions, path, handler, middlewares, name)

proc all*(app: Application, path: string, handler: HandlerAsync,
          middlewares: seq[HandlerAsync] = @[], name = "") =
  app.get(path, handler, middlewares, name & "_get")
  app.post(path, handler, middlewares, name & "_post")
  app.put(path, handler, middlewares, name & "_put")
  app.delete(path, handler, middlewares, name & "_delete")
  app.patch(path, handler, middlewares, name & "_patch")

proc use*(app: Application, middlewares: varargs[HandlerAsync]) =
  for m in middlewares:
    app.globalMiddlewares.add(m)

proc registerErrorHandler*(app: Application, code: HttpCode, handler: ErrorHandler) =
  app.errorHandlerTable[code] = handler

proc registerErrorHandler*(app: Application, codes: set[HttpCode], handler: ErrorHandler) =
  for code in codes:
    app.errorHandlerTable[code] = handler

proc onStart*(app: Application, handler: Event) =
  app.startupEvents.add(AppEvent(async: false, syncHandler: handler))

proc onStartAsync*(app: Application, handler: AppAsyncEvent) =
  app.startupEvents.add(AppEvent(async: true, asyncHandler: handler))

proc onStop*(app: Application, handler: Event) =
  app.shutdownEvents.add(AppEvent(async: false, syncHandler: handler))

proc onStopAsync*(app: Application, handler: AppAsyncEvent) =
  app.shutdownEvents.add(AppEvent(async: true, asyncHandler: handler))

proc `[]`*(app: Application, key: string): JsonNode =
  app.gScope.appData.getOrDefault(key, newJNull())

proc `[]=`*(app: Application, key: string, value: JsonNode) =
  app.gScope.appData[key] = value

proc handleContext*(app: Application, ctx: Context) {.async.} =
  ctx.middlewares = @[]
  for m in app.globalMiddlewares:
    ctx.middlewares.add(m)

  let matchResult = app.gScope.router.matchRoute(ctx.request.httpMethod, ctx.request.url.path)

  if not matchResult.matched:
    ctx.response.code = Http404
    if app.errorHandlerTable.hasKey(Http404):
      await app.errorHandlerTable[Http404](ctx)
    return

  for p in matchResult.pathParams:
    ctx.request.pathParams[p.name] = p.value

  for m in matchResult.middlewares:
    ctx.middlewares.add(m)

  ctx.middlewares.add(matchResult.handler)

  ctx.middlewareIdx = 0
  ctx.first = true

  try:
    if ctx.middlewares.len > 0:
      await ctx.middlewares[0](ctx)
  except AbortError:
    discard
  except RouteError:
    ctx.response.code = Http404
    if app.errorHandlerTable.hasKey(Http404):
      await app.errorHandlerTable[Http404](ctx)
  except Exception:
    ctx.response.code = Http500
    ctx.response.body = getCurrentExceptionMsg()
    if app.errorHandlerTable.hasKey(Http500):
      await app.errorHandlerTable[Http500](ctx)

  if ctx.response.code.int >= 400 and app.errorHandlerTable.hasKey(ctx.response.code):
    await app.errorHandlerTable[ctx.response.code](ctx)

proc prepareRun*(app: Application) =
  for event in app.startupEvents:
    if not event.async:
      event.syncHandler()

proc shutdown*(app: Application) =
  for event in app.shutdownEvents:
    if not event.async:
      event.syncHandler()
