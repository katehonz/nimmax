import std/[httpcore, tables, json, strutils, options, os, times]
import ./types, ./request, ./response, ./route, ./utils, ./exceptions

proc parseContentRange*(rangeHeader: string, totalSize: int): Option[(int, int)]

proc newContext*(
  gScope: GlobalScope,
  nativeReq: NativeRequest,
  body = ""
): Context =
  let req = newRequest(nativeReq, body)
  let resp = newResponse()
  result = Context(
    request: req,
    response: resp,
    handled: false,
    session: nil,
    ctxData: newTable[string, JsonNode](),
    gScope: gScope,
    middlewares: @[],
    middlewareIdx: 0,
    first: true
  )

proc getPathParams*(ctx: Context): TableRef[string, string] =
  ctx.request.pathParams

proc getQueryParam*(ctx: Context, key: string): string =
  ctx.request.getQueryParam(key)

proc getPostParam*(ctx: Context, key: string): string =
  ctx.request.getPostParam(key)

proc getPathParam*(ctx: Context, key: string): string =
  ctx.request.getPathParam(key)

proc getInt*(ctx: Context, key: string, source = "path"): Option[int] =
  case source
  of "path": ctx.request.pathParams.getInt(key)
  of "query": ctx.request.queryParams.getInt(key)
  of "post": ctx.request.postParams.getInt(key)
  else: none(int)

proc getFloat*(ctx: Context, key: string, source = "path"): Option[float] =
  case source
  of "path": ctx.request.pathParams.getFloat(key)
  of "query": ctx.request.queryParams.getFloat(key)
  of "post": ctx.request.postParams.getFloat(key)
  else: none(float)

proc getBool*(ctx: Context, key: string, source = "query"): Option[bool] =
  case source
  of "path": ctx.request.pathParams.getBool(key)
  of "query": ctx.request.queryParams.getBool(key)
  of "post": ctx.request.postParams.getBool(key)
  else: none(bool)

proc setResponse*(ctx: Context, resp: Response) =
  ctx.response = resp

proc respond*(ctx: Context, body: string, code = Http200, headers: HttpHeaders = nil) =
  ctx.response.code = code
  ctx.response.body = body
  if not headers.isNil:
    for k, v in headers:
      ctx.response.headers[k] = v

proc send*(ctx: Context, body: string, code = Http200, contentType = "text/html; charset=utf-8") =
  ctx.response.code = code
  ctx.response.body = body
  ctx.response.headers["Content-Type"] = contentType

proc html*(ctx: Context, body: string, code = Http200) =
  ctx.send(body, code, "text/html; charset=utf-8")

proc text*(ctx: Context, body: string, code = Http200) =
  ctx.send(body, code, "text/plain; charset=utf-8")

proc json*(ctx: Context, data: JsonNode, code = Http200) =
  ctx.send($data, code, "application/json; charset=utf-8")

proc json*(ctx: Context, data: string, code = Http200) =
  ctx.send(data, code, "application/json; charset=utf-8")

proc redirect*(ctx: Context, url: string, code = Http301) =
  ctx.response.code = code
  ctx.response.headers["Location"] = url

proc temporaryRedirect*(ctx: Context, url: string) =
  ctx.redirect(url, Http302)

proc seeOther*(ctx: Context, url: string) =
  ctx.redirect(url, Http303)

proc abortRequest*(ctx: Context, code: HttpCode, body = "") =
  ctx.response.code = code
  ctx.response.body = body
  raise newAbortError(code, body)

proc getCookie*(ctx: Context, name: string): string =
  ctx.request.getCookie(name)

proc setCookie*(ctx: Context, name, value: string, path = "/",
                domain = "", maxAge = 0, httpOnly = false,
                secure = false, sameSite = "Lax") =
  ctx.response.setCookie(name, value, path, domain, maxAge, httpOnly, secure, sameSite)

proc deleteCookie*(ctx: Context, name: string, path = "/") =
  ctx.response.setCookie(name, "", path = path, maxAge = 0)

proc urlFor*(ctx: Context, name: string, params: seq[(string, string)] = @[]): string =
  ctx.gScope.router.buildUrl(name, params)

proc getSettings*(ctx: Context): Settings =
  ctx.gScope.settings

proc `[]`*(ctx: Context, key: string): JsonNode =
  ctx.ctxData.getOrDefault(key, newJNull())

proc `[]=`*(ctx: Context, key: string, value: JsonNode) =
  ctx.ctxData[key] = value

