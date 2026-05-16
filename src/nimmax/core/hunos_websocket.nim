## Hunos WebSocket Adapter for NimMax
##
## Bridges Hunos sync WebSocket callbacks to NimMax async WebSocket API.
## Usage is identical to standard NimMax wsRoute:
##
##   app.get("/ws", hunosWsRoute(proc(ws: WebSocket) {.async.} =
##     while ws.readyState == wsOpen:
##       let msg = await ws.receiveStrPacket()
##       await ws.sendText("Echo: " & msg)
##   ))

when not defined(nimmaxHunos):
  {.error: "Hunos backend requires the Hunos package. Install with: nimble install hunos, then compile with -d:nimmaxHunos. If you don't need the Hunos backend, use 'import nimmax' instead.".}

import std/[asyncdispatch, locks, deques, hashes, tables]
import hunos
import ./types, ./context
import ../websocket/websocket as wsBase

# ---------------------------------------------------------------------------
# Re-export NimMax WebSocket types that don't depend on async socket
# ---------------------------------------------------------------------------

export wsBase.WSReadyState

# ---------------------------------------------------------------------------
# Hunos-backed WebSocket
# ---------------------------------------------------------------------------

type
  HunosWebSocket* = ref object of wsBase.WebSocket
    ## NimMax-compatible WebSocket backed by Hunos native WebSocket.
    hunosWs*: hunos.WebSocket
    msgQueue*: Deque[string]
    binQueue*: Deque[seq[byte]]
    queueLock*: Lock

proc newHunosWebSocket*(hws: hunos.WebSocket): HunosWebSocket =
  result = HunosWebSocket(
    hunosWs: hws,
    readyState: wsOpen,
    closeCode: 1005,
    msgQueue: initDeque[string](),
    binQueue: initDeque[seq[byte]]()
  )
  initLock(result.queueLock)

type
  WSHandler* = proc(ws: HunosWebSocket): Future[void] {.closure, gcsafe.}
  WSMessageHandler* = proc(ws: HunosWebSocket, message: string): Future[void] {.closure, gcsafe.}
  WSBinaryHandler* = proc(ws: HunosWebSocket, data: seq[byte]): Future[void] {.closure, gcsafe.}
  WSCloseHandler* = proc(ws: HunosWebSocket, code: int, reason: string): Future[void] {.closure, gcsafe.}

proc sendText*(ws: HunosWebSocket, message: string) {.gcsafe.} =
  ## Send a text frame through the Hunos WebSocket.
  if ws.readyState != wsOpen:
    return
  ws.hunosWs.send(message, hunos.TextMessage)

proc bytesToString(data: seq[byte]): string =
  result = newString(data.len)
  for i in 0 ..< data.len:
    result[i] = char(data[i])

