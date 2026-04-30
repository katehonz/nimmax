import std/[strutils, httpcore, asyncdispatch]
import ../core/types, ../core/middleware, ../core/context, ../core/utils

proc corsMiddleware*(
  allowOrigins: seq[string] = @["*"],
  allowMethods: seq[string] = @["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
  allowHeaders: seq[string] = @["Content-Type", "Authorization"],
  exposeHeaders: seq[string] = @[],
  allowCredentials = false,
  maxAge = 7200,
  excludePaths: seq[string] = @[]
): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let origin = ctx.request.headers.getHeader("Origin")

    var excluded = false
    for path in excludePaths:
      if ctx.request.url.path.startsWith(path):
        excluded = true
        break

    if not excluded and origin.len > 0:
      var allowed = false
      for o in allowOrigins:
        if o == "*" or o == origin:
          allowed = true
          break

      if allowed:
        ctx.response.headers["Access-Control-Allow-Origin"] =
          if allowOrigins.len == 1 and allowOrigins[0] == "*": "*"
          else: origin

        if allowCredentials:
          ctx.response.headers["Access-Control-Allow-Credentials"] = "true"

        if exposeHeaders.len > 0:
          ctx.response.headers["Access-Control-Expose-Headers"] = exposeHeaders.join(", ")

      if ctx.request.httpMethod == HttpOptions:
        let reqMethod = ctx.request.headers.getHeader("Access-Control-Request-Method")
        let reqHeaders = ctx.request.headers.getHeader("Access-Control-Request-Headers")

        ctx.response.headers["Access-Control-Allow-Methods"] = allowMethods.join(", ")
        ctx.response.headers["Access-Control-Allow-Headers"] =
          if reqHeaders.len > 0: reqHeaders
          else: allowHeaders.join(", ")
        ctx.response.headers["Access-Control-Max-Age"] = $maxAge

        ctx.response.code = Http204
        ctx.response.body = ""
        return

    await switch(ctx)
