# NimMax Hunos Backend

NimMax supports an alternative HTTP backend powered by [Hunos](https://github.com/katehonz/hunos) — a high-performance, multi-threaded HTTP/1.1 and HTTP/2 server for Nim.

## Why Hunos Backend?

| Feature | asynchttpserver (default) | Hunos backend |
|---------|---------------------------|---------------|
| Concurrency | Single-threaded async | Multi-threaded worker pool |
| HTTP/2 | Not supported | H2C supported |
| Routing | Sequential scan | Trie-based O(k) matching* |
| Compression | Middleware-based | Built-in gzip/deflate |
| Best for | I/O-bound async apps | CPU-bound, high-throughput APIs |

*Routing is still handled by NimMax's router; Hunos provides the HTTP server layer.

## Quick Start

Change your import from `nimmax` to `nimmax/hunos`:

```nim
import nimmax/hunos  # <-- changed from `import nimmax`

proc hello(ctx: Context) {.async.} =
  ctx.html("<h1>Hello from Hunos!</h1>")

let app = newApp()
app.get("/", hello)
app.runHunos(port = Port(8080))
```

Compile with **threads on** and **ARC memory management**:

```bash
nim c --threads:on --mm:arc -r app.nim
```

## API Differences

The Hunos backend preserves the same NimMax API you already know:

- `newApp()` — create application
- `app.get()`, `app.post()`, etc. — register routes
- `app.use()` — add global middleware
- `ctx.html()`, `ctx.json()`, `ctx.text()` — send responses
- `ctx.getInt()`, `ctx.getFloat()`, `ctx.getBool()` — typed parameters

The only differences are:

1. **Import**: Use `import nimmax/hunos` instead of `import nimmax`
2. **Server start**: Use `app.runHunos()` instead of `app.run()`
3. **Compile flags**: Always use `--threads:on --mm:arc`

## Important Notes

### Async Handlers

NimMax handlers are `async`, but Hunos workers are synchronous OS threads. The adapter bridges this by using `waitFor` inside each worker thread.

This means:
- **CPU-bound handlers** (parsing, rendering, business logic) run perfectly and utilize all CPU cores
- **I/O-bound handlers** that use `await` for DB queries, HTTP clients, etc. will **block the worker thread** during the `await`

For I/O-bound workloads, consider:
- Using synchronous DB clients inside handlers
- Keeping the default `asynchttpserver` backend for heavy async I/O
- Running a hybrid setup (Hunos for API, asynchttpserver for async pages)

### Memory Management

Hunos requires `--mm:arc` or `--mm:orc`. We recommend `--mm:arc` for stability with the current Hunos version.

### WebSocket

WebSocket works through the Hunos backend using `registerHunosWs`:

```nim
proc wsHandler(ws: HunosWebSocket) {.async.} =
  while ws.readyState == wsOpen:
    let msg = await ws.receiveStrPacket()
    if msg.len > 0:
      ws.sendText("Echo: " & msg)

app.registerHunosWs("/ws", wsHandler)
```

Note: `HunosWebSocket` is used instead of the standard `WebSocket` type because
Hunos uses a sync callback architecture that requires an adapter layer.

## Example

See `examples/hunos_backend/basic.nim` for a complete working example.

```bash
nim c --threads:on --mm:arc -r examples/hunos_backend/basic.nim
```

Then visit http://localhost:8080
