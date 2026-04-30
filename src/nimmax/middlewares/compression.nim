import std/[zlib, streams, strutils, httpcore, asyncdispatch]
import ../core/types, ../core/middleware, ../core/context

type
  CompressionLevel* = enum
    clNone = 0
    clBestSpeed = 1
    clBestCompression = 9
    clDefault = 6

proc compressGzip*(data: string, level: CompressionLevel = clDefault): string =
  if data.len == 0:
    return ""
  var outputStream = newStringStream()
  var compressStream = newZlibStream(outputStream, fmWrite, level = ord(level))
  compressStream.write(data)
  compressStream.close()
  result = outputStream.data

proc decompressGzip*(data: string): string =
  if data.len == 0:
    return ""
  var inputStream = newStringStream(data)
  var decompressStream = newZlibStream(inputStream, fmRead)
  result = decompressStream.readAll()
  decompressStream.close()

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
    if "br" in acceptEncoding:
      supportedEncodings.add("br")

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
      let compressed = compressGzip(ctx.response.body, level)
      if compressed.len < ctx.response.body.len:
        ctx.response.body = compressed
        ctx.response.headers["Content-Encoding"] = "gzip"
        ctx.response.headers["Content-Length"] = $compressed.len
        ctx.response.headers["Vary"] = "Accept-Encoding"
    elif "deflate" in supportedEncodings:
      let compressed = compressGzip(ctx.response.body, level)
      if compressed.len < ctx.response.body.len:
        ctx.response.body = compressed
        ctx.response.headers["Content-Encoding"] = "deflate"
        ctx.response.headers["Content-Length"] = $compressed.len
        ctx.response.headers["Vary"] = "Accept-Encoding"