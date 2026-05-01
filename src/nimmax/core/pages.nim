import std/[httpcore]
import ./types, ./utils

proc default404Page*(ctx: Context): Future[void] {.async, gcsafe.} =
  let body = """<!DOCTYPE html>
<html>
<head><title>404 Not Found</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
         display: flex; justify-content: center; align-items: center; min-height: 100vh;
         margin: 0; background: #f5f5f5; color: #333; }
  .error-container { text-align: center; padding: 40px; }
  .error-code { font-size: 120px; font-weight: 700; color: #3498db; margin: 0; }
  .error-title { font-size: 24px; margin: 10px 0; color: #555; }
  .error-message { font-size: 16px; color: #777; }
</style>
</head>
<body>
<div class="error-container">
  <h1 class="error-code">404</h1>
  <h2 class="error-title">Page Not Found</h2>
  <p class="error-message">The requested URL was not found on this server.</p>
</div>
</body>
</html>"""
  ctx.response.code = Http404
  ctx.response.body = body
  ctx.response.headers["Content-Type"] = "text/html; charset=utf-8"

proc default500Page*(ctx: Context): Future[void] {.async, gcsafe.} =
  let msg = if ctx.response.body.len > 0: ctx.response.body else: "Internal Server Error"
  let body = """<!DOCTYPE html>
<html>
<head><title>500 Internal Server Error</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
         display: flex; justify-content: center; align-items: center; min-height: 100vh;
         margin: 0; background: #f5f5f5; color: #333; }
  .error-container { text-align: center; padding: 40px; }
  .error-code { font-size: 120px; font-weight: 700; color: #e74c3c; margin: 0; }
  .error-title { font-size: 24px; margin: 10px 0; color: #555; }
  .error-message { font-size: 16px; color: #777; }
</style>
</head>
<body>
<div class="error-container">
  <h1 class="error-code">500</h1>
  <h2 class="error-title">Internal Server Error</h2>
  <p class="error-message">""" & escapeHtmlContent(msg) & """</p>
</div>
</body>
</html>"""
  ctx.response.code = Http500
  ctx.response.body = body
  ctx.response.headers["Content-Type"] = "text/html; charset=utf-8"

proc default403Page*(ctx: Context): Future[void] {.async, gcsafe.} =
  let body = """<!DOCTYPE html>
<html>
<head><title>403 Forbidden</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
         display: flex; justify-content: center; align-items: center; min-height: 100vh;
         margin: 0; background: #f5f5f5; color: #333; }
  .error-container { text-align: center; padding: 40px; }
  .error-code { font-size: 120px; font-weight: 700; color: #e67e22; margin: 0; }
  .error-title { font-size: 24px; margin: 10px 0; color: #555; }
  .error-message { font-size: 16px; color: #777; }
</style>
</head>
<body>
<div class="error-container">
  <h1 class="error-code">403</h1>
  <h2 class="error-title">Forbidden</h2>
  <p class="error-message">You don't have permission to access this resource.</p>
</div>
</body>
</html>"""
  ctx.response.code = Http403
  ctx.response.body = body
  ctx.response.headers["Content-Type"] = "text/html; charset=utf-8"

proc newErrorHandlerTable*(): Table[HttpCode, ErrorHandler] =
  result = initTable[HttpCode, ErrorHandler]()
  result[Http404] = default404Page
  result[Http500] = default500Page
