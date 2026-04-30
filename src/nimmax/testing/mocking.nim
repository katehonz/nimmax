import std/[asyncdispatch, httpcore, tables, json, uri]
import ../core/types, ../core/request, ../core/response, ../core/context, ../core/application, ../core/settings

proc mockRequest*(
  httpMethod = HttpGet,
  path = "/",
  headers: HttpHeaders = nil,
  body = "",
  queryParams: TableRef[string, string] = nil,
  postParams: TableRef[string, string] = nil
): Request =
  let url = parseUri(path)
  let h = if headers.isNil: newHttpHeaders() else: headers
  let qp = if queryParams.isNil: newTable[string, string]() else: queryParams
  let pp = if postParams.isNil: newTable[string, string]() else: postParams

  Request(
    nativeRequest: nil,
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

proc runOnce*(app: Application, httpMethod = HttpGet, path = "/",
              headers: HttpHeaders = nil, body = ""): Context =
  let ctx = mockContext(httpMethod, path, headers, body, app.gScope.settings)
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
