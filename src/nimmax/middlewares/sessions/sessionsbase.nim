import ../../core/types

import ./memorysession
export memorysession

proc sessionMiddleware*(
  backend: SessionBackend = sbMemory,
  sessionName = "nimmax_session",
  maxAge = 14 * 24 * 60 * 60,
  path = "/",
  secretKey: SecretKey = SecretKey("")
): HandlerAsync =
  case backend
  of sbMemory:
    memorySessionMiddleware(sessionName = sessionName, maxAge = maxAge, path = path)
  of sbSignedCookie:
    if secretKey.len == 0:
      raise newException(ValueError, "secretKey is required for signed cookie sessions")
    signedCookieSessionMiddleware(secretKey, sessionName = sessionName, maxAge = maxAge, path = path)
