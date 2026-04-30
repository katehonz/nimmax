import std/[strutils, tables, options, httpcore]
import algorithm
import ./types, ./exceptions

proc parsePattern*(pattern: string): seq[RoutePart] =
  result = @[]
  if pattern.len == 0 or pattern == "/":
    return

  let cleanPattern = if pattern.startsWith('/'): pattern[1 .. ^1] else: pattern
  let segments = cleanPattern.split('/')

  for segment in segments:
    if segment.len == 0:
      continue
    if segment == "*":
      result.add(RoutePart(kind: rpkWildcard))
    elif segment.startsWith('{') and segment.endsWith('}'):
      let paramName = segment[1 .. ^2]
      if paramName.endsWith('$'):
        result.add(RoutePart(kind: rpkWildcard))
      else:
        result.add(RoutePart(kind: rpkParam, paramName: paramName))
    else:
      result.add(RoutePart(kind: rpkLiteral, literal: segment))

proc routeSpecificity*(parts: seq[RoutePart]): int =
  result = 0
  for part in parts:
    case part.kind
    of rpkLiteral:
      result += 100
    of rpkParam:
      result += 50
    of rpkWildcard:
      result += 1

proc matchPath*(parts: seq[RoutePart], path: string): tuple[matched: bool, params: seq[PathParam]] =
  result.matched = false
  result.params = @[]

  let cleanPath = if path.startsWith('/'): path[1 .. ^1] else: path
  var segments: seq[string] = @[]
  for s in cleanPath.split('/'):
    if s.len > 0:
      segments.add(s)

  var partIdx = 0
  var segIdx = 0

  while partIdx < parts.len and segIdx < segments.len:
    let part = parts[partIdx]
    case part.kind
    of rpkLiteral:
      if segments[segIdx] != part.literal:
        return
      inc partIdx
      inc segIdx
    of rpkParam:
      result.params.add(PathParam(name: part.paramName, value: segments[segIdx]))
      inc partIdx
      inc segIdx
    of rpkWildcard:
      if partIdx == parts.len - 1:
        var rest = segments[segIdx .. ^1].join("/")
        if cleanPath.endsWith('/') and rest.len > 0:
          rest &= "/"
        result.params.add(PathParam(name: "*", value: rest))
        result.matched = true
        return
      else:
        result.params.add(PathParam(name: "*", value: segments[segIdx]))
        inc partIdx
        inc segIdx

  if partIdx == parts.len and segIdx == segments.len:
    result.matched = true
  elif partIdx == parts.len - 1 and parts[partIdx].kind == rpkWildcard:
    result.params.add(PathParam(name: "*", value: ""))
    result.matched = true

proc newRouter*(): Router =
  Router(
    routes: initTable[string, seq[RouteEntry]](),
    namedRoutes: initTable[string, RouteEntry]()
  )

proc addRoute*(router: Router, httpMethod: HttpMethod, pattern: string,
               handler: HandlerAsync, middlewares: seq[HandlerAsync] = @[],
               name = "") =
  let parts = parsePattern(pattern)
  let methodKey = $httpMethod
  let specificity = routeSpecificity(parts)

  if not router.routes.hasKey(methodKey):
    router.routes[methodKey] = @[]

  let entry = RouteEntry(
    pattern: pattern,
    parts: parts,
    handler: handler,
    middlewares: middlewares,
    name: name,
    httpMethod: httpMethod,
    specificity: specificity
  )

  router.routes[methodKey].add(entry)

  if name.len > 0:
    if router.namedRoutes.hasKey(name):
      raise newDuplicatedRouteError("Duplicate route name: " & name)
    router.namedRoutes[name] = entry

proc findRoute*(router: Router, httpMethod: HttpMethod, path: string): Option[RouteEntry] =
  let methodKey = $httpMethod

  if not router.routes.hasKey(methodKey):
    return none(RouteEntry)

  for entry in router.routes[methodKey]:
    let (matched, _) = matchPath(entry.parts, path)
    if matched:
      return some(entry)

  return none(RouteEntry)

proc matchRoute*(router: Router, httpMethod: HttpMethod, path: string): MatchResult =
  result.matched = false

  let methodKey = $httpMethod
  if router.routes.hasKey(methodKey):
    var routes = router.routes[methodKey]
    sort(routes, proc(a, b: RouteEntry): int = cmp(a.specificity, b.specificity), Descending)
    for entry in routes:
      let (matched, params) = matchPath(entry.parts, path)
      if matched:
        result.matched = true
        result.pathParams = params
        result.handler = entry.handler
        result.middlewares = entry.middlewares
        result.routeName = entry.name
        return

  let allMethods = @["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
  for m in allMethods:
    if m == methodKey:
      continue
    if router.routes.hasKey(m):
      var routes = router.routes[m]
      sort(routes, proc(a, b: RouteEntry): int = cmp(a.specificity, b.specificity), Descending)
      for entry in routes:
        let (matched, _) = matchPath(entry.parts, path)
        if matched:
          result.matched = false
          return

proc buildUrl*(router: Router, name: string, params: seq[(string, string)] = @[]): string =
  if not router.namedRoutes.hasKey(name):
    raise newRouteNotFoundError("Named route not found: " & name)

  let entry = router.namedRoutes[name]
  result = ""
  var paramTable = initTable[string, string]()
  for (k, v) in params:
    paramTable[k] = v

  for part in entry.parts:
    result.add("/")
    case part.kind
    of rpkLiteral:
      result.add(part.literal)
    of rpkParam:
      if paramTable.hasKey(part.paramName):
        result.add(paramTable[part.paramName])
      else:
        result.add("{" & part.paramName & "}")
    of rpkWildcard:
      if paramTable.hasKey("*"):
        result.add(paramTable["*"])

  if result.len == 0:
    result = "/"
