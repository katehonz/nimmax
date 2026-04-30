import std/[httpcore, strutils]

type
  NimMaxError* = object of CatchableError
  HttpError* = object of NimMaxError
  AbortError* = object of HttpError
    code*: HttpCode
  RouteError* = object of NimMaxError
  RouteNotFoundError* = object of RouteError
  DuplicatedRouteError* = object of RouteError
  MiddlewareError* = object of NimMaxError
  SessionError* = object of NimMaxError
  ValidationError* = object of NimMaxError
    errors*: seq[string]
  ConfigError* = object of NimMaxError
  SecurityError* = object of NimMaxError
  FormParseError* = object of NimMaxError

proc newAbortError*(code: HttpCode, msg = ""): ref AbortError =
  result = newException(AbortError, msg)
  result.code = code

proc newRouteNotFoundError*(msg = "Route not found"): ref RouteNotFoundError =
  newException(RouteNotFoundError, msg)

proc newDuplicatedRouteError*(msg: string): ref DuplicatedRouteError =
  newException(DuplicatedRouteError, msg)

proc newValidationError*(errors: seq[string]): ref ValidationError =
  result = newException(ValidationError, errors.join(", "))
  result.errors = errors

proc newConfigError*(msg: string): ref ConfigError =
  newException(ConfigError, msg)

proc newSecurityError*(msg: string): ref SecurityError =
  newException(SecurityError, msg)

proc newFormParseError*(msg: string): ref FormParseError =
  newException(FormParseError, msg)
