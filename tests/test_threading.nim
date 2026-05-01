import std/[unittest, asyncdispatch, httpcore, times, locks, strutils, options, atomics]
import nimmax/core/types
import nimmax/core/context
import nimmax/core/application
import nimmax/testing/mocking
import nimmax/cache

suite "Thread Safety Tests":
  test "basic thread creation and join works":
    var result = 0
    var thr: Thread[int]
    proc worker(id: int) {.thread.} =
      result = id * 2
    createThread(thr, worker, 10)
    joinThread(thr)
    check result == 20

  test "multiple threads can run concurrently":
    var counter = 0
    var lock: Lock
    initLock(lock)
    const numThreads = 4
    const iterations = 1000

    proc increment() {.thread.} =
      for i in 0..<iterations:
        acquire(lock)
        inc counter
        release(lock)

    var threads: array[numThreads, Thread[void]]
    for i in 0..<numThreads:
      createThread(threads[i], increment)
    for i in 0..<numThreads:
      joinThread(threads[i])

    check counter == numThreads * iterations

  test "thread-safe counter with atomic operations":
    var counter = 0
    const numThreads = 4
    const iterations = 1000

    proc incrementAtomic() {.thread.} =
      for i in 0..<iterations:
        atomicInc(counter)

    var threads: array[numThreads, Thread[void]]
    for i in 0..<numThreads:
      createThread(threads[i], incrementAtomic)
    for i in 0..<numThreads:
      joinThread(threads[i])

    check counter == numThreads * iterations

  test "LRU cache basic operations":
    var cache = initLRUCache[string, string](capacity = 100)
    cache.put("key1", "value1")
    let val = cache.get("key1")
    check val.isSome
    check val.get == "value1"

    cache.put("key2", "value2")
    let val2 = cache.get("key2")
    check val2.isSome
    check val2.get == "value2"

    check cache.len == 2

  test "LRU cache sequential access works":
    var cache = initLRUCache[string, int](capacity = 100)
    for i in 0..<100:
      cache.put("key" & $i, i)
    for i in 0..<100:
      let val = cache.get("key" & $i)
      check val.isSome
      check val.get == i

  test "LFU cache basic operations":
    var cache = initLFUCache[string, string](capacity = 100)
    cache.put("key1", "value1")
    let val = cache.get("key1")
    check val.isSome
    check val.get == "value1"

  test "LFU cache sequential access":
    var cache = initLFUCache[string, int](capacity = 100)
    for i in 0..<50:
      cache.put("k" & $i, i * 10)
    for i in 0..<50:
      let val = cache.get("k" & $i)
      check val.isSome
      check val.get == i * 10

suite "Concurrent Request Tests":
  test "mockApp handles multiple requests sequentially":
    let app = mockApp()
    var requestCount = 0

    proc handler(ctx: Context) {.async, gcsafe.} =
      inc requestCount
      ctx.text("count=" & $requestCount)

    app.get("/test", handler)

    for i in 0..<10:
      let ctx = app.runOnce(HttpGet, "/test")
      check ctx.response.code == Http200

    check requestCount == 10

  test "multiple route handlers work":
    let app = mockApp()

    proc handler1(ctx: Context) {.async, gcsafe.} =
      ctx.text("handler1")

    proc handler2(ctx: Context) {.async, gcsafe.} =
      ctx.text("handler2")

    app.get("/h1", handler1)
    app.get("/h2", handler2)

    for i in 0..<5:
      let ctx1 = app.runOnce(HttpGet, "/h1")
      let ctx2 = app.runOnce(HttpGet, "/h2")
      check ctx1.response.body == "handler1"
      check ctx2.response.body == "handler2"

  test "path parameters work with concurrent requests":
    let app = mockApp()

    proc handler(ctx: Context) {.async, gcsafe.} =
      let id = ctx.getPathParam("id")
      ctx.text("id=" & id)

    app.get("/user/{id}", handler)

    for i in @[1, 2, 3, 42, 100]:
      let ctx = app.runOnce(HttpGet, "/user/" & $i)
      check ctx.response.code == Http200
      check ctx.response.body == "id=" & $i

suite "Async Tests":
  test "async procedure can be awaited":
    proc asyncWorker(): Future[int] {.async.} =
      return 42

    let result = waitFor asyncWorker()
    check result == 42

  test "multiple async futures can run":
    proc asyncAdd(a, b: int): Future[int] {.async.} =
      return a + b

    let f1 = asyncAdd(1, 2)
    let f2 = asyncAdd(3, 4)
    let f3 = asyncAdd(5, 6)

    let results = waitFor all([f1, f2, f3])
    check results == @[3, 7, 11]

type
  ThreadArg = object
    cache: pointer
    startIdx: int
    count: int
    id: int

