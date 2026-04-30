import std/[asyncdispatch, strutils, times]
import ../core/types, ../core/middleware, ../core/context, ../core/utils

type
  RequestIdHeader* = object
    name*: string
    extract*: proc(headers: HttpHeaders): string {.gcsafe.}
    generate*: proc(): string

var defaultRequestIdHeader* = "X-Request-ID"

proc generateRequestId*(): string =
  let timestamp = now().toUnix()
  let randomPart = randomString(16)
  result = $timestamp & "-" & randomPart

proc requestIdMiddleware*(
  headerName: string = defaultRequestIdHeader,
  generateId: proc(): string = generateRequestId,
  includeInResponse: bool = true
): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    var requestId = ""

    let existingId = ctx.request.headers.getHeader(headerName)
    if existingId.len > 0:
      requestId = existingId
    else:
      requestId = generateId()

    ctx[headerName] = %requestId

    if includeInResponse:
      ctx.response.headers[headerName] = requestId

    await switch(ctx)

proc requestLoggingMiddleware*(includeRequestId: bool = true): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let startTime = cpuTime()
    let requestId = if includeRequestId: ctx["X-Request-ID"].getStr("") else: ""
    let reqIdStr = if requestId.len > 0: " [" & requestId & "]" else: ""

    await switch(ctx)

    let elapsed = cpuTime() - startTime
    let httpMethod = $ctx.request.httpMethod
    let path = ctx.request.url.path
    let code = ctx.response.code.int
    echo "NimMax" & reqIdStr & " | " & httpMethod & " " & path & " -> " & $code & " (" &
         formatFloat(elapsed * 1000, ffDecimal, 2) & "ms)"