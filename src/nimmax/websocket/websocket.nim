import std/[asyncdispatch, asynchttpserver, asyncnet, strutils, tables, base64, sha1, random, endians, options]
import ../core/types, ../core/context

type
  WSOpcode* = enum
    wsContinuation = 0x0
    wsText = 0x1
    wsBinary = 0x2
    wsClose = 0x8
    wsPing = 0x9
    wsPong = 0xA

  WSReadyState* = enum
    wsConnecting = 0
    wsOpen = 1
    wsClosing = 2
    wsClosed = 3

  WebSocket* = ref object
    ctx*: Context
    socket*: AsyncSocket
    readyState*: WSReadyState
    closeCode*: int

  WSHandler* = proc(ws: WebSocket): Future[void] {.closure, gcsafe.}
  WSMessageHandler* = proc(ws: WebSocket, message: string): Future[void] {.closure, gcsafe.}
  WSBinaryHandler* = proc(ws: WebSocket, data: seq[byte]): Future[void] {.closure, gcsafe.}
  WSCloseHandler* = proc(ws: WebSocket, code: int, reason: string): Future[void] {.closure, gcsafe.}

proc newWebSocket*(ctx: Context): WebSocket =
  WebSocket(ctx: ctx, readyState: wsConnecting, closeCode: 1005)

proc encodeFrame*(opcode: WSOpcode, data: string | seq[byte], fin = true): seq[byte] =
  var firstByte: byte = (if fin: 0x80'u8 else: 0x00'u8) or byte(opcode)
  result = @[firstByte]

  let length = data.len
  if length <= 125:
    result.add(byte(length))
  elif length <= 65535:
    result.add(126'u8)
    result.add(byte((length shr 8) and 0xFF))
    result.add(byte(length and 0xFF))
  else:
    result.add(127'u8)
    for i in countdown(7, 0):
      result.add(byte((length shr (i * 8)) and 0xFF))

  when data is string:
    for c in data:
      result.add(byte(c))
  else:
    result.add(data)

proc encodeCloseFrame*(code: int, reason = ""): seq[byte] =
  var payload = newSeq[byte](2)
  payload[0] = byte((code shr 8) and 0xFF)
  payload[1] = byte(code and 0xFF)
  if reason.len > 0:
    for c in reason:
      payload.add(byte(c))
  result = encodeFrame(wsClose, payload)

proc performHandshake*(ws: WebSocket) {.async.} =
  let key = ws.ctx.request.headers.getHeader("Sec-WebSocket-Key", "")
  if key.len == 0:
    ws.ctx.response.code = Http400
    ws.ctx.response.body = "Missing Sec-WebSocket-Key header"
    return

  let socket = ws.ctx.request.nativeRequest.client
  ws.socket = socket

  let acceptKey = encode(secureHash(key & "258EAFA5-E914-47DA-95CA-5AB9E6FE45D5").Sha1Digest)

  var response = "HTTP/1.1 101 Switching Protocols\r\n"
  response &= "Upgrade: websocket\r\n"
  response &= "Connection: Upgrade\r\n"
  response &= "Sec-WebSocket-Accept: " & acceptKey & "\r\n"
  response &= "\r\n"

  await socket.send(response)
  ws.readyState = wsOpen
  ws.ctx.upgraded = true

proc readFrame*(ws: WebSocket): Future[seq[byte]] {.async.} =
  if ws.readyState == wsClosed:
    return @[]

  var header = await ws.socket.recv(2)
  if header.len < 2:
    ws.readyState = wsClosed
    return @[]

  let fin = (header[0] and 0x80'u8) != 0
  let opcode = WSOpcode(header[0] and 0x0F'u8)

  let masked = (header[1] and 0x80'u8) != 0
  var payloadLen = int(header[1] and 0x7F'u8)

  if payloadLen == 126:
    var extLen = await ws.socket.recv(2)
    if extLen.len < 2:
      ws.readyState = wsClosed
      return @[]
    payloadLen = int(extLen[0]) shl 8 or int(extLen[1])
  elif payloadLen == 127:
    var extLen = await ws.socket.recv(8)
    if extLen.len < 8:
      ws.readyState = wsClosed
      return @[]
    payloadLen = 0
    for i in 0 ..< 8:
      payloadLen = payloadLen shl 8 or int(extLen[i])

  var maskKey: array[4, byte]
  if masked:
    var mask = await ws.socket.recv(4)
    if mask.len < 4:
      ws.readyState = wsClosed
      return @[]
    maskKey = [mask[0], mask[1], mask[2], mask[3]]

  var payload = await ws.socket.recv(payloadLen)
  if payload.len < payloadLen:
    ws.readyState = wsClosed
    return @[]

  if masked:
    for i in 0 ..< payload.len:
      payload[i] = payload[i] xor maskKey[i mod 4]

  case opcode
  of wsClose:
    var code = 1005
    var reason = ""
    if payload.len >= 2:
      code = int(payload[0]) shl 8 or int(payload[1])
    if payload.len > 2:
      reason = cast[string](payload[2 .. ^1])
    let response = encodeCloseFrame(code)
    await ws.socket.send(response)
    ws.readyState = wsClosed
    ws.closeCode = code
    return @[]
  of wsPing:
    let pongFrame = encodeFrame(wsPong, payload)
    await ws.socket.send(pongFrame)
    return @[]
  of wsPong:
    return @[]
  of wsText, wsBinary:
    if not fin:
      return await ws.readFrame()
    return payload
  else:
    return payload

proc sendText*(ws: WebSocket, message: string) {.async.} =
  if ws.readyState != wsOpen:
    return
  let frame = encodeFrame(wsText, message)
  await ws.socket.send(frame)

proc sendBinary*(ws: WebSocket, data: seq[byte]) {.async.} =
  if ws.readyState != wsOpen:
    return
  let frame = encodeFrame(wsBinary, data)
  await ws.socket.send(frame)

proc sendPing*(ws: WebSocket, data: string = "") {.async.} =
  if ws.readyState != wsOpen:
    return
  let frame = encodeFrame(wsPing, data)
  await ws.socket.send(frame)

proc receiveStrPacket*(ws: WebSocket): Future[string] {.async.} =
  while ws.readyState == wsOpen:
    let payload = await ws.readFrame()
    if payload.len == 0 and ws.readyState == wsClosed:
      return ""
    if payload.len > 0:
      return cast[string](payload)

proc receiveBinaryPacket*(ws: WebSocket): Future[seq[byte]] {.async.} =
  while ws.readyState == wsOpen:
    let payload = await ws.readFrame()
    if payload.len == 0 and ws.readyState == wsClosed:
      return @[]
    if payload.len > 0:
      return payload

proc close*(ws: WebSocket, code = 1000, reason = "") {.async.} =
  if ws.readyState != wsOpen:
    return
  ws.readyState = wsClosing
  let frame = encodeCloseFrame(code, reason)
  await ws.socket.send(frame)
  ws.readyState = wsClosed

proc loopMessages*(ws: WebSocket, onMessage: WSMessageHandler) {.async.} =
  while ws.readyState == wsOpen:
    let msg = await ws.receiveStrPacket()
    if msg.len > 0:
      await onMessage(ws, msg)

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
    if ws.readyState == wsOpen:
      await handler(ws)
      if ws.readyState == wsOpen:
        await ws.close()
