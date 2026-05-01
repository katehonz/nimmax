import std/[asyncdispatch, httpcore, strutils]
import ../core/types, ../core/middleware, ../core/utils

type
  CompressionLevel* = enum
    clNone = 0
    clBestSpeed = 1
    clBestCompression = 9
    clDefault = 6

proc compressionMiddleware*(
  minSize = 1024,
  level = clDefault,
  excludePaths: seq[string] = @[]
): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    for path in excludePaths:
      if ctx.request.url.path.startsWith(path):
        await switch(ctx)
        return

    let acceptEncoding = ctx.request.headers.getHeader("Accept-Encoding", "")
    if acceptEncoding.len == 0:
      await switch(ctx)
      return

    var supportedEncodings: seq[string] = @[]
    if "gzip" in acceptEncoding or "*" in acceptEncoding:
      supportedEncodings.add("gzip")
    if "deflate" in acceptEncoding:
      supportedEncodings.add("deflate")

    if supportedEncodings.len == 0:
      await switch(ctx)
      return

    await switch(ctx)

    if ctx.response.body.len < minSize:
      return

    let contentType = ctx.response.headers.getHeader("Content-Type", "")
    if contentType.startsWith("image/") or contentType.startsWith("audio/") or contentType.startsWith("video/"):
      return

    if "gzip" in supportedEncodings:
      ctx.response.headers["Vary"] = "Accept-Encoding"
    elif "deflate" in supportedEncodings:
      ctx.response.headers["Vary"] = "Accept-Encoding"
