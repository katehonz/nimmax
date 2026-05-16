# Package
version       = "1.2.0"
author        = "NimMax Contributors"
description   = "NimMax - A modern, high-performance web framework for Nim"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"
requires "zippy >= 0.10.0"

# Optional dependencies (install only if needed):
#   nimble install hunos   # For the Hunos multi-threaded backend

# Tasks
task test, "Run the tests":
  exec "nim c -r --threads:on --mm:arc -p:src tests/test_routes.nim"
  exec "nim c -r --threads:on --mm:arc -p:src tests/test_middleware.nim"
  exec "nim c -r --threads:on --mm:arc -p:src tests/test_threading.nim"
  exec "nim c -r --threads:on --mm:arc -p:src tests/test_websocket.nim"
  # Hunos backend test requires: nimble install hunos
  when false:
    exec "nim c -r --threads:on --mm:arc -p:src tests/test_hunos_backend.nim"

task docs, "Generate documentation":
  exec "nim doc --project --outdir:docs src/nimmax.nim"