suite "LRU Cache Thread Safety":
  test "concurrent put from multiple threads":
    const numThreads = 4
    const keysPerThread = 250

    proc writerFn(arg: ThreadArg) {.thread.} =
      let cache = cast[LRUCache[string, int]](arg.cache)
      for i in 0..<arg.count:
        let key = "t" & $arg.id & "_k" & $i
        cache.put(key, arg.id * 1000 + i)

    var cache = initLRUCache[string, int](capacity = 2000)
    let cachePtr = cast[pointer](cache)

    var threads: array[numThreads, Thread[ThreadArg]]
    for i in 0..<numThreads:
      createThread(threads[i], writerFn, ThreadArg(cache: cachePtr, startIdx: i * keysPerThread, count: keysPerThread, id: i))
    for i in 0..<numThreads:
      joinThread(threads[i])

    var found = 0
    for t in 0..<numThreads:
      for i in 0..<keysPerThread:
        let key = "t" & $t & "_k" & $i
        let val = cache.get(key)
        if val.isSome:
          check val.get == t * 1000 + i
          inc found
    check found == numThreads * keysPerThread

  test "concurrent read and write from multiple threads":
    const numWriters = 2
    const numReaders = 2
    const iterations = 500

    proc writerFn(arg: ThreadArg) {.thread.} =
      let cache = cast[LRUCache[string, int]](arg.cache)
      for i in 0..<iterations:
        cache.put("shared_" & $i, i)

    proc readerFn(arg: ThreadArg) {.thread.} =
      let cache = cast[LRUCache[string, int]](arg.cache)
      for i in 0..<iterations:
        let val = cache.get("shared_" & $i)
        if val.isSome:
          check val.get == i

    var cache = initLRUCache[string, int](capacity = 2000)
    let cachePtr = cast[pointer](cache)

    var writerThreads: array[numWriters, Thread[ThreadArg]]
    var readerThreads: array[numReaders, Thread[ThreadArg]]
    for i in 0..<numWriters:
      createThread(writerThreads[i], writerFn, ThreadArg(cache: cachePtr))
    for i in 0..<numReaders:
      createThread(readerThreads[i], readerFn, ThreadArg(cache: cachePtr))
    for i in 0..<numWriters:
      joinThread(writerThreads[i])
    for i in 0..<numReaders:
      joinThread(readerThreads[i])

    check cache.len <= 2000

  test "concurrent put and del":
    const numThreads = 4
    const iterations = 300

    proc putDelFn(arg: ThreadArg) {.thread.} =
      let cache = cast[LRUCache[string, int]](arg.cache)
      for i in 0..<iterations:
        let key = "pd_" & $arg.id & "_" & $i
        cache.put(key, i)
        cache.del(key)

    var cache = initLRUCache[string, int](capacity = 1000)
    let cachePtr = cast[pointer](cache)

    var threads: array[numThreads, Thread[ThreadArg]]
    for i in 0..<numThreads:
      createThread(threads[i], putDelFn, ThreadArg(cache: cachePtr, id: i))
    for i in 0..<numThreads:
      joinThread(threads[i])

    for t in 0..<numThreads:
      for i in 0..<iterations:
        check cache.get("pd_" & $t & "_" & $i).isNone

suite "LFU Cache Thread Safety":
  test "concurrent put from multiple threads":
    const numThreads = 4
    const keysPerThread = 250

    proc writerFn(arg: ThreadArg) {.thread.} =
      let cache = cast[LFUCache[string, int]](arg.cache)
      for i in 0..<arg.count:
        let key = "t" & $arg.id & "_k" & $i
        cache.put(key, arg.id * 1000 + i)

    var cache = initLFUCache[string, int](capacity = 2000)
    let cachePtr = cast[pointer](cache)

    var threads: array[numThreads, Thread[ThreadArg]]
    for i in 0..<numThreads:
      createThread(threads[i], writerFn, ThreadArg(cache: cachePtr, startIdx: i * keysPerThread, count: keysPerThread, id: i))
    for i in 0..<numThreads:
      joinThread(threads[i])

    var found = 0
    for t in 0..<numThreads:
      for i in 0..<keysPerThread:
        let key = "t" & $t & "_k" & $i
        let val = cache.get(key)
        if val.isSome:
          check val.get == t * 1000 + i
          inc found
    check found == numThreads * keysPerThread

  test "concurrent read and write from multiple threads":
    const numWriters = 2
    const numReaders = 2
    const iterations = 500

    proc writerFn(arg: ThreadArg) {.thread.} =
      let cache = cast[LFUCache[string, int]](arg.cache)
      for i in 0..<iterations:
        cache.put("shared_" & $i, i)

    proc readerFn(arg: ThreadArg) {.thread.} =
      let cache = cast[LFUCache[string, int]](arg.cache)
      for i in 0..<iterations:
        let val = cache.get("shared_" & $i)
        if val.isSome:
          check val.get == i

    var cache = initLFUCache[string, int](capacity = 2000)
    let cachePtr = cast[pointer](cache)

    var writerThreads: array[numWriters, Thread[ThreadArg]]
    var readerThreads: array[numReaders, Thread[ThreadArg]]
    for i in 0..<numWriters:
      createThread(writerThreads[i], writerFn, ThreadArg(cache: cachePtr))
    for i in 0..<numReaders:
      createThread(readerThreads[i], readerFn, ThreadArg(cache: cachePtr))
    for i in 0..<numWriters:
      joinThread(writerThreads[i])
    for i in 0..<numReaders:
      joinThread(readerThreads[i])

    check cache.len <= 2000

  test "concurrent put and del":
    const numThreads = 4
    const iterations = 300

    proc putDelFn(arg: ThreadArg) {.thread.} =
      let cache = cast[LFUCache[string, int]](arg.cache)
      for i in 0..<iterations:
        let key = "pd_" & $arg.id & "_" & $i
        cache.put(key, i)
        cache.del(key)

    var cache = initLFUCache[string, int](capacity = 1000)
    let cachePtr = cast[pointer](cache)

    var threads: array[numThreads, Thread[ThreadArg]]
    for i in 0..<numThreads:
      createThread(threads[i], putDelFn, ThreadArg(cache: cachePtr, id: i))
    for i in 0..<numThreads:
      joinThread(threads[i])

    for t in 0..<numThreads:
      for i in 0..<iterations:
        check cache.get("pd_" & $t & "_" & $i).isNone

suite "Server Shutdown Safety":
  test "atomic shutdown flag works":
    var flag: Atomic[bool]
    flag.store(false)
    check flag.load() == false
    flag.store(true)
    check flag.load() == true
