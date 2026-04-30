import std/[asyncdispatch, asynchttpserver, strutils, tables, base64, sha1, random]
import ../core/types, ../core/context

type
  WebSocketFrame* = object
    opcode*: int
    data*: string
    fin*: bool

  WebSocket* = ref object
    ctx*: Context
    isOpen*: bool

  WSHandler* = proc(ws: WebSocket): Future[void] {.closure, gcsafe.}
  WSMessageHandler* = proc(ws: WebSocket, message: string): Future[void] {.closure, gcsafe.}

proc newWebSocket*(ctx: Context): WebSocket =
  WebSocket(ctx: ctx, isOpen: false)

proc performHandshake*(ws: WebSocket) {.async.} =
  let key = ws.ctx.request.headers.getHeader("Sec-WebSocket-Key", "")
  if key.len == 0:
    ws.ctx.response.code = Http400
    ws.ctx.response.body = "Missing Sec-WebSocket-Key header"
    return

  let acceptKey = encode(secureHash(key & "258EAFA5-E914-47DA-95CA-5AB9E6FE45D5").Sha1Digest)
  ws.ctx.response.code = Http101
  ws.ctx.response.headers["Upgrade"] = "websocket"
  ws.ctx.response.headers["Connection"] = "Upgrade"
  ws.ctx.response.headers["Sec-WebSocket-Accept"] = acceptKey
  ws.isOpen = true

proc sendText*(ws: WebSocket, message: string) {.async.} =
  if not ws.isOpen:
    return
  ws.ctx.response.body = message
  ws.ctx.response.headers["X-WebSocket-Frame"] = "text"

proc close*(ws: WebSocket) {.async.} =
  ws.isOpen = false

proc wsRoute*(handler: WSHandler): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let upgrade = ctx.request.headers.getHeader("Upgrade", "").toLowerAscii()
    let connection = ctx.request.headers.getHeader("Connection", "").toLowerAscii()

    if upgrade != "websocket" or "upgrade" notin connection:
      ctx.response.code = Http400
      ctx.response.body = "Expected WebSocket upgrade"
      return

    let ws = newWebSocket(ctx)
    await ws.performHandshake()
    if ws.isOpen:
      await handler(ws)
