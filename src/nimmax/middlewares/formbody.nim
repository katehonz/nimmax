import std/[asyncdispatch, tables, strutils]
import ../core/types, ../core/context, ../core/middleware, ../core/utils, ../core/form

proc formBodyMiddleware*(): HandlerAsync =
  ## Middleware that automatically parses application/x-www-form-urlencoded
  ## and multipart/form-data POST bodies into ctx.request.postParams.
  ##
  ## This solves Deficiency #8: POST Body Params Not Auto-Parsed.
  ## Without this middleware, POST params are only populated if you manually
  ## call parseFormParams().
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let httpMethod = ctx.request.reqMethod()
    if httpMethod == HttpPost or httpMethod == HttpPut or httpMethod == HttpPatch:
      let contentType = ctx.request.headers.getHeader("Content-Type", "")
      let body = ctx.request.body
      if body.len > 0:
        if "application/x-www-form-urlencoded" in contentType:
          let formPart = parseFormParams(body, contentType)
          for key, values in formPart.data:
            if values.len > 0:
              ctx.request.postParams[key] = values[0]
          ctx.request.formParams = formPart
        elif "multipart/form-data" in contentType:
          let formPart = parseFormParams(body, contentType)
          for key, values in formPart.data:
            if values.len > 0:
              ctx.request.postParams[key] = values[0]
          ctx.request.formParams = formPart
    await switch(ctx)
