# WebSocket

NimMax provides a full RFC 6455 WebSocket implementation with support for text and binary messages, ping/pong, and graceful close.

## Basic WebSocket Route

```nim
import nimmax
import nimmax/websocket

app.get("/ws", wsRoute(proc(ws: WebSocket) {.async.} =
  echo "Client connected"

  while ws.readyState == wsOpen:
    let msg = await ws.receiveStrPacket()
    if msg.len > 0:
      echo "Received: " & msg
      await ws.sendText("Echo: " & msg)

  echo "Client disconnected, code: " & $ws.closeCode
))
```

The `wsRoute` handler automatically performs the HTTP upgrade handshake and manages the connection lifecycle:
1. Validates `Upgrade: websocket` and `Connection: upgrade` headers
2. Computes `Sec-WebSocket-Accept` key
3. Sends `101 Switching Protocols` response directly via socket
4. Calls your handler with the ready WebSocket
5. Automatically closes the connection when your handler returns

## WebSocket Object

### Properties

| Property | Type | Description |
|---|---|---|
| `ws.ctx` | `Context` | The original HTTP context |
| `ws.socket` | `AsyncSocket` | The raw TCP socket |
| `ws.readyState` | `WSReadyState` | Connection state |
| `ws.closeCode` | `int` | Close code received from client (default: 1005) |

### Ready States

| Value | Description |
|---|---|
| `wsConnecting` (0) | Initial state, before handshake |
| `wsOpen` (1) | Handshake complete, connection open |
| `wsClosing` (2) | Close frame sent, waiting for response |
| `wsClosed` (3) | Connection closed |

## Sending Messages

### Text Messages

```nim
await ws.sendText("Hello, world!")
```

### Binary Messages

```nim
let data = @[byte(1), byte(2), byte(3)]
await ws.sendBinary(data)
```

### Ping

```nim
await ws.sendPing("keepalive")
```

Pong responses are handled automatically by `readFrame`.

## Receiving Messages

### Text Messages

```nim
let msg = await ws.receiveStrPacket()
if msg.len > 0:
  echo "Text message: " & msg
```

### Binary Messages

```nim
let data = await ws.receiveBinaryPacket()
if data.len > 0:
  echo "Binary data: " & $data.len & " bytes"
```

### Message Loop

```nim
await ws.loopMessages(proc(ws: WebSocket, msg: string) {.async.} =
  echo "Message: " & msg
  await ws.sendText("Got: " & msg)
)
```

## Closing Connections

### Graceful Close

```nim
await ws.close(code = 1000, reason = "Done")
```

Standard close codes:
- `1000` — Normal closure
- `1001` — Going away (e.g., tab closed)
- `1002` — Protocol error
- `1008` — Policy violation
- `1011` — Internal server error

### Detecting Client Disconnect

```nim
while ws.readyState == wsOpen:
  let msg = await ws.receiveStrPacket()
  if msg.len == 0 and ws.readyState == wsClosed:
    echo "Client disconnected with code: " & $ws.closeCode
    break
  # process msg
```

## Low-Level Frame API

For advanced use cases, access raw WebSocket frames:

```nim
let frame = await ws.readFrame()  # returns seq[byte]

# Send raw frame
let frame = encodeFrame(wsText, "Hello")  # returns seq[byte]
await ws.socket.send(frame)

# Send close frame
let closeFrame = encodeCloseFrame(1000, "Bye")
await ws.socket.send(closeFrame)
```

### Opcodes

| Opcode | Value | Description |
|---|---|---|
| `wsContinuation` | 0x0 | Continuation frame |
| `wsText` | 0x1 | Text frame |
| `wsBinary` | 0x2 | Binary frame |
| `wsClose` | 0x8 | Connection close |
| `wsPing` | 0x9 | Ping |
| `wsPong` | 0xA | Pong |

## Manual Handshake

For full control, handle the WebSocket upgrade without `wsRoute`:

```nim
app.get("/ws/custom", proc(ctx: Context) {.async.} =
  let upgrade = ctx.request.headers.getHeader("Upgrade").toLowerAscii()
  if upgrade != "websocket":
    ctx.abortRequest(Http400, "Expected WebSocket upgrade")
    return

  let ws = newWebSocket(ctx)
  await ws.performHandshake()

  if ws.readyState == wsOpen:
    await ws.sendText("Handshake complete")
    while ws.readyState == wsOpen:
      let msg = await ws.receiveStrPacket()
      if msg.len > 0:
        await ws.sendText("Echo: " & msg)
)
```

## Accessing Request Context

The WebSocket object provides access to the original HTTP context — useful for authentication via sessions or cookies:

```nim
app.get("/ws/chat", wsRoute(proc(ws: WebSocket) {.async.} =
  let user = ws.ctx.session.getOrDefault("user", "")
  if user.len == 0:
    await ws.sendText("Please authenticate first")
    await ws.close(1008, "Unauthenticated")
    return

  await ws.sendText("Welcome to chat, " & user & "!")
  while ws.readyState == wsOpen:
    let msg = await ws.receiveStrPacket()
    if msg.len > 0:
      broadcast(user, msg)
))
```

## NimLeptos Realtime Integration

NimMax WebSocket is the transport layer for NimLeptos realtime signal synchronization:

```nim
import nimleptos/server
import nimleptos/realtime

let app = newNimLeptosApp()

let onlineCount = createServerSignal[int]("online", 0)

app.get("/ws", wsRoute(proc(ws: WebSocket) {.async.} =
  onlineCount.setServerValue(onlineCount.currentValue + 1)
  await ws.loopMessages(handleRealtimeMessage)
  onlineCount.setServerValue(onlineCount.currentValue - 1)
))
```

## Example: Chat Server

```nim
import nimmax
import nimmax/websocket

var clients: seq[WebSocket] = @[]

proc broadcast(msg: string) {.async.} =
  for i in countdown(clients.len - 1, 0):
    if clients[i].readyState == wsOpen:
      try:
        await clients[i].sendText(msg)
      except:
        clients.del(i)
    else:
      clients.del(i)

app.get("/ws", wsRoute(proc(ws: WebSocket) {.async.} =
  clients.add(ws)
  echo "Client connected (" & $clients.len & " total)"

  while ws.readyState == wsOpen:
    let msg = await ws.receiveStrPacket()
    if msg.len > 0:
      echo "Chat message: " & msg
      await broadcast(msg)

  # Remove disconnected client
  for i in 0 ..< clients.len:
    if clients[i] == ws:
      clients.del(i)
      break
  echo "Client disconnected (" & $clients.len & " total)"
))
```

## Example: Full HTML Client

```nim
app.get("/", proc(ctx: Context) {.async.} =
  ctx.html("""
    <!DOCTYPE html>
    <html>
    <body>
      <h1>WebSocket Echo</h1>
      <input id="msg" type="text" placeholder="Type a message..." />
      <button onclick="send()">Send</button>
      <pre id="output"></pre>
      <script>
        const ws = new WebSocket('ws://' + location.host + '/ws');
        ws.onmessage = (e) => {
          document.getElementById('output').textContent += e.data + '\\n';
        };
        function send() {
          ws.send(document.getElementById('msg').value);
          document.getElementById('msg').value = '';
        }
      </script>
    </body>
    </html>
  """)
)
```
