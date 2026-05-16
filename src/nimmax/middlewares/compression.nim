import std/[asyncdispatch, httpcore, strutils]
import ../core/types, ../core/middleware, ../core/utils

type
  CompressionLevel* = enum
    clNone = 0
    clBestSpeed = 1
    clBestCompression = 9
    clDefault = 6

when not defined(nimmaxNoZippy):
  import zippy

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

      if level == clNone:
        return

      if ctx.response.body.len < minSize:
        return

      let contentType = ctx.request.headers.getHeader("Content-Type", "")
      if contentType.startsWith("image/") or contentType.startsWith("audio/") or
         contentType.startsWith("video/") or contentType.startsWith("application/zip"):
        return

      var compressed: string
      var encoding: string

      try:
        let dataLevel = case level
          of clNone: BestSpeed
          of clBestSpeed: BestSpeed
          of clBestCompression: BestCompression
          of clDefault: DefaultCompression

        if "gzip" in supportedEncodings:
          compressed = zippy.compress(ctx.response.body, level = dataLevel, dataFormat = dfGzip)
          encoding = "gzip"
        elif "deflate" in supportedEncodings:
          compressed = zippy.compress(ctx.response.body, level = dataLevel, dataFormat = dfZlib)
          encoding = "deflate"
      except:
        return

      if compressed.len > 0 and compressed.len < ctx.response.body.len:
        ctx.response.body = compressed
        ctx.response.headers["Content-Encoding"] = encoding
        ctx.response.headers["Content-Length"] = $compressed.len

        let existingValue = ctx.response.headers.getHeader("Vary", "")
        if existingValue.len == 0:
          ctx.response.headers["Vary"] = "Accept-Encoding"
        elif "Accept-Encoding" notin existingValue:
          ctx.response.headers["Vary"] = existingValue & ", Accept-Encoding"
      else:
        let existingValue = ctx.response.headers.getHeader("Vary", "")
        if existingValue.len == 0:
          ctx.response.headers["Vary"] = "Accept-Encoding"
        elif "Accept-Encoding" notin existingValue:
          ctx.response.headers["Vary"] = existingValue & ", Accept-Encoding"

else:
  ## Fallback when zippy is unavailable (nimmaxNoZippy defined).
  ## The middleware passes through without compression.
  proc compressionMiddleware*(
    minSize = 1024,
    level = clDefault,
    excludePaths: seq[string] = @[]
  ): HandlerAsync =
    result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
      await switch(ctx)
