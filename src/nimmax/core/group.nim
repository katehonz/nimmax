import std/[httpcore]
import ./types, ./route

proc newGroup*(app: Application, route: string,
               middlewares: seq[HandlerAsync] = @[],
               parent: Group = nil): Group =
  Group(
    app: app,
    parent: parent,
    route: route,
    middlewares: middlewares
  )

proc buildFullPath*(group: Group, path: string): string =
  result = group.route
  if path.len > 0:
    if not path.startsWith('/'):
      result.add("/")
    result.add(path)

  if group.parent != nil:
    result = group.parent.buildFullPath(result)

proc buildMiddlewares*(group: Group, middlewares: seq[HandlerAsync]): seq[HandlerAsync] =
  result = @[]
  if group.parent != nil:
    result.add(group.parent.buildMiddlewares(@[]))
  result.add(group.middlewares)
  result.add(middlewares)

proc addRoute*(group: Group, httpMethod: HttpMethod, path: string,
               handler: HandlerAsync, middlewares: seq[HandlerAsync] = @[],
               name = "") =
  let fullPath = group.buildFullPath(path)
  let allMiddlewares = group.buildMiddlewares(middlewares)
  group.app.gScope.router.addRoute(httpMethod, fullPath, handler, allMiddlewares, name)

proc get*(group: Group, path: string, handler: HandlerAsync,
          middlewares: seq[HandlerAsync] = @[], name = "") =
  group.addRoute(HttpGet, path, handler, middlewares, name)

proc post*(group: Group, path: string, handler: HandlerAsync,
           middlewares: seq[HandlerAsync] = @[], name = "") =
  group.addRoute(HttpPost, path, handler, middlewares, name)

proc put*(group: Group, path: string, handler: HandlerAsync,
          middlewares: seq[HandlerAsync] = @[], name = "") =
  group.addRoute(HttpPut, path, handler, middlewares, name)

proc delete*(group: Group, path: string, handler: HandlerAsync,
             middlewares: seq[HandlerAsync] = @[], name = "") =
  group.addRoute(HttpDelete, path, handler, middlewares, name)

proc patch*(group: Group, path: string, handler: HandlerAsync,
            middlewares: seq[HandlerAsync] = @[], name = "") =
  group.addRoute(HttpPatch, path, handler, middlewares, name)

proc head*(group: Group, path: string, handler: HandlerAsync,
           middlewares: seq[HandlerAsync] = @[], name = "") =
  group.addRoute(HttpHead, path, handler, middlewares, name)

proc options*(group: Group, path: string, handler: HandlerAsync,
              middlewares: seq[HandlerAsync] = @[], name = "") =
  group.addRoute(HttpOptions, path, handler, middlewares, name)

proc all*(group: Group, path: string, handler: HandlerAsync,
          middlewares: seq[HandlerAsync] = @[], name = "") =
  group.get(path, handler, middlewares, name & "_get")
  group.post(path, handler, middlewares, name & "_post")
  group.put(path, handler, middlewares, name & "_put")
  group.delete(path, handler, middlewares, name & "_delete")
  group.patch(path, handler, middlewares, name & "_patch")
  group.head(path, handler, middlewares, name & "_head")
  group.options(path, handler, middlewares, name & "_options")
