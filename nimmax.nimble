# Package
version       = "1.1.0"
author        = "NimMax Contributors"
description   = "NimMax - A modern, high-performance web framework for Nim"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"
requires "zippy >= 0.10.0"
requires "hunos >= 1.2.0"

# Tasks
task test, "Run the tests":
  exec "nim c -r --threads:on --mm:arc -p:src tests/test_routes.nim"
  exec "nim c -r --threads:on --mm:arc -p:src tests/test_middleware.nim"
  exec "nim c -r --threads:on --mm:arc -p:src tests/test_threading.nim"
  exec "nim c -r --threads:on --mm:arc -p:src tests/test_websocket.nim"
  exec "nim c -r --threads:on --mm:arc -p:src tests/test_hunos_backend.nim"

task docs, "Generate documentation":
  exec "nim doc --project --outdir:docs src/nimmax.nim"
