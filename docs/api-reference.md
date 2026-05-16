# API Reference

Complete reference for all NimMax public types, procedures, and modules.

## Table of Contents

- [Core Types](#core-types)
- [Application](#application)
- [Context](#context)
- [Request](#request)
- [Response](#response)
- [Router & Routing](#router--routing)
- [Middleware](#middleware)
- [Groups](#groups)
- [Settings](#settings)
- [Sessions](#sessions)
- [Forms](#forms)
- [Exceptions](#exceptions)

---

## Core Types

### HandlerAsync

```nim
HandlerAsync* = proc(ctx: Context): Future[void] {.closure, gcsafe.}
```

The fundamental handler type. All route handlers and middleware are `HandlerAsync` procs.

### Context

```nim
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
```

Central object passed to every handler and middleware.

### Request

```nim
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
```

### Response

```nim
Response* = ref object
  httpVersion*: HttpVersion
  code*: HttpCode
  headers*: HttpHeaders
  body*: string
```

### Settings

```nim
Settings* = ref object
  address*: string
  port*: Port
  debug*: bool
  reusePort*: bool
  secretKey*: SecretKey
  appName*: string
  bufSize*: int
  data*: JsonNode
```

### Session

```nim
Session* = ref object
  data*: TableRef[string, string]
  newCreated*: bool
  modified*: bool
  accessed*: bool
```

### FlashLevel

```nim
FlashLevel* = enum
  flInfo = "info"
  flWarning = "warning"
  flError = "error"
  flSuccess = "success"
```

### SecretKey

```nim
SecretKey* = distinct string
```

---

## Application

### newApp

```nim
proc newApp*(
  settings: Settings = newSettings(),
  middlewares: seq[HandlerAsync] = @[],
  startup: seq[AppEvent] = @[],
  shutdown: seq[AppEvent] = @[],
  errorHandlerTable: Table[HttpCode, ErrorHandler] = newErrorHandlerTable()
): Application
```

Create a new application instance.

### Route Registration

```nim
proc get*(app: Application, path: string, handler: HandlerAsync,
          middlewares: seq[HandlerAsync] = @[], name = "")
proc post*(app: Application, path: string, handler: HandlerAsync,
           middlewares: seq[HandlerAsync] = @[], name = "")
proc put*(app: Application, path: string, handler: HandlerAsync,
          middlewares: seq[HandlerAsync] = @[], name = "")
proc delete*(app: Application, path: string, handler: HandlerAsync,
             middlewares: seq[HandlerAsync] = @[], name = "")
proc patch*(app: Application, path: string, handler: HandlerAsync,
            middlewares: seq[HandlerAsync] = @[], name = "")
proc head*(app: Application, path: string, handler: HandlerAsync,
           middlewares: seq[HandlerAsync] = @[], name = "")
proc options*(app: Application, path: string, handler: HandlerAsync,
              middlewares: seq[HandlerAsync] = @[], name = "")
proc all*(app: Application, path: string, handler: HandlerAsync,
          middlewares: seq[HandlerAsync] = @[], name = "")
proc addRoute*(app: Application, httpMethod: HttpMethod, pattern: string,
               handler: HandlerAsync, middlewares: seq[HandlerAsync] = @[],
               name = "")
```

### Middleware

```nim
proc use*(app: Application, middlewares: varargs[HandlerAsync])
```

### Error Handling

```nim
proc registerErrorHandler*(app: Application, code: HttpCode, handler: ErrorHandler)
proc registerErrorHandler*(app: Application, codes: set[HttpCode], handler: ErrorHandler)
```

### Lifecycle Events

```nim
proc onStart*(app: Application, handler: Event)
proc onStartAsync*(app: Application, handler: AppAsyncEvent)
proc onStop*(app: Application, handler: Event)
proc onStopAsync*(app: Application, handler: AppAsyncEvent)
```

### Application Data

```nim
proc `[]`*(app: Application, key: string): JsonNode
proc `[]=`*(app: Application, key: string, value: JsonNode)
```

### Run

```nim
proc run*(app: Application, address = "", port: Port = Port(0), debug = true)
proc serve*(app: Application)
```

---

## Context

### Parameter Access

```nim
proc getPathParam*(ctx: Context, key: string): string
proc getQueryParam*(ctx: Context, key: string): string
proc getPostParam*(ctx: Context, key: string): string
proc getInt*(ctx: Context, key: string, source = "path"): Option[int]
proc getFloat*(ctx: Context, key: string, source = "path"): Option[float]
proc getBool*(ctx: Context, key: string, source = "query"): Option[bool]

### Unified Parameter Access (v1.1+)

```nim
proc getParam*(ctx: Context, key: string): string
  ## Tries path → query → post params in order, returns first match.

proc getParamInt*(ctx: Context, key: string): Option[int]
  ## Tries path → query → post params, returns Option[int].

proc getParamFloat*(ctx: Context, key: string): Option[float]
  ## Tries path → query → post params, returns Option[float].

proc getParamBool*(ctx: Context, key: string): Option[bool]
  ## Tries path → query → post params, returns Option[bool].
```
```

### Response Helpers

```nim
proc html*(ctx: Context, body: string, code = Http200)
proc json*(ctx: Context, data: JsonNode, code = Http200)
proc json*(ctx: Context, data: string, code = Http200)
proc text*(ctx: Context, body: string, code = Http200)
proc redirect*(ctx: Context, url: string, code = Http301)
proc temporaryRedirect*(ctx: Context, url: string)
proc seeOther*(ctx: Context, url: string)
proc abortRequest*(ctx: Context, code: HttpCode, body = "")
proc send*(ctx: Context, body: string, code = Http200, contentType = "text/html; charset=utf-8")
proc respond*(ctx: Context, body: string, code = Http200, headers: HttpHeaders = nil)
proc setResponse*(ctx: Context, resp: Response)

### Jester-Compatible resp (v1.1+)

```nim
proc resp*(ctx: Context, body: string, code = Http200, contentType = "")
  ## Jester-compatible: resp(body), resp(body, code), resp(body, code, contentType)

proc resp*(ctx: Context, code: HttpCode, body: string, contentType = "")
  ## Jester-compatible: resp(code, body), resp(code, body, contentType)
```

### Control Flow Helpers (v1.1+)

```nim
proc cond*(ctx: Context, condition: bool)
  ## Aborts with Http400 if condition is false.

proc halt*(ctx: Context, code = Http404, body = "")
  ## Stops request processing with given status code.
```

### Cookies

```nim
proc getCookie*(ctx: Context, name: string): string
proc setCookie*(ctx: Context, name, value: string, path = "/",
                domain = "", maxAge = 0, httpOnly = false,
                secure = false, sameSite = "Lax")
proc setCookieEnum*(ctx: Context, name, value: string, path = "/",
                domain = "", maxAge = 0, httpOnly = false,
                secure = false, sameSite: cookies.SameSite = cookies.SameSite.Lax)
  ## Type-safe overload using stdlib SameSite enum (v1.1+).
proc deleteCookie*(ctx: Context, name: string, path = "/")
```

### Flash Messages

```nim
proc flash*(ctx: Context, msg: string, category = flInfo)
proc getFlashedMsgs*(ctx: Context): seq[string]
proc getFlashedMsgsWithCategory*(ctx: Context): seq[(FlashLevel, string)]
```

### URL Building

```nim
proc urlFor*(ctx: Context, name: string, params: seq[(string, string)] = @[]): string

### URL Building & Client Info (v1.1+)

```nim
proc makeUri*(ctx: Context, address = "", absolute = true): string
  ## Builds a URL relative to the current request's scheme/host.
  ## Respects X-Forwarded-Proto for reverse proxy setups.

proc clientIP*(ctx: Context): string
  ## Returns client IP, respecting X-Forwarded-For and X-Real-IP headers.
```

### Static Files

```nim
proc staticFileResponse*(ctx: Context, filePath: string, downloadName = "")
```

### Settings

```nim
proc getSettings*(ctx: Context): Settings
```

### Context Data

```nim
proc `[]`*(ctx: Context, key: string): JsonNode
proc `[]=`*(ctx: Context, key: string, value: JsonNode)
```

---

## Request

### Helper Procedures

```nim
proc path*(req: Request): string
proc query*(req: Request): string
proc scheme*(req: Request): string
proc hostName*(req: Request): string
proc contentType*(req: Request): string
proc userAgent*(req: Request): string
proc reqMethod*(req: Request): HttpMethod
proc secure*(req: Request): bool
```

### Typed Parameter Access

```nim
proc getPathParam*(req: Request, key: string): string
proc getPathParamInt*(req: Request, key: string): Option[int]
proc getPathParamFloat*(req: Request, key: string): Option[float]
proc getQueryParam*(req: Request, key: string): string
proc getQueryParamInt*(req: Request, key: string): Option[int]
proc getQueryParamFloat*(req: Request, key: string): Option[float]
proc getQueryParamBool*(req: Request, key: string): Option[bool]
proc getPostParam*(req: Request, key: string): string
proc getCookie*(req: Request, name: string): string
proc hasCookie*(req: Request, name: string): bool
```

### Bracket Access

```nim
proc `[]`*(req: Request, key: string): string
# Tries path → query → post params
```

---

## Response

### Constructors

```nim
proc newResponse*(code = Http200, body = "", headers: HttpHeaders = nil): Response
proc htmlResponse*(body: string, code = Http200): Response
proc plainTextResponse*(body: string, code = Http200): Response
proc jsonResponse*(data: JsonNode, code = Http200): Response
proc jsonResponse*(data: string, code = Http200): Response
proc redirect*(url: string, code = Http301): Response
proc temporaryRedirect*(url: string): Response
proc seeOther*(url: string): Response
proc abort*(code: HttpCode, body = ""): Response
proc errorPage*(code: HttpCode, title, message: string): Response
```

### Methods

```nim
proc setHeader*(resp: Response, key, value: string): Response {.discardable.}
proc setCookie*(resp: Response, name, value: string, path = "/",
                domain = "", maxAge = 0, httpOnly = false,
                secure = false, sameSite = "Lax"): Response {.discardable.}

proc setCookieEnum*(resp: Response, name, value: string, path = "/",
                domain = "", maxAge = 0, httpOnly = false,
                secure = false, sameSite: cookies.SameSite = cookies.SameSite.Lax): Response {.discardable.}
  ## Type-safe overload using stdlib SameSite enum (v1.1+).
```

---

## Router & Routing

### Route Patterns

- `/hello` — literal match
- `/user/{id}` — named parameter
- `/files/*` — wildcard

### RouteEntry

```nim
RouteEntry* = object
  pattern*: string
  parts*: seq[RoutePart]
  handler*: HandlerAsync
  middlewares*: seq[HandlerAsync]
  name*: string
  httpMethod*: HttpMethod
```

### MatchResult

```nim
MatchResult* = object
  matched*: bool
  pathParams*: seq[PathParam]
  handler*: HandlerAsync
  middlewares*: seq[HandlerAsync]
  routeName*: string
```

---

## Middleware

### Built-in Middleware

```nim
proc loggingMiddleware*(appName = "NimMax"): HandlerAsync
proc debugRequestMiddleware*(appName = "NimMax"): HandlerAsync
proc debugResponseMiddleware*(appName = "NimMax"): HandlerAsync
proc stripPathMiddleware*(): HandlerAsync
proc httpRedirectMiddleware*(fromPath, toPath: string): HandlerAsync
proc corsMiddleware*(...): HandlerAsync
proc csrfMiddleware*(...): HandlerAsync
proc basicAuthMiddleware*(...): HandlerAsync
proc staticFileMiddleware*(dirs: varargs[string]): HandlerAsync
proc sessionMiddleware*(...): HandlerAsync
proc formBodyMiddleware*(): HandlerAsync
  ## Auto-parses application/x-www-form-urlencoded and multipart/form-data (v1.1+).
proc compressionMiddleware*(minSize = 1024, level = clDefault, excludePaths: seq[string] = @[]): HandlerAsync
  ## gzip/deflate compression via zippy (optional, disable with -d:nimmaxNoZippy).
proc rateLimitMiddleware*(...): HandlerAsync
proc requestIdMiddleware*(...): HandlerAsync
proc jsonBodyMiddleware*(): HandlerAsync
proc securityHeadersMiddleware*(...): HandlerAsync
```

### Composition

```nim
proc compose*(middlewares: openArray[HandlerAsync]): HandlerAsync
proc chain*(before, after: HandlerAsync): HandlerAsync
proc switch*(ctx: Context): Future[void]
```

---

## Groups

```nim
proc newGroup*(app: Application, route: string,
               middlewares: seq[HandlerAsync] = @[]): Group
proc get*(group: Group, path: string, handler: HandlerAsync, ...)
proc post*(group: Group, path: string, handler: HandlerAsync, ...)
proc put*(group: Group, path: string, handler: HandlerAsync, ...)
proc delete*(group: Group, path: string, handler: HandlerAsync, ...)
proc patch*(group: Group, path: string, handler: HandlerAsync, ...)
proc all*(group: Group, path: string, handler: HandlerAsync, ...)
```

---

## Settings

```nim
proc newSettings*(...): Settings
proc loadSettings*(data: JsonNode): Settings
proc loadSettings*(configPath: string): Settings
proc `[]`*(settings: Settings, key: string): JsonNode
proc getStr*(settings: Settings, key: string, default = ""): string
proc getInt*(settings: Settings, key: string, default = 0): int
proc getBool*(settings: Settings, key: string, default = false): bool
```

---

## Sessions

```nim
proc `[]`*(session: Session, key: string): string
proc `[]=`*(session: Session, key, value: string)
proc del*(session: Session, key: string)
proc clear*(session: Session)
proc hasKey*(session: Session, key: string): bool
proc len*(session: Session): int
proc pairs*(session: Session): seq[(string, string)]
```

---

## Forms

```nim
proc parseFormParams*(body: string, contentType: string): FormPart
proc getFormValue*(form: FormPart, key: string): string
proc getFormValues*(form: FormPart, key: string): seq[string]
proc getFormFile*(form: FormPart, key: string): FormFile
proc getFormFiles*(form: FormPart, key: string): seq[FormFile]
proc hasFormField*(form: FormPart, key: string): bool
proc hasFormFile*(form: FormPart, key: string): bool
```

---

## Exceptions

```nim
NimMaxError*        # base exception
HttpError*          # HTTP-related errors
AbortError*         # raised by abortRequest (has code field)
RouteError*         # routing errors
RouteNotFoundError* # route not found
DuplicatedRouteError* # duplicate route name
MiddlewareError*    # middleware errors
SessionError*       # session errors
ValidationError*    # validation errors (has errors: seq[string])
ConfigError*        # configuration errors
SecurityError*      # security errors
FormParseError*     # form parsing errors
```