proc flash*(ctx: Context, msg: string, category = flInfo) =
  if ctx.session.isNil:
    return
  let key = "_flash_" & $category
  var msgs: seq[string]
  if ctx.session.data.hasKey(key):
      try:
        msgs = parseJson(ctx.session.data[key]).to(seq[string])
      except JsonParsingError:
        msgs = @[]
  msgs.add(msg)
  ctx.session.data[key] = $(%msgs)
  ctx.session.modified = true

proc getFlashedMsgs*(ctx: Context): seq[string] =
  if ctx.session.isNil:
    return @[]
  result = @[]
  for level in FlashLevel:
    let key = "_flash_" & $level
    if ctx.session.data.hasKey(key):
      try:
        let msgs = parseJson(ctx.session.data[key]).to(seq[string])
        result.add(msgs)
        ctx.session.data.del(key)
        ctx.session.modified = true
      except JsonParsingError:
        discard

proc getFlashedMsgsWithCategory*(ctx: Context): seq[(FlashLevel, string)] =
  if ctx.session.isNil:
    return @[]
  result = @[]
  for level in FlashLevel:
    let key = "_flash_" & $level
    if ctx.session.data.hasKey(key):
      try:
        let msgs = parseJson(ctx.session.data[key]).to(seq[string])
        for msg in msgs:
          result.add((level, msg))
        ctx.session.data.del(key)
        ctx.session.modified = true
      except JsonParsingError:
        discard

proc staticFileResponse*(ctx: Context, filePath: string, downloadName = "") =
  if not fileExists(filePath):
    ctx.abortRequest(Http404, "File not found")
    return

  if dirExists(filePath):
    ctx.abortRequest(Http403, "Directory access forbidden")
    return

  let ext = filePath.splitFile().ext
  let contentType = getContentType(ext)
  let contentLen = getFileSize(filePath)
  let modTime = getLastModificationTime(filePath)

  ctx.response.code = Http200
  ctx.response.body = ""
  ctx.response.headers["Content-Type"] = contentType
  ctx.response.headers["Content-Length"] = $contentLen

  if downloadName.len > 0:
    ctx.response.headers["Content-Disposition"] = "attachment; filename=\"" & downloadName & "\""

  let etag = "\"" & $modTime & "-" & $contentLen & "\""
  ctx.response.headers["ETag"] = etag
  let httpDate = format(utc(modTime), "ddd, dd MMM yyyy HH:mm:ss 'GMT'")
  ctx.response.headers["Last-Modified"] = httpDate

  let ifNoneMatch = ctx.request.headers.getHeader("If-None-Match", "")
  if ifNoneMatch == etag:
    ctx.response.code = Http304
    ctx.response.body = ""
    return

  let ifModifiedSince = ctx.request.headers.getHeader("If-Modified-Since", "")
  if ifModifiedSince.len > 0:
    try:
      let clientTime = parseTime(ifModifiedSince, "ddd, dd MMM yyyy HH:mm:ss 'GMT'", utc())
      let modTimeUtc = utc(modTime)
      let clientDateTime = clientTime.inZone(utc())
      if clientDateTime <= modTimeUtc:
        ctx.response.code = Http304
        ctx.response.body = ""
        return
    except TimeParseError:
      discard

  ctx.response.headers["Accept-Ranges"] = "bytes"

  let rangeHeader = ctx.request.headers.getHeader("Range", "")
  if rangeHeader.len > 0 and rangeHeader.startsWith("bytes="):
    let ranges = parseContentRange(rangeHeader, contentLen)
    if ranges.isSome:
      let (startByte, endByte) = ranges.get
      let fullContent = readFile(filePath)
      let slice = fullContent[startByte .. endByte]
      ctx.response.code = Http206
      ctx.response.body = slice
      ctx.response.headers["Content-Length"] = $slice.len
      ctx.response.headers["Content-Range"] = "bytes " & $startByte & "-" & $endByte & "/" & $contentLen
      return

  let content = readFile(filePath)
  ctx.response.body = content

proc parseContentRange*(rangeHeader: string, totalSize: int): Option[(int, int)] =
  let rangeStr = rangeHeader[6 .. ^1]
  let parts = rangeStr.split("-")
  if parts.len != 2:
    return none((int, int))
  try:
    let startByte = if parts[0].len > 0: parseInt(parts[0]) else: 0
    let endByte = if parts[1].len > 0: parseInt(parts[1]) else: totalSize - 1
    if startByte >= 0 and endByte < totalSize and startByte <= endByte:
      return some((startByte, endByte))
  except ValueError:
    discard
  return none((int, int))
