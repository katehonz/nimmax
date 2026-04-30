# Configuration

NimMax supports multiple configuration methods that can be combined.

## Programmatic Configuration

Create settings directly in code:

```nim
let settings = newSettings(
  address = "0.0.0.0",
  port = Port(8080),
  debug = true,
  reusePort = true,
  secretKey = "my-secret-key",
  appName = "MyApp",
  bufSize = 40960,
  data = %*{"custom_key": "custom_value"}
)

let app = newApp(settings = settings)
```

### Settings Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `address` | `string` | `"0.0.0.0"` | Bind address |
| `port` | `Port` | `8080` | Listen port |
| `debug` | `bool` | `true` | Enable debug mode |
| `reusePort` | `bool` | `true` | Allow port reuse |
| `secretKey` | `SecretKey` | random | Cryptographic secret |
| `appName` | `string` | `"NimMax"` | Application name |
| `bufSize` | `int` | `40960` | Max request body size |
| `data` | `JsonNode` | `{}` | Custom data |

## JSON Configuration

### From File

Create `.config/config.json`:

```json
{
  "address": "0.0.0.0",
  "port": 8080,
  "debug": true,
  "reusePort": true,
  "bufSize": 40960,
  "nimmax": {
    "secretKey": "change-me-in-production",
    "appName": "MyApp"
  }
}
```

Load it:

```nim
let settings = loadSettings(".config/config.json")
let app = newApp(settings = settings)
```

### Per-Environment Configs

Create separate config files for each environment:

```
.config/
  config.json               # default
  config.debug.json         # development
  config.production.json    # production
  config.staging.json       # staging
```

Set the environment:

```bash
# Via environment variable
export NIMMAX_ENV=production
nim c -r src/app.nim
```

Or programmatically:

```nim
let settings = newAppFromConfig(".config", "production")
```

## Environment Variables

### .env Files

Create a `.env` file:

```
# Database
DATABASE_URL=postgres://user:pass@localhost:5432/mydb
DATABASE_POOL_SIZE=10

# API Keys
STRIPE_SECRET_KEY=sk_test_...
SENDGRID_API_KEY=SG....

# App Settings
APP_PORT=3000
APP_DEBUG=true
```

Load and use:

```nim
import nimmax/configure

let env = loadEnv()  # loads from ".env" by default

let dbUrl = env.get("DATABASE_URL")
let poolSize = parseInt(env.get("DATABASE_POOL_SIZE", "5"))
let stripeKey = env.get("STRIPE_SECRET_KEY")
let port = Port(parseInt(env.get("APP_PORT", "8080")))

# Check if a key exists
if "SENDGRID_API_KEY" in env:
  echo "Email service configured"
```

### System Environment Variables

```nim
import std/envvars

let dbUrl = getEnv("DATABASE_URL")
let port = Port(parseInt(getEnv("APP_PORT", "8080")))
```

### With Prefix

Use a prefix to avoid conflicts:

```bash
export MYAPP_DATABASE_URL=postgres://...
export MYAPP_SECRET_KEY=...
```

```nim
const prefix = "MYAPP_"
let dbUrl = getEnv(prefix & "DATABASE_URL")
```

## Custom Settings Data

Store arbitrary configuration in the `data` field:

```nim
let settings = newSettings(data = %*{
  "database": {
    "host": "localhost",
    "port": 5432,
    "name": "mydb"
  },
  "redis": {
    "host": "localhost",
    "port": 6379
  },
  "features": {
    "registration": true,
    "maintenance_mode": false
  }
})
```

Access via the Settings object:

```nim
let dbHost = settings.getStr("database", "localhost")
let dbPort = settings.getInt("database", 5432)
let isDebug = settings.getBool("debug", false)

# Direct JSON access
let dbConfig = settings["database"]
let redisHost = settings["redis"]["host"].getStr()
```

## Application Data

Store runtime data accessible from any handler:

```nim
let app = newApp()

# Set app-wide data
app["db_pool"] = %*poolSize
app["cache_enabled"] = %true

# Access from handlers
app.get("/status", proc(ctx: Context) {.async.} =
  let cacheEnabled = ctx.gScope.appData["cache_enabled"].getBool()
  ctx.json(%*{"cache": cacheEnabled})
)
```

## Accessing Settings from Handlers

```nim
proc handler(ctx: Context) {.async.} =
  let settings = ctx.getSettings()
  let isDebug = settings.debug
  let appName = settings.appName

  if isDebug:
    ctx.response.headers["X-Debug"] = "true"
```

## Production Configuration Example

```json
{
  "address": "0.0.0.0",
  "port": 8080,
  "debug": false,
  "reusePort": true,
  "bufSize": 1048576,
  "nimmax": {
    "secretKey": "long-random-string-from-env",
    "appName": "MyApp"
  }
}
```

```nim
import nimmax, nimmax/configure, std/envvars

proc main() =
  let env = loadEnv()
  let config = loadConfig(".config", getEnv("NIMMAX_ENV", "production"))
  let settings = loadSettings(config)

  # Override secret key from environment
  settings.secretKey = SecretKey(getEnv("SECRET_KEY", $settings.secretKey))

  let app = newApp(settings = settings)
  app.use(loggingMiddleware())

  if settings.debug:
    app.use(debugRequestMiddleware())

  # ... register routes ...
  app.run()
```
