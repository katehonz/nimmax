import std/[asyncdispatch, strutils, httpcore, random]
import ../core/types, ../core/middleware, ../core/context, ../core/utils, ../core/constants

proc generateCsrfToken*(): string =
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  result = newString(64)
  for i in 0 ..< 64:
    result[i] = chars[rand(chars.len - 1)]

proc csrfMiddleware*(tokenName = csrfTokenName, cookieName = csrfCookieName): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    if ctx.request.httpMethod in {HttpPost, HttpPut, HttpDelete, HttpPatch}:
      let cookieToken = ctx.getCookie(cookieName)
      let formToken = ctx.getPostParam(tokenName)
      let headerToken = ctx.request.headers.getHeader("X-CSRF-Token", "")

      let token = if formToken.len > 0: formToken
                  elif headerToken.len > 0: headerToken
                  else: ""

      if token.len == 0 or cookieToken.len == 0 or token != cookieToken:
        ctx.response.code = Http403
        ctx.response.body = "CSRF token validation failed"
        return

    let token = generateCsrfToken()
    ctx.setCookie(cookieName, token, httpOnly = true, sameSite = "Strict")
    ctx["csrf_token"] = %token

    await switch(ctx)

proc getCsrfToken*(ctx: Context, tokenName = csrfTokenName): string =
  ctx.getCookie(csrfCookieName)

proc csrfTokenInput*(ctx: Context, tokenName = csrfTokenName): string =
  let token = ctx.getCsrfToken()
  """<input type="hidden" name="""" & tokenName & """" value="""" & token & """">"""
