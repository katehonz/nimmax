import std/net

const
  nimMaxVersion* = "1.0.0"
  nimMaxPrefix* = "NIMMAX_"
  defaultAddress* = "0.0.0.0"
  defaultPort* = Port(8080)
  defaultBufSize* = 40960
  defaultAppName* = "NimMax"
  defaultSessionName* = "nimmax_session"
  defaultSecretKeyLength* = 32
  defaultCookiePath* = "/"
  defaultSessionMaxAge* = 14 * 24 * 60 * 60  # 14 days
  csrfTokenName* = "nimmax_csrf_token"
  csrfCookieName* = "nimmax_csrf"
