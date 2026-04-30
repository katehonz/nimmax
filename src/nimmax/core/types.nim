import std/[asynchttpserver, asyncdispatch, uri, tables, strutils, options, json, times, httpcore]

export asyncdispatch, uri, tables, strutils, options, json, times, httpcore

type
  NativeRequest* = asynchttpserver.Request

  Context* = ref object of RootObj
    request*: Request
    response*: Response
    handled*: bool
    session*: Session
    ctxData*: TableRef[string, JsonNode]
    gScope*: GlobalScope
    middlewares*: seq[HandlerAsync]
    middlewareIdx*: int
    first*: bool

  HandlerAsync* = proc(ctx: Context): Future[void] {.closure, gcsafe.}

  ErrorHandler* = proc(ctx: Context): Future[void] {.closure, gcsafe.}

  Event* = proc() {.gcsafe.}
  AppAsyncEvent* = proc(): Future[void] {.gcsafe.}

  AppEvent* = object
    case async*: bool
    of true:
      asyncHandler*: AppAsyncEvent
    of false:
      syncHandler*: Event

  SecretKey* = distinct string

  FlashLevel* = enum
    flInfo = "info"
    flWarning = "warning"
    flError = "error"
    flSuccess = "success"

  Session* = ref object
    data*: TableRef[string, string]
    newCreated*: bool
    modified*: bool
    accessed*: bool

  FormPart* = object
    data*: TableRef[string, seq[string]]
    files*: TableRef[string, seq[FormFile]]

  FormFile* = object
    filename*: string
    contentType*: string
    body*: string

  Request* = ref object
    nativeRequest*: NativeRequest
    httpMethod*: HttpMethod
    url*: Uri
    headers*: HttpHeaders
    body*: string
    cookies*: TableRef[string, string]
    queryParams*: TableRef[string, string]
    postParams*: TableRef[string, string]
    pathParams*: TableRef[string, string]
    formParams*: FormPart

  Response* = ref object
    httpVersion*: HttpVersion
    code*: HttpCode
    headers*: HttpHeaders
    body*: string

  RoutePartKind* = enum
    rpkLiteral, rpkParam, rpkWildcard

  RoutePart* = object
    case kind*: RoutePartKind
    of rpkLiteral:
      literal*: string
    of rpkParam:
      paramName*: string
    of rpkWildcard:
      discard

  RouteEntry* = object
    pattern*: string
    parts*: seq[RoutePart]
    handler*: HandlerAsync
    middlewares*: seq[HandlerAsync]
    name*: string
    httpMethod*: HttpMethod
    specificity*: int

  PathParam* = object
    name*: string
    value*: string

  MatchResult* = object
    matched*: bool
    pathParams*: seq[PathParam]
    handler*: HandlerAsync
    middlewares*: seq[HandlerAsync]
    routeName*: string

  Router* = ref object
    routes*: Table[string, seq[RouteEntry]]
    namedRoutes*: Table[string, RouteEntry]

  Settings* = ref object
    address*: string
    port*: Port
    debug*: bool
    reusePort*: bool
    secretKey*: SecretKey
    appName*: string
    bufSize*: int
    shutdownTimeout*: int
    data*: JsonNode

  GlobalScope* = ref object
    router*: Router
    settings*: Settings
    appData*: TableRef[string, JsonNode]

  Application* = ref object
    gScope*: GlobalScope
    globalMiddlewares*: seq[HandlerAsync]
    startupEvents*: seq[AppEvent]
    shutdownEvents*: seq[AppEvent]
    errorHandlerTable*: Table[HttpCode, ErrorHandler]

  Group* = ref object
    app*: Application
    parent*: Group
    route*: string
    middlewares*: seq[HandlerAsync]

proc len*(s: SecretKey): int {.borrow.}
