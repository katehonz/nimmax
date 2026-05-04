import std/[asyncdispatch, json]
import ../core/types, ../core/context, ../core/middleware, ../core/utils

proc jsonBodyMiddleware*(): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let contentType = ctx.request.headers.getHeader("Content-Type", "")
    if "json" in contentType:
      try:
        let node = ctx.getJsonBody()
        ctx.ctxData["_jsonBody"] = node
      except ValueError:
        ctx.abortRequest(Http400, "Invalid JSON body")
    await switch(ctx)
