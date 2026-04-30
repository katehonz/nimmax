# Cache

NimMax includes two in-memory cache implementations with TTL (Time-To-Live) expiration.

## LRU Cache (Least Recently Used)

Evicts the least recently accessed item when the cache is full.

```nim
import nimmax/cache

# Create a cache with capacity 1000 and default 1-hour TTL
var cache = initLRUCache[string, JsonNode](
  capacity = 1000,
  defaultTimeout = 3600.0  # seconds
)

# Store a value
cache.put("user:1", %*{"name": "Alice", "age": 30})

# Store with custom TTL (5 minutes)
cache.put("session:abc", %*{"user": "Alice"}, timeout = 300.0)

# Retrieve a value
let user = cache.get("user:1")  # Option[JsonNode]
if user.isSome:
  echo user.get()["name"].getStr()

# Check existence
if cache.hasKey("user:1"):
  echo "Found"

# Delete
cache.del("user:1")

# Get size
echo "Cached items: " & $cache.len()

# Clear all
cache.clear()
```

### LRU Behavior

When the cache reaches capacity, the **least recently accessed** item is evicted:

```nim
var cache = initLRUCache[string, int](capacity = 3)

cache.put("a", 1)
cache.put("b", 2)
cache.put("c", 3)

# Cache: [a=1, b=2, c=3]

discard cache.get("a")  # Access "a", moves it to front

# Cache: [b=2, c=3, a=1]

cache.put("d", 4)  # Evicts "b" (least recently used)

# Cache: [c=3, a=1, d=4]
```

## LFU Cache (Least Frequently Used)

Evicts the item with the lowest access count when the cache is full.

```nim
import nimmax/cache

var cache = initLFUCache[string, string](
  capacity = 500,
  defaultTimeout = 1800.0  # 30 minutes
)

# Store values
cache.put("config:db", "postgres://localhost/mydb")
cache.put("config:redis", "localhost:6379")

# Retrieve
let dbUrl = cache.get("config:db")  # Option[string]
if dbUrl.isSome:
  echo dbUrl.get()

# Custom TTL
cache.put("temp:data", "value", timeout = 60.0)  # 1 minute

# Check, delete, clear, len
if cache.hasKey("config:db"):
  echo "Found"
cache.del("config:db")
echo cache.len()
cache.clear()
```

### LFU Behavior

When the cache reaches capacity, the **least frequently accessed** item is evicted:

```nim
var cache = initLFUCache[string, int](capacity = 3)

cache.put("a", 1)
cache.put("b", 2)
cache.put("c", 3)

# Access "a" 5 times, "b" 3 times, "c" 1 time
for i in 0..<5: discard cache.get("a")
for i in 0..<3: discard cache.get("b")
discard cache.get("c")

cache.put("d", 4)  # Evicts "c" (lowest frequency)

# a=1 (freq=6), b=2 (freq=4), d=4 (freq=1)
```

## Choosing Between LRU and LFU

| Cache | Best For |
|---|---|
| **LRU** | General purpose, recent access patterns, session data |
| **LFU** | Hot data that's accessed frequently, configuration, reference data |

## TTL (Expiration)

Both caches support per-item TTL expiration:

```nim
# Default TTL (set at cache creation)
var cache = initLRUCache[string, string](capacity = 100, defaultTimeout = 3600.0)

# Uses default TTL (1 hour)
cache.put("key1", "value1")

# Custom TTL (5 minutes)
cache.put("key2", "value2", timeout = 300.0)

# Custom TTL (24 hours)
cache.put("key3", "value3", timeout = 86400.0)
```

Expired items are removed on access:

```nim
cache.put("temp", "data", timeout = 1.0)  # 1 second TTL
sleep(2000)
let val = cache.get("temp")  # Returns none(string) — expired
```

## Use Cases

### API Response Caching

```nim
var apiCache = initLRUCache[string, JsonNode](capacity = 100, defaultTimeout = 300.0)

app.get("/api/products", proc(ctx: Context) {.async.} =
  let cacheKey = "products:" & ctx.request.url.query
  let cached = apiCache.get(cacheKey)

  if cached.isSome:
    ctx.json(cached.get())
    return

  # Fetch from database
  let products = fetchProductsFromDB()
  let jsonProducts = %*products

  apiCache.put(cacheKey, jsonProducts)
  ctx.json(jsonProducts)
)
```

### Session Caching

```nim
var sessionCache = initLFUCache[string, Session](capacity = 10000, defaultTimeout = 86400.0)
```

### Rate Limiting

```nim
var rateLimitCache = initLRUCache[string, int](capacity = 10000, defaultTimeout = 60.0)

proc checkRateLimit(ip: string, maxRequests = 100): bool =
  let count = rateLimitCache.get(ip)
  if count.isNone:
    rateLimitCache.put(ip, 1)
    return true
  if count.get() >= maxRequests:
    return false
  rateLimitCache.put(ip, count.get() + 1)
  return true
```
