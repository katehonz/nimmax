import std/[asyncdispatch, times, tables, locks, strutils, httpcore]
import ../core/types, ../core/middleware, ../core/context

type
  RateLimiter* = ref object
    requests: Table[string, seq[int64]]
    lock: Lock
    maxRequests: int
    windowMs: int64
    enabled*: bool

  RateLimitExceeded* = object of CatchableError

proc newRateLimiter*(maxRequests: int = 100, windowSeconds: int = 60): RateLimiter =
  new(result)
  result.maxRequests = maxRequests
  result.windowMs = int64(windowSeconds) * 1000
  result.enabled = true
  initLock(result.lock)

proc cleanupExpired*(rl: RateLimiter, clientId: string, nowMs: int64) =
  if rl.requests.hasKey(clientId):
    var timestamps = rl.requests[clientId]
    timestamps = timestamps.filterIt(nowMs - it < rl.windowMs)
    if timestamps.len == 0:
      rl.requests.del(clientId)
    else:
      rl.requests[clientId] = timestamps

proc isAllowed*(rl: RateLimiter, clientId: string): tuple[allowed: bool, remaining: int, resetAt: int64] =
  if not rl.enabled:
    return (true, rl.maxRequests, 0)

  let nowMs = epochTime() * 1000
  withLock rl.lock:
    rl.cleanupExpired(clientId, nowMs)
    if not rl.requests.hasKey(clientId):
      rl.requests[clientId] = @[nowMs]
      return (true, rl.maxRequests - 1, nowMs + rl.windowMs)
    var timestamps = rl.requests[clientId]
    timestamps.add(nowMs)
    rl.requests[clientId] = timestamps
    let remaining = max(0, rl.maxRequests - timestamps.len)
    let allowed = timestamps.len <= rl.maxRequests
    let oldest = if timestamps.len > 0: timestamps[0] else: nowMs
    let resetAt = oldest + rl.windowMs
    return (allowed, remaining, resetAt)

proc reset*(rl: RateLimiter, clientId: string) =
  withLock rl.lock:
    rl.requests.del(clientId)

proc clear*(rl: RateLimiter) =
  withLock rl.lock:
    rl.requests.clear()

proc rateLimitMiddleware*(
  limiter: RateLimiter,
  keyExtractor: proc(ctx: Context): string {.gcsafe.} = nil,
  skipPaths: seq[string] = @[]
): HandlerAsync =
  let defaultKeyExtractor = proc(ctx: Context): string {.gcsafe.} =
    let ip = ctx.request.headers.getHeader("X-Forwarded-For", "")
    if ip.len > 0:
      return ip.split(",")[0].strip()
    return ctx.request.ip

  let extractor = if keyExtractor != nil: keyExtractor else: defaultKeyExtractor

  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    for path in skipPaths:
      if ctx.request.url.path.startsWith(path):
        await switch(ctx)
        return

    let clientId = extractor(ctx)
    let (allowed, remaining, resetAt) = limiter.isAllowed(clientId)

    ctx.response.headers["X-RateLimit-Limit"] = $limiter.maxRequests
    ctx.response.headers["X-RateLimit-Remaining"] = $remaining
    if resetAt > 0:
      let resetSeconds = max(1, (resetAt - (epochTime() * 1000)) div 1000)
      ctx.response.headers["X-RateLimit-Reset"] = $resetSeconds

    if not allowed:
      ctx.response.code = Http429
      ctx.response.body = "Rate limit exceeded. Try again later."
      ctx.response.headers["Retry-After"] = $max(1, (resetAt - (epochTime() * 1000)) div 1000)
      return

    await switch(ctx)