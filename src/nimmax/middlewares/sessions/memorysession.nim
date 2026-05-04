import std/[asyncdispatch, tables, strutils, json, base64, locks]
import ../../core/types, ../../core/middleware, ../../core/context, ../../core/constants, ../../core/utils
import ../../security/signing

type
  SessionBackend* = enum
    sbMemory, sbSignedCookie

  MemorySessionStore* = ref object
    sessions: Table[string, Session]
    lock: Lock

proc newMemorySessionStore*(): MemorySessionStore =
  new(result)
  result.sessions = initTable[string, Session]()
  initLock(result.lock)

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

proc get(store: MemorySessionStore, id: string): Session =
  withLock store.lock:
    if store.sessions.hasKey(id):
      return store.sessions[id]
    return nil

proc put(store: MemorySessionStore, id: string, session: Session) =
  withLock store.lock:
    store.sessions[id] = session

proc memorySessionMiddleware*(
  sessionName = defaultSessionName,
  maxAge = defaultSessionMaxAge,
  path = defaultCookiePath,
  httpOnly = true,
  secure = false,
  sameSite = "Lax"
): HandlerAsync =
  let store = newMemorySessionStore()

  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let sessionId = ctx.getCookie(sessionName)

    var activeId = sessionId
    if sessionId.len > 0:
      let existing = store.get(sessionId)
      if existing != nil:
        ctx.session = existing
        ctx.session.accessed = true
      else:
        activeId = generateSessionId()
        ctx.session = newSession()
        store.put(activeId, ctx.session)
        ctx.setCookie(sessionName, activeId, path = path, maxAge = maxAge,
                      httpOnly = httpOnly, secure = secure, sameSite = sameSite)
    else:
      activeId = generateSessionId()
      ctx.session = newSession()
      store.put(activeId, ctx.session)
      ctx.setCookie(sessionName, activeId, path = path, maxAge = maxAge,
                    httpOnly = httpOnly, secure = secure, sameSite = sameSite)

    await switch(ctx)

    if ctx.session.modified:
      store.put(activeId, ctx.session)

proc signedCookieSessionMiddleware*(
  secretKey: SecretKey,
  sessionName = defaultSessionName,
  maxAge = defaultSessionMaxAge,
  path = defaultCookiePath
): HandlerAsync =
  let timedSigner = newTimedSigner(secretKey, maxAge = maxAge, salt = "nimmax.session")

  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let cookieValue = ctx.getCookie(sessionName)

    if cookieValue.len > 0:
      try:
        let unsigned = timedSigner.unsign(cookieValue)
        if unsigned.len > 0:
          ctx.session = deserialize(unsigned)
        else:
          ctx.session = newSession()
      except ValueError, JsonParsingError:
        ctx.session = newSession()
    else:
      ctx.session = newSession()

    await switch(ctx)

    if ctx.session.modified or ctx.session.newCreated:
      let serialized = serialize(ctx.session)
      let signed = timedSigner.sign(serialized)
      ctx.setCookie(sessionName, signed, path = path, maxAge = maxAge,
                    httpOnly = true, sameSite = "Lax")
