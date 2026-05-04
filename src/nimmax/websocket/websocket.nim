import std/[asyncdispatch, asynchttpserver, asyncnet, strutils, tables, base64, sha1, random, endians, options]
import ../core/types, ../core/context, ../core/utils

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

  WebSocket* = ref object of RootObj
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

proc frameToString(frame: seq[byte]): string =
  result = newString(frame.len)
  for i in 0 ..< frame.len:
    result[i] = char(frame[i])

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

proc readRawFrame*(ws: WebSocket): Future[tuple[opcode: WSOpcode, fin: bool, data: seq[byte]]] {.async.} =
  if ws.readyState == wsClosed:
    return (wsClose, true, @[])

  var header = await ws.socket.recv(2)
  if header.len < 2:
    ws.readyState = wsClosed
    return (wsClose, true, @[])

  let b0 = byte(header[0])
  let b1 = byte(header[1])
  let fin = (b0 and 0x80'u8) != 0
  let opcode = WSOpcode(b0 and 0x0F'u8)

  let masked = (b1 and 0x80'u8) != 0
  var payloadLen = int(b1 and 0x7F'u8)

  if payloadLen == 126:
    var extLen = await ws.socket.recv(2)
    if extLen.len < 2:
      ws.readyState = wsClosed
      return (wsClose, true, @[])
    payloadLen = int(extLen[0]) shl 8 or int(extLen[1])
  elif payloadLen == 127:
    var extLen = await ws.socket.recv(8)
    if extLen.len < 8:
      ws.readyState = wsClosed
      return (wsClose, true, @[])
    payloadLen = 0
    for i in 0 ..< 8:
      payloadLen = payloadLen shl 8 or int(extLen[i])

  var maskKey: array[4, byte]
  if masked:
    var mask = await ws.socket.recv(4)
    if mask.len < 4:
      ws.readyState = wsClosed
      return (wsClose, true, @[])
    maskKey = [byte(mask[0]), byte(mask[1]), byte(mask[2]), byte(mask[3])]

  var payload = await ws.socket.recv(payloadLen)
  if payload.len < payloadLen:
    ws.readyState = wsClosed
    return (wsClose, true, @[])

  if masked:
    for i in 0 ..< payload.len:
      payload[i] = char(byte(payload[i]) xor maskKey[i mod 4])

  var data = newSeq[byte](payload.len)
  for i in 0 ..< payload.len:
    data[i] = byte(payload[i])

  return (opcode, fin, data)

proc readFrame*(ws: WebSocket): Future[seq[byte]] {.async.} =
  var messageBuffer = newSeq[byte]()

  while ws.readyState == wsOpen:
    let (opcode, fin, data) = await ws.readRawFrame()

    case opcode
    of wsClose:
      var code = 1005
      var reason = ""
      if data.len >= 2:
        code = int(data[0]) shl 8 or int(data[1])
      if data.len > 2:
        reason = newString(data.len - 2)
        for i in 2 ..< data.len:
          reason[i - 2] = char(data[i])
      let response = encodeCloseFrame(code)
      await ws.socket.send(frameToString(response))
      ws.readyState = wsClosed
      ws.closeCode = code
      return @[]
    of wsPing:
      let pongFrame = encodeFrame(wsPong, data)
      await ws.socket.send(frameToString(pongFrame))
      continue
    of wsPong:
      continue
    of wsText, wsBinary:
      if not fin:
        messageBuffer = data
        continue
      else:
        return data
    of wsContinuation:
      messageBuffer.add(data)
      if fin:
        return messageBuffer

  return @[]

proc sendText*(ws: WebSocket, message: string) {.async.} =
  if ws.readyState != wsOpen:
    return
  let frame = encodeFrame(wsText, message)
  await ws.socket.send(frameToString(frame))

proc sendBinary*(ws: WebSocket, data: seq[byte]) {.async.} =
  if ws.readyState != wsOpen:
    return
  let frame = encodeFrame(wsBinary, data)
  await ws.socket.send(frameToString(frame))

proc sendPing*(ws: WebSocket, data: string = "") {.async.} =
  if ws.readyState != wsOpen:
    return
  let frame = encodeFrame(wsPing, data)
  await ws.socket.send(frameToString(frame))

proc receiveStrPacket*(ws: WebSocket): Future[string] {.async.} =
  while ws.readyState == wsOpen:
    let payload = await ws.readFrame()
    if payload.len == 0 and ws.readyState == wsClosed:
      return ""
    if payload.len > 0:
      result = newString(payload.len)
      for i in 0 ..< payload.len:
        result[i] = char(payload[i])
      return result

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
  await ws.socket.send(frameToString(frame))
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
