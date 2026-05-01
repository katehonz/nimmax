import std/[asyncdispatch, httpcore, tables, json, uri, asynchttpserver]
import ../core/types as coreTypes, ../core/response, ../core/application, ../core/settings, ../core/utils

proc mockRequest*(
  httpMethod = HttpGet,
  path = "/",
  headers: HttpHeaders = nil,
  body = "",
  queryParams: TableRef[string, string] = nil,
  postParams: TableRef[string, string] = nil
): coreTypes.Request =
  let url = parseUri(path)
  let h = if headers.isNil: newHttpHeaders() else: headers
  let qp = if not queryParams.isNil: queryParams
           elif url.query.len > 0: parseQueryParams(url.query)
           else: newTable[string, string]()
  let pp = if postParams.isNil: newTable[string, string]() else: postParams

  coreTypes.Request(
    nativeRequest: default(asynchttpserver.Request),
    httpMethod: httpMethod,
    url: url,
    headers: h,
    body: body,
    cookies: newTable[string, string](),
    queryParams: qp,
    postParams: pp,
    pathParams: newTable[string, string](),
    formParams: FormPart(
      data: newTable[string, seq[string]](),
      files: newTable[string, seq[FormFile]]()
    )
  )

proc mockContext*(
  httpMethod = HttpGet,
  path = "/",
  headers: HttpHeaders = nil,
  body = "",
  settings: Settings = nil,
  queryParams: TableRef[string, string] = nil,
  postParams: TableRef[string, string] = nil
): Context =
  let s = if settings.isNil: newSettings() else: settings
  let gScope = newGlobalScope(s)
  let req = mockRequest(httpMethod, path, headers, body, queryParams, postParams)
  let resp = newResponse()

  Context(
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

proc mockApp*(settings: Settings = nil): Application =
  let s = if settings.isNil: newSettings() else: settings
  newApp(s)

proc mockContextWithApp*(
  app: Application,
  httpMethod = HttpGet,
  path = "/",
  headers: HttpHeaders = nil,
  body = ""
): Context =
  let req = mockRequest(httpMethod, path, headers, body)
  let resp = newResponse()

  Context(
    request: req,
    response: resp,
    handled: false,
    session: nil,
    ctxData: newTable[string, JsonNode](),
    gScope: app.gScope,
    middlewares: @[],
    middlewareIdx: 0,
    first: true
  )

proc runOnce*(app: Application, httpMethod = HttpGet, path = "/",
              headers: HttpHeaders = nil, body = ""): Context =
  let ctx = mockContextWithApp(app, httpMethod, path, headers, body)
  waitFor app.handleContext(ctx)
  result = ctx

proc debugResponse*(ctx: Context) =
  echo "=== Response ==="
  echo "Status: " & $ctx.response.code.int
  echo "Headers:"
  for k, v in ctx.response.headers:
    echo "  " & k & ": " & v
  echo "Body:"
  echo ctx.response.body
  echo "================"
