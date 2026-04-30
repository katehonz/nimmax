import std/[strutils, httpcore, asyncdispatch]
import ../core/types, ../core/middleware, ../core/context

proc loggingMiddleware*(appName = "NimMax"): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let startTime = cpuTime()
    await switch(ctx)
    let elapsed = cpuTime() - startTime
    let httpMethod = $ctx.request.httpMethod
    let path = ctx.request.url.path
    let code = ctx.response.code.int
    echo appName & " | " & httpMethod & " " & path & " -> " & $code & " (" &
         formatFloat(elapsed * 1000, ffDecimal, 2) & "ms)"

proc debugRequestMiddleware*(appName = "NimMax"): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    echo "--- Request Debug ---"
    echo "Method: " & $ctx.request.httpMethod
    echo "Path: " & ctx.request.url.path
    echo "Query: " & ctx.request.url.query
    echo "Headers:"
    for k, v in ctx.request.headers:
      echo "  " & k & ": " & v
    echo "Body length: " & $ctx.request.body.len
    echo "---"
    await switch(ctx)

proc debugResponseMiddleware*(appName = "NimMax"): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    await switch(ctx)
    echo "--- Response Debug ---"
    echo "Code: " & $ctx.response.code.int
    echo "Headers:"
    for k, v in ctx.response.headers:
      echo "  " & k & ": " & v
    echo "Body length: " & $ctx.response.body.len
    echo "---"

proc stripPathMiddleware*(): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    var path = ctx.request.url.path
    if path.len > 1 and path.endsWith('/'):
      path = path[0 .. ^2]
      ctx.request.url.path = path
    await switch(ctx)

proc httpRedirectMiddleware*(fromPath, toPath: string): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    if ctx.request.url.path == fromPath:
      ctx.redirect(toPath, Http301)
      return
    await switch(ctx)
