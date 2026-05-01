# Package
version       = "1.0.0"
author        = "NimMax Contributors"
description   = "NimMax - A modern, high-performance web framework for Nim"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"

# Tasks
task test, "Run the tests":
  exec "nim c -r tests/test_routes.nim"
  exec "nim c -r tests/test_middleware.nim"

task docs, "Generate documentation":
  exec "nim doc --project --outdir:docs src/nimmax.nim"
