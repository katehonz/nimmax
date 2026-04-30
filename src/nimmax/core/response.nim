import std/[json]
import ./types, ./utils

proc newResponse*(code = Http200, body = "", headers: HttpHeaders = nil): Response =
  result = Response(
    httpVersion: HttpVer11,
    code: code,
    headers: if headers.isNil: newHttpHeaders() else: headers,
    body: body
  )

proc htmlResponse*(body: string, code = Http200): Response =
  result = newResponse(code, body)
  result.headers["Content-Type"] = "text/html; charset=utf-8"

proc plainTextResponse*(body: string, code = Http200): Response =
  result = newResponse(code, body)
  result.headers["Content-Type"] = "text/plain; charset=utf-8"

proc jsonResponse*(data: JsonNode, code = Http200): Response =
  result = newResponse(code, $data)
  result.headers["Content-Type"] = "application/json; charset=utf-8"

proc jsonResponse*(data: string, code = Http200): Response =
  result = newResponse(code, data)
  result.headers["Content-Type"] = "application/json; charset=utf-8"

proc redirect*(url: string, code = Http301): Response =
  result = newResponse(code, "")
  result.headers["Location"] = url

proc temporaryRedirect*(url: string): Response =
  redirect(url, Http302)

proc seeOther*(url: string): Response =
  redirect(url, Http303)

proc abort*(code: HttpCode, body = ""): Response =
  newResponse(code, body)

proc errorPage*(code: HttpCode, title, message: string): Response =
  let body = """<!DOCTYPE html>
<html>
<head><title>""" & $code.int & " " & title & """</title>
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
  <h1 class="error-code">""" & $code.int & """</h1>
  <h2 class="error-title">""" & escapeHtml(title) & """</h2>
  <p class="error-message">""" & escapeHtml(message) & """</p>
</div>
</body>
</html>"""
  result = newResponse(code, body)
  result.headers["Content-Type"] = "text/html; charset=utf-8"

proc setHeader*(resp: Response, key, value: string): Response {.discardable.} =
  resp.headers[key] = value
  result = resp

proc setCookie*(resp: Response, name, value: string, path = "/",
                domain = "", maxAge = 0, httpOnly = false,
                secure = false, sameSite = "Lax"): Response {.discardable.} =
  var cookie = name & "=" & value & "; Path=" & path
  if domain.len > 0:
    cookie &= "; Domain=" & domain
  if maxAge > 0:
    cookie &= "; Max-Age=" & $maxAge
  if httpOnly:
    cookie &= "; HttpOnly"
  if secure:
    cookie &= "; Secure"
  if sameSite.len > 0:
    cookie &= "; SameSite=" & sameSite
  resp.headers.add("Set-Cookie", cookie)
  result = resp
