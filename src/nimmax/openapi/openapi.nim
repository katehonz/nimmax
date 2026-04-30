import std/[json, tables, strutils, httpcore]
import ../core/types, ../core/context, ../core/application

type
  OpenApiInfo* = object
    title*: string
    description*: string
    version*: string

  OpenApiPath* = object
    path*: string
    method*: string
    summary*: string
    tags*: seq[string]

  OpenApiSpec* = ref object
    info*: OpenApiInfo
    paths*: seq[OpenApiPath]

proc newOpenApiSpec*(title = "NimMax API", description = "", version = "1.0.0"): OpenApiSpec =
  OpenApiSpec(
    info: OpenApiInfo(title: title, description: description, version: version),
    paths: @[]
  )

proc addPath*(spec: OpenApiSpec, path, method, summary: string, tags: seq[string] = @[]) =
  spec.paths.add(OpenApiPath(path: path, method: method.toLowerAscii(), summary: summary, tags: tags))

proc toJson*(spec: OpenApiSpec): JsonNode =
  var paths = newJObject()
  for p in spec.paths:
    if not paths.hasKey(p.path):
      paths[p.path] = newJObject()
    var operation = newJObject()
    operation["summary"] = %p.summary
    if p.tags.len > 0:
      var tagsArr = newJArray()
      for t in p.tags:
        tagsArr.add(%t)
      operation["tags"] = tagsArr
    operation["responses"] = %*{"200": {"description": "Successful response"}}
    paths[p.path][p.method] = operation

  result = %*{
    "openapi": "3.0.0",
    "info": {
      "title": spec.info.title,
      "description": spec.info.description,
      "version": spec.info.version
    },
    "paths": paths
  }

proc serveDocs*(app: Application, spec: OpenApiSpec, path = "/docs",
                openApiPath = "/openapi.json", onlyDebug = true) =
  app.get(openApiPath, proc(ctx: Context): Future[void] {.async, gcsafe.} =
    if onlyDebug and not ctx.getSettings().debug:
      ctx.abortRequest(Http404)
      return
    ctx.json(spec.toJson())
  )

  app.get(path, proc(ctx: Context): Future[void] {.async, gcsafe.} =
    if onlyDebug and not ctx.getSettings().debug:
      ctx.abortRequest(Http404)
      return
    let body = """<!DOCTYPE html>
<html>
<head>
  <title>""" & spec.info.title & """ - API Documentation</title>
  <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    SwaggerUIBundle({url: '""" & openApiPath & """', dom_id: '#swagger-ui'})
  </script>
</body>
</html>"""
    ctx.html(body)
  )
