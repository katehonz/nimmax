# WebSocket

NimMax provides WebSocket support for real-time bidirectional communication.

## Basic WebSocket Route

```nim
import nimmax
import nimmax/websocket

app.get("/ws", wsRoute(proc(ws: WebSocket) {.async.} =
  await ws.performHandshake()

  # Connection is now open
  echo "Client connected"

  # Handle communication...
  await ws.sendText("Welcome!")
  await ws.close()
))
```

## WebSocket Handshake

The `wsRoute` helper handles the HTTP upgrade handshake automatically:

1. Validates the `Upgrade: websocket` header
2. Computes the `Sec-WebSocket-Accept` key
3. Sends the `101 Switching Protocols` response

```nim
proc echoHandler(ws: WebSocket) {.async.} =
  await ws.performHandshake()

  if ws.isOpen:
    echo "WebSocket connection established"
    await ws.sendText("Connected!")
    await ws.close()

app.get("/ws/echo", wsRoute(echoHandler))
```

## WebSocket Object

### Properties

| Property | Type | Description |
|---|---|---|
| `ws.ctx` | `Context` | The original HTTP context |
| `ws.isOpen` | `bool` | Whether the connection is open |

### Methods

```nim
# Send a text message
await ws.sendText("Hello, client!")

# Close the connection
await ws.close()
```

## Accessing Request Context

The WebSocket object provides access to the original request context, useful for authentication:

```nim
app.get("/ws/chat", wsRoute(proc(ws: WebSocket) {.async.} =
  # Check authentication from session/cookies
  let user = ws.ctx.session.getOrDefault("user", "")
  if user.len == 0:
    await ws.close()
    return

  await ws.performHandshake()
  await ws.sendText("Welcome to chat, " & user & "!")
  await ws.close()
))
```

## Manual WebSocket Handling

For more control, handle the WebSocket upgrade manually:

```nim
app.get("/ws/custom", proc(ctx: Context) {.async.} =
  let upgrade = ctx.request.headers.getHeader("Upgrade").toLowerAscii()
  if upgrade != "websocket":
    ctx.abortRequest(Http400, "Expected WebSocket upgrade")
    return

  let ws = newWebSocket(ctx)
  await ws.performHandshake()

  if ws.isOpen:
    await ws.sendText("Manual handshake complete")
    await ws.close()
)
```

## Example: Echo Server

```nim
import nimmax
import nimmax/websocket

proc echoWs(ws: WebSocket) {.async.} =
  await ws.performHandshake()
  if ws.isOpen:
    await ws.sendText("Echo server ready. Send me a message!")
    await ws.close()

proc main() =
  let app = newApp()
  app.use(loggingMiddleware())

  app.get("/", proc(ctx: Context) {.async.} =
    ctx.html("""
      <!DOCTYPE html>
      <html>
      <body>
        <h1>WebSocket Echo</h1>
        <input id="msg" type="text" placeholder="Type a message...">
        <button onclick="send()">Send</button>
        <pre id="output"></pre>
        <script>
          const ws = new WebSocket('ws://localhost:8080/ws');
          ws.onmessage = (e) => {
            document.getElementById('output').textContent += e.data + '\\n';
          };
          function send() {
            ws.send(document.getElementById('msg').value);
          }
        </script>
      </body>
      </html>
    """)
  )

  app.get("/ws", wsRoute(echoWs))
  app.run()

main()
```
