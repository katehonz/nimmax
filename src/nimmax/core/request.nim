import std/[uri, strutils, tables, httpcore, options]
import ./types, ./utils

proc newRequest*(nativeReq: NativeRequest, body = ""): Request =
  result = Request(
    nativeRequest: nativeReq,
    httpMethod: nativeReq.reqMethod,
    url: nativeReq.url,
    headers: nativeReq.headers,
    body: body,
    cookies: parseCookies(nativeReq.headers.getHeader("Cookie")),
    queryParams: parseQueryParams(nativeReq.url.query),
    postParams: newTable[string, string](),
    pathParams: newTable[string, string](),
    formParams: FormPart(
      data: newTable[string, seq[string]](),
      files: newTable[string, seq[FormFile]]()
    )
  )

proc path*(req: Request): string =
  req.url.path

proc query*(req: Request): string =
  req.url.query

proc scheme*(req: Request): string =
  if req.url.scheme.len > 0: req.url.scheme else: "http"

proc hostName*(req: Request): string =
  $req.headers["Host"]

proc contentType*(req: Request): string =
  $req.headers["Content-Type"]

proc userAgent*(req: Request): string =
  $req.headers["User-Agent"]

proc reqMethod*(req: Request): HttpMethod =
  req.httpMethod

proc secure*(req: Request): bool =
  req.scheme == "https"

proc `[]`*(params: TableRef[string, string], key: string): string =
  if params.isNil: return ""
  params.getOrDefault(key, "")

proc `[]=`*(params: TableRef[string, string], key, value: string) =
  if params.isNil: return
  params[key] = value

proc getOption*(params: TableRef[string, string], key: string): Option[string] =
  if params.isNil: return none(string)
  if params.hasKey(key): some(params[key]) else: none(string)

proc getInt*(params: TableRef[string, string], key: string): Option[int] =
  let val = params.getOption(key)
  if val.isSome:
    try:
      some(parseInt(val.get))
    except ValueError:
      none(int)
  else:
    none(int)

proc getFloat*(params: TableRef[string, string], key: string): Option[float] =
  let val = params.getOption(key)
  if val.isSome:
    try:
      some(parseFloat(val.get))
    except ValueError:
      none(float)
  else:
    none(float)

proc getBool*(params: TableRef[string, string], key: string): Option[bool] =
  let val = params.getOption(key)
  if val.isSome:
    let lower = val.get.toLowerAscii()
    case lower
    of "true", "1", "yes", "on": some(true)
    of "false", "0", "no", "off": some(false)
    else: none(bool)
  else:
    none(bool)

proc hasKey*(params: TableRef[string, string], key: string): bool =
  if params.isNil: return false
  params.hasKey(key)

proc getPathParam*(req: Request, key: string): string =
  req.pathParams[key]

proc getPathParamInt*(req: Request, key: string): Option[int] =
  req.pathParams.getInt(key)

proc getPathParamFloat*(req: Request, key: string): Option[float] =
  req.pathParams.getFloat(key)

proc getQueryParam*(req: Request, key: string): string =
  req.queryParams[key]

proc getQueryParamInt*(req: Request, key: string): Option[int] =
  req.queryParams.getInt(key)

proc getQueryParamFloat*(req: Request, key: string): Option[float] =
  req.queryParams.getFloat(key)

proc getQueryParamBool*(req: Request, key: string): Option[bool] =
  req.queryParams.getBool(key)

proc getPostParam*(req: Request, key: string): string =
  req.postParams[key]

proc getCookie*(req: Request, name: string): string =
  req.cookies.getOrDefault(name, "")

proc hasCookie*(req: Request, name: string): bool =
  req.cookies.hasKey(name)

proc `[]`*(req: Request, key: string): string =
  req.pathParams.getOrDefault(key,
    req.queryParams.getOrDefault(key,
      req.postParams.getOrDefault(key, "")))
