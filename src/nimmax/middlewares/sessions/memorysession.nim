import std/[asyncdispatch, tables, strutils, httpcore, random, times, json, base64]
import ../../core/types, ../../core/middleware, ../../core/context, ../../core/constants, ../../core/utils

type
  SessionBackend* = enum
    sbMemory, sbSignedCookie

proc newSession*(): Session =
  Session(
    data: newTable[string, string](),
    newCreated: true,
    modified: false,
    accessed: false
  )

proc generateSessionId*(): string =
  randomString(32)

proc serialize*(session: Session): string =
  let data = %*session.data
  encode($data, safe = true)

proc deserialize*(data: string): Session =
  let decoded = decode(data)
  let jsonNode = parseJson(decoded)
  result = newSession()
  result.newCreated = false
  for k, v in jsonNode:
    result.data[k] = v.getStr()

proc `[]`*(session: Session, key: string): string =
  session.accessed = true
  session.data.getOrDefault(key, "")

proc `[]=`*(session: Session, key, value: string) =
  session.accessed = true
  session.modified = true
  session.data[key] = value

proc del*(session: Session, key: string) =
  session.accessed = true
  session.modified = true
  session.data.del(key)

proc clear*(session: Session) =
  session.accessed = true
  session.modified = true
  session.data.clear()

proc hasKey*(session: Session, key: string): bool =
  session.accessed = true
  session.data.hasKey(key)

proc len*(session: Session): int =
  session.data.len

proc pairs*(session: Session): seq[(string, string)] =
  result = @[]
  for k, v in session.data.pairs():
    result.add((k, v))

proc memorySessionMiddleware*(
  sessionName = defaultSessionName,
  maxAge = defaultSessionMaxAge,
  path = defaultCookiePath,
  httpOnly = true,
  secure = false,
  sameSite = "Lax"
): HandlerAsync =
  var sessions = initTable[string, Session]()

  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let sessionId = ctx.getCookie(sessionName)

    if sessionId.len > 0 and sessions.hasKey(sessionId):
      ctx.session = sessions[sessionId]
      ctx.session.accessed = true
    else:
      let newId = generateSessionId()
      ctx.session = newSession()
      sessions[newId] = ctx.session
      ctx.setCookie(sessionName, newId, path = path, maxAge = maxAge,
                    httpOnly = httpOnly, secure = secure, sameSite = sameSite)

    await switch(ctx)

    if ctx.session.modified:
      sessions[sessionId] = ctx.session

proc signedCookieSessionMiddleware*(
  secretKey: SecretKey,
  sessionName = defaultSessionName,
  maxAge = defaultSessionMaxAge,
  path = defaultCookiePath
): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let cookieValue = ctx.getCookie(sessionName)

    if cookieValue.len > 0:
      try:
        ctx.session = deserialize(cookieValue)
      except:
        ctx.session = newSession()
    else:
      ctx.session = newSession()

    await switch(ctx)

    if ctx.session.modified or ctx.session.newCreated:
      let serialized = serialize(ctx.session)
      ctx.setCookie(sessionName, serialized, path = path, maxAge = maxAge,
                    httpOnly = true, sameSite = "Lax")
