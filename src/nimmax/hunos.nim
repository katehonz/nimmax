## NimMax Hunos Backend Entry Point
##
## Provides the full NimMax API backed by the Hunos multi-threaded
## HTTP/1.1 + HTTP/2 + WebSocket server.
##
## Usage:
##   import nimmax/hunos
##
##   proc hello(ctx: Context) {.async.} =
##     ctx.html("<h1>Hello from Hunos backend!</h1>")
##
##   let app = newApp()
##   app.get("/", hello)
##   app.runHunos(port = Port(8080))

when not defined(nimmaxHunos):
  {.error: "Hunos backend requires the Hunos package. Install with: nimble install hunos, then compile with -d:nimmaxHunos. If you don't need the Hunos backend, use 'import nimmax' instead.".}

import nimmax/core/types
import nimmax/core/constants
import nimmax/core/exceptions
import nimmax/core/utils
import nimmax/core/contenttype
import nimmax/core/form
import nimmax/core/response
import nimmax/core/request
import nimmax/core/pages
import nimmax/core/settings
import nimmax/core/configure
import nimmax/core/route
import nimmax/core/middleware
import nimmax/core/context
import nimmax/core/group
import nimmax/core/application
import nimmax/core/hunos_backend
import nimmax/core/hunos_websocket
import nimmax/websocket/websocket as wsBase
export types
export constants
export exceptions
export utils
export contenttype
export form
export response
export request
export pages
export settings
export configure
export route
export middleware
export context
export group
export application
export hunos_backend
export hunos_websocket
export wsBase.WebSocket
export hunos_websocket.HunosWebSocket
export hunos_backend.registerHunosWs
