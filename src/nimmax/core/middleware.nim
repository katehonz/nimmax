import std/[asyncdispatch]
import ./types

proc compose*(middlewares: openArray[HandlerAsync]): HandlerAsync =
  let mws = @middlewares
  if mws.len == 0:
    return proc(ctx: Context): Future[void] {.async, gcsafe.} =
      discard

  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let savedMiddlewares = ctx.middlewares
    let savedIdx = ctx.middlewareIdx
    ctx.middlewares = @[]
    for m in mws:
      ctx.middlewares.add(m)
    ctx.middlewareIdx = 0
    if ctx.middlewares.len > 0:
      await ctx.middlewares[0](ctx)
    ctx.middlewares = savedMiddlewares
    ctx.middlewareIdx = savedIdx

proc switch*(ctx: Context) {.async.} =
  inc ctx.middlewareIdx
  if ctx.middlewareIdx < ctx.middlewares.len:
    await ctx.middlewares[ctx.middlewareIdx](ctx)

proc chain*(before, after: HandlerAsync): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    await before(ctx)
    await switch(ctx)
    await after(ctx)

proc onlyGet*(handler: HandlerAsync): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    if ctx.request.httpMethod == HttpGet:
      await handler(ctx)
    else:
      await switch(ctx)

proc onlyPost*(handler: HandlerAsync): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    if ctx.request.httpMethod == HttpPost:
      await handler(ctx)
    else:
      await switch(ctx)

proc skip*(handler: HandlerAsync): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    await switch(ctx)
