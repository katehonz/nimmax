import std/[tables, times, options, locks]

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
    lock: Lock

proc initLFUCache*[K, V](capacity = 128, defaultTimeout = 3600.0): LFUCache[K, V] =
  result = LFUCache[K, V](
    capacity: capacity,
    defaultTimeout: defaultTimeout,
    table: initTable[K, LFUNode[V]](),
    freqTable: initTable[int, seq[K]](),
    minFreq: 0
  )
  initLock(result.lock)

proc removeFromFreqTable[K, V](cache: LFUCache[K, V], key: K, freq: int) =
  if cache.freqTable.hasKey(freq):
    var keys = cache.freqTable[freq]
    let idx = keys.find(key)
    if idx >= 0:
      keys.del(idx)
      if keys.len == 0:
        cache.freqTable.del(freq)
      else:
        cache.freqTable[freq] = keys

proc addToFreqTable[K, V](cache: LFUCache[K, V], key: K, freq: int) =
  if not cache.freqTable.hasKey(freq):
    cache.freqTable[freq] = @[]
  cache.freqTable[freq].add(key)

proc get*[K, V](cache: LFUCache[K, V], key: K): Option[V] =
  acquire(cache.lock)
  try:
    if not cache.table.hasKey(key):
      return none(V)

    let node = cache.table[key]
    if epochTime() > node.expiresAt:
      cache.removeFromFreqTable(key, node.freq)
      cache.table.del(key)
      return none(V)

    let oldFreq = node.freq
    let newFreq = oldFreq + 1
    node.freq = newFreq

    cache.removeFromFreqTable(key, oldFreq)
    cache.addToFreqTable(key, newFreq)

    if not cache.freqTable.hasKey(oldFreq):
      if cache.minFreq == oldFreq:
        cache.minFreq = newFreq

    return some(node.value)
  finally:
    release(cache.lock)

proc put*[K, V](cache: LFUCache[K, V], key: K, value: V, timeout = 0.0) =
  acquire(cache.lock)
  try:
    let actualTimeout = if timeout > 0: timeout else: cache.defaultTimeout
    let expiresAt = epochTime() + actualTimeout

    if cache.table.hasKey(key):
      let node = cache.table[key]
      node.value = value
      node.expiresAt = expiresAt
      let oldFreq = node.freq
      let newFreq = oldFreq + 1
      node.freq = newFreq
      cache.removeFromFreqTable(key, oldFreq)
      cache.addToFreqTable(key, newFreq)
      if not cache.freqTable.hasKey(oldFreq):
        if cache.minFreq == oldFreq:
          cache.minFreq = newFreq
      return

    if cache.table.len >= cache.capacity:
      var evicted = false
      for f in cache.minFreq ..< high(int):
        if cache.freqTable.hasKey(f) and cache.freqTable[f].len > 0:
          let evictKey = cache.freqTable[f][0]
          cache.removeFromFreqTable(evictKey, f)
          cache.table.del(evictKey)
          evicted = true
          break
      if not evicted:
        var lowestFreq = high(int)
        var evictKey: K
        var found = false
        for k, n in cache.table:
          if n.freq < lowestFreq:
            lowestFreq = n.freq
            evictKey = k
            found = true
        if found:
          cache.removeFromFreqTable(evictKey, lowestFreq)
          cache.table.del(evictKey)

    let node = LFUNode[V](value: value, freq: 1, expiresAt: expiresAt)
    cache.table[key] = node
    cache.minFreq = 1
    cache.addToFreqTable(key, 1)
  finally:
    release(cache.lock)

proc del*[K, V](cache: LFUCache[K, V], key: K) =
  acquire(cache.lock)
  try:
    if cache.table.hasKey(key):
      let node = cache.table[key]
      cache.removeFromFreqTable(key, node.freq)
      cache.table.del(key)
  finally:
    release(cache.lock)

proc clear*[K, V](cache: LFUCache[K, V]) =
  acquire(cache.lock)
  try:
    cache.table.clear()
    cache.freqTable.clear()
    cache.minFreq = 0
  finally:
    release(cache.lock)

proc len*[K, V](cache: LFUCache[K, V]): int =
  acquire(cache.lock)
  try:
    result = cache.table.len
  finally:
    release(cache.lock)

proc hasKey*[K, V](cache: LFUCache[K, V], key: K): bool =
  cache.get(key).isSome
