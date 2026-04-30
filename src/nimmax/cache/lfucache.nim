import std/[tables, times, options]

type
  LFUNode*[V] = ref object
    value*: V
    freq*: int
    expiresAt*: float

  LFUCache*[K, V] = ref object
    capacity*: int
    defaultTimeout*: float
    table*: Table[K, LFUNode[V]]
    freqTable*: Table[int, seq[K]]
    minFreq*: int

proc initLFUCache*[K, V](capacity = 128, defaultTimeout = 3600.0): LFUCache[K, V] =
  result = LFUCache[K, V](
    capacity: capacity,
    defaultTimeout: defaultTimeout,
    table: initTable[K, LFUNode[V]](),
    freqTable: initTable[int, seq[K]](),
    minFreq: 0
  )

proc get*[K, V](cache: LFUCache[K, V], key: K): Option[V] =
  if not cache.table.hasKey(key):
    return none(V)

  let node = cache.table[key]
  if epochTime() > node.expiresAt:
    cache.table.del(key)
    return none(V)

  let oldFreq = node.freq
  let newFreq = oldFreq + 1
  node.freq = newFreq

  if cache.freqTable.hasKey(oldFreq):
    var keys = cache.freqTable[oldFreq]
    let idx = keys.find(key)
    if idx >= 0:
      keys.del(idx)
      cache.freqTable[oldFreq] = keys
      if keys.len == 0:
        cache.freqTable.del(oldFreq)
        if cache.minFreq == oldFreq:
          cache.minFreq = newFreq

  if not cache.freqTable.hasKey(newFreq):
    cache.freqTable[newFreq] = @[]
  cache.freqTable[newFreq].add(key)

  some(node.value)

proc put*[K, V](cache: LFUCache[K, V], key: K, value: V, timeout = 0.0) =
  let actualTimeout = if timeout > 0: timeout else: cache.defaultTimeout
  let expiresAt = epochTime() + actualTimeout

  if cache.table.hasKey(key):
    let node = cache.table[key]
    node.value = value
    node.expiresAt = expiresAt
    discard cache.get(key)
    return

  if cache.table.len >= cache.capacity:
    var evicted = false
    for f in cache.minFreq .. cache.minFreq + 100:
      if cache.freqTable.hasKey(f) and cache.freqTable[f].len > 0:
        let evictKey = cache.freqTable[f][0]
        cache.freqTable[f].del(0)
        if cache.freqTable[f].len == 0:
          cache.freqTable.del(f)
        cache.table.del(evictKey)
        evicted = true
        break
    if not evicted:
      var oldestKey: K
      for k, n in cache.table:
        oldestKey = k
        break
      cache.table.del(oldestKey)

  let node = LFUNode[V](value: value, freq: 1, expiresAt: expiresAt)
  cache.table[key] = node
  cache.minFreq = 1
  if not cache.freqTable.hasKey(1):
    cache.freqTable[1] = @[]
  cache.freqTable[1].add(key)

proc del*[K, V](cache: LFUCache[K, V], key: K) =
  if cache.table.hasKey(key):
    cache.table.del(key)

proc clear*[K, V](cache: LFUCache[K, V]) =
  cache.table.clear()
  cache.freqTable.clear()
  cache.minFreq = 0

proc len*[K, V](cache: LFUCache[K, V]): int =
  cache.table.len

proc hasKey*[K, V](cache: LFUCache[K, V], key: K): bool =
  cache.get(key).isSome
