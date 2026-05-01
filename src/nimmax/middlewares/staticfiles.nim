import std/[asyncdispatch, os, strutils, httpcore, times]
import ../core/types, ../core/middleware, ../core/utils

proc staticFileMiddleware*(dirs: varargs[string]): HandlerAsync =
  let staticDirs = @dirs
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    if ctx.request.httpMethod != HttpGet and ctx.request.httpMethod != HttpHead:
      await switch(ctx)
      return

    let path = ctx.request.url.path
    for dir in staticDirs:
      let relPath = path[1 .. ^1]
      let filePath = dir / relPath
      let realPath = expandFilename(filePath)
      let realDir = expandFilename(dir)
      if not realPath.startsWith(realDir):
        continue
      if fileExists(filePath):
        let ext = filePath.splitFile().ext
        let contentType = getContentType(ext)
        let content = readFile(filePath)
        let etag = "\"" & $content.len & "-" & $toUnix(getLastModificationTime(filePath)).int64 & "\""

        let ifNoneMatch = ctx.request.headers.getHeader("If-None-Match", "")
        if ifNoneMatch == etag:
          ctx.response.code = Http304
          ctx.response.body = ""
          return

        ctx.response.code = Http200
        ctx.response.body = content
        ctx.response.headers["Content-Type"] = contentType
        ctx.response.headers["Content-Length"] = $content.len
        ctx.response.headers["ETag"] = etag
        ctx.response.headers["Cache-Control"] = "public, max-age=3600"
        return

    await switch(ctx)

proc serveStaticFile*(ctx: Context, dir: string, path: string): bool =
  let filePath = dir / path
  if not fileExists(filePath):
    return false

  let ext = filePath.splitFile().ext
  let contentType = getContentType(ext)
  let content = readFile(filePath)

  ctx.response.code = Http200
  ctx.response.body = content
  ctx.response.headers["Content-Type"] = contentType
  ctx.response.headers["Content-Length"] = $content.len
  result = true
