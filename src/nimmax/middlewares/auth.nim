import std/[asyncdispatch, strutils, httpcore, base64]
import ../core/types, ../core/middleware, ../core/context, ../core/utils

type
  VerifyHandler* = proc(username, password: string): bool {.gcsafe.}

proc basicAuthMiddleware*(
  realm: string,
  verifyHandler: VerifyHandler,
  charset = "UTF-8"
): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let authHeader = ctx.request.headers.getHeader("Authorization", "")

    if authHeader.len == 0 or not authHeader.startsWith("Basic "):
      ctx.response.code = Http401
      ctx.response.headers["WWW-Authenticate"] = "Basic realm=\"" & realm & "\", charset=\"" & charset & "\""
      ctx.response.body = "Unauthorized"
      return

    let encoded = authHeader[6 .. ^1]
    var decoded: string
    try:
      decoded = decode(encoded)
    except ValueError:
      ctx.response.code = Http401
      ctx.response.body = "Invalid authorization header"
      return

    let parts = decoded.split(':', 1)
    if parts.len != 2:
      ctx.response.code = Http401
      ctx.response.body = "Invalid authorization format"
      return

    if not verifyHandler(parts[0], parts[1]):
      ctx.response.code = Http401
      ctx.response.headers["WWW-Authenticate"] = "Basic realm=\"" & realm & "\", charset=\"" & charset & "\""
      ctx.response.body = "Invalid credentials"
      return

    ctx["auth_user"] = %parts[0]
    await switch(ctx)
