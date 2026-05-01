import std/[tables, times, options, locks]

type
  LRUNode*[K, V] = ref object
    key*: K
    value*: V
    expiresAt*: float
    next*, prev*: LRUNode[K, V]

  LRUCache*[K, V] = ref object
    capacity*: int
    defaultTimeout*: float
    size*: int
    head*, tail*: LRUNode[K, V]
    table*: Table[K, LRUNode[K, V]]
    lock: Lock

proc initLRUCache*[K, V](capacity = 128, defaultTimeout = 3600.0): LRUCache[K, V] =
  result = LRUCache[K, V](
    capacity: capacity,
    defaultTimeout: defaultTimeout,
    size: 0,
    head: nil,
    tail: nil,
    table: initTable[K, LRUNode[K, V]]()
  )
  initLock(result.lock)

proc removeNode[K, V](cache: LRUCache[K, V], node: LRUNode[K, V]) =
  if node.prev != nil:
    node.prev.next = node.next
  else:
    cache.head = node.next

  if node.next != nil:
    node.next.prev = node.prev
  else:
    cache.tail = node.prev

proc addToFront[K, V](cache: LRUCache[K, V], node: LRUNode[K, V]) =
  node.next = cache.head
  node.prev = nil
  if cache.head != nil:
    cache.head.prev = node
  cache.head = node
  if cache.tail.isNil:
    cache.tail = node

proc get*[K, V](cache: LRUCache[K, V], key: K): Option[V] =
  acquire(cache.lock)
  try:
    if not cache.table.hasKey(key):
      return none(V)

    let node = cache.table[key]
    if epochTime() > node.expiresAt:
      cache.removeNode(node)
      cache.table.del(key)
      dec cache.size
      return none(V)

    cache.removeNode(node)
    cache.addToFront(node)
    return some(node.value)
  finally:
    release(cache.lock)

proc put*[K, V](cache: LRUCache[K, V], key: K, value: V, timeout = 0.0) =
  acquire(cache.lock)
  try:
    let actualTimeout = if timeout > 0: timeout else: cache.defaultTimeout
    let expiresAt = epochTime() + actualTimeout

    if cache.table.hasKey(key):
      let node = cache.table[key]
      node.value = value
      node.expiresAt = expiresAt
      cache.removeNode(node)
      cache.addToFront(node)
      return

    if cache.size >= cache.capacity:
      let tail = cache.tail
      cache.removeNode(tail)
      cache.table.del(tail.key)
      dec cache.size

    let node = LRUNode[K, V](key: key, value: value, expiresAt: expiresAt)
    cache.addToFront(node)
    cache.table[key] = node
    inc cache.size
  finally:
    release(cache.lock)

proc del*[K, V](cache: LRUCache[K, V], key: K) =
  acquire(cache.lock)
  try:
    if cache.table.hasKey(key):
      let node = cache.table[key]
      cache.removeNode(node)
      cache.table.del(key)
      dec cache.size
  finally:
    release(cache.lock)

proc clear*[K, V](cache: LRUCache[K, V]) =
  acquire(cache.lock)
  try:
    cache.head = nil
    cache.tail = nil
    cache.table.clear()
    cache.size = 0
  finally:
    release(cache.lock)

proc len*[K, V](cache: LRUCache[K, V]): int =
  acquire(cache.lock)
  try:
    result = cache.size
  finally:
    release(cache.lock)

proc hasKey*[K, V](cache: LRUCache[K, V], key: K): bool =
  cache.get(key).isSome