proc stringToBytes(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i in 0 ..< s.len:
    result[i] = byte(s[i])

proc sendBinary*(ws: HunosWebSocket, data: seq[byte]) {.gcsafe.} =
  ## Send a binary frame through the Hunos WebSocket.
  if ws.readyState != wsOpen:
    return
  ws.hunosWs.send(bytesToString(data), hunos.BinaryMessage)

proc sendPing*(ws: HunosWebSocket, data: string = "") {.gcsafe.} =
  if ws.readyState != wsOpen:
    return
  ws.hunosWs.send(data, hunos.Ping)

proc receiveStrPacket*(ws: HunosWebSocket): Future[string] {.async.} =
  ## Receive the next text message. Blocks until a message arrives.
  while ws.readyState == wsOpen:
    acquire(ws.queueLock)
    if ws.msgQueue.len > 0:
      let msg = ws.msgQueue.popFirst()
      release(ws.queueLock)
      return msg
    release(ws.queueLock)
    await sleepAsync(5)
  return ""

proc receiveBinaryPacket*(ws: HunosWebSocket): Future[seq[byte]] {.async.} =
  ## Receive the next binary message. Blocks until a message arrives.
  while ws.readyState == wsOpen:
    acquire(ws.queueLock)
    if ws.binQueue.len > 0:
      let data = ws.binQueue.popFirst()
      release(ws.queueLock)
      return data
    release(ws.queueLock)
    await sleepAsync(5)
  return @[]

proc close*(ws: HunosWebSocket, code = 1000, reason = "") {.async.} =
  ## Close the WebSocket gracefully.
  acquire(ws.queueLock)
  if ws.readyState != wsOpen:
    release(ws.queueLock)
    return
  ws.readyState = wsClosing
  ws.closeCode = code
  release(ws.queueLock)
  ws.hunosWs.close()
  ws.readyState = wsClosed

proc loopMessages*(ws: HunosWebSocket, onMessage: WSMessageHandler) {.async.} =
  ## Loop receiving text messages until the WebSocket closes.
  while ws.readyState == wsOpen:
    let msg = await ws.receiveStrPacket()
    if msg.len > 0 and ws.readyState == wsOpen:
      await onMessage(ws, msg)

# ---------------------------------------------------------------------------
# Global adapter registry (thread-safe)
# ---------------------------------------------------------------------------

var gAdapters: Table[Hash, HunosWebSocket]
var gAdaptersLock: Lock
initLock(gAdaptersLock)

proc registerAdapter*(hws: hunos.WebSocket, adapter: HunosWebSocket) =
  {.gcsafe.}:
    withLock gAdaptersLock:
      gAdapters[hash(hws)] = adapter

proc unregisterAdapter*(hws: hunos.WebSocket) =
  {.gcsafe.}:
    withLock gAdaptersLock:
      gAdapters.del(hash(hws))

proc getAdapter*(hws: hunos.WebSocket): HunosWebSocket =
  {.gcsafe.}:
    withLock gAdaptersLock:
      result = gAdapters.getOrDefault(hash(hws), nil)

# ---------------------------------------------------------------------------
# Hunos WebSocketHandler callback
# ---------------------------------------------------------------------------

proc hunosWebSocketHandler*(
  websocket: hunos.WebSocket,
  event: hunos.WebSocketEvent,
  message: hunos.Message
) {.gcsafe.} =
  ## Called by Hunos worker threads when WebSocket events occur.
  let adapter = getAdapter(websocket)
  if adapter.isNil:
    return

  case event:
  of hunos.MessageEvent:
    case message.kind:
    of hunos.TextMessage:
      acquire(adapter.queueLock)
      adapter.msgQueue.addLast(message.data)
      release(adapter.queueLock)
    of hunos.BinaryMessage:
      acquire(adapter.queueLock)
      adapter.binQueue.addLast(stringToBytes(message.data))
      release(adapter.queueLock)
    of hunos.Ping:
      websocket.send(message.data, hunos.Pong)
    of hunos.Pong:
      discard
    else:
      discard
  of hunos.CloseEvent:
    acquire(adapter.queueLock)
    adapter.readyState = wsClosed
    adapter.msgQueue.addLast("")   # unblock receive
    release(adapter.queueLock)
  of hunos.ErrorEvent:
    acquire(adapter.queueLock)
    adapter.readyState = wsClosed
    adapter.msgQueue.addLast("")   # unblock receive
    release(adapter.queueLock)
  else:
    discard

# ---------------------------------------------------------------------------
# hunosWsRoute — NimMax-compatible wsRoute for Hunos backend
# ---------------------------------------------------------------------------

proc runWsHandlerAsync(adapter: HunosWebSocket, handler: WSHandler) {.async.} =
  ## Runs the user's async WebSocket handler.
  try:
    await handler(adapter)
  except Exception as e:
    echo "WebSocket handler error: " & e.msg
  finally:
    if adapter.readyState == wsOpen:
      await adapter.close()
    unregisterAdapter(adapter.hunosWs)

proc startHunosWs*(request: hunos.Request, handler: WSHandler) {.gcsafe.} =
  ## Internal: starts a WebSocket connection and runs the given handler.
  let upgrade = request.headers["Upgrade"].toLowerAscii()
  if upgrade != "websocket":
    request.respond(400, body = "Expected WebSocket upgrade")
    return

  try:
    let hws = request.upgradeToWebSocket()
    let adapter = newHunosWebSocket(hws)
    registerAdapter(hws, adapter)

    # Run the async handler in a dedicated thread with its own event loop
    var wsThread: Thread[tuple[adapter: HunosWebSocket, handler: WSHandler]]
    proc wsThreadProc(args: tuple[adapter: HunosWebSocket, handler: WSHandler]) {.thread.} =
      try:
        waitFor runWsHandlerAsync(args.adapter, args.handler)
      except Exception as e:
        echo "WebSocket thread error: " & e.msg
        args.adapter.readyState = wsClosed
        unregisterAdapter(args.adapter.hunosWs)

    createThread(wsThread, wsThreadProc, (adapter, handler))

  except Exception as e:
    request.respond(500, body = "WebSocket upgrade failed: " & e.msg)
