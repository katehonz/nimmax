import std/[json, tables, net]
import ./types, ./constants, ./utils

proc newSettings*(
  address = defaultAddress,
  port = defaultPort,
  debug = true,
  reusePort = true,
  secretKey = "",
  appName = defaultAppName,
  bufSize = defaultBufSize,
  shutdownTimeout = 30,
  data: JsonNode = nil
): Settings =
  let key = if secretKey.len > 0: secretKey else: randomString(defaultSecretKeyLength)
  result = Settings(
    address: address,
    port: port,
    debug: debug,
    reusePort: reusePort,
    secretKey: SecretKey(key),
    appName: appName,
    bufSize: bufSize,
    shutdownTimeout: shutdownTimeout,
    data: if data.isNil: newJObject() else: data
  )

proc loadSettings*(data: JsonNode): Settings =
  let prologue = data{"nimmax"}
  let secretKey = if prologue.isNil: randomString(defaultSecretKeyLength)
                  else: prologue{"secretKey"}.getStr(randomString(defaultSecretKeyLength))
  let appName = if prologue.isNil: defaultAppName
                else: prologue{"appName"}.getStr(defaultAppName)

  newSettings(
    address = data{"address"}.getStr(defaultAddress),
    port = Port(data{"port"}.getInt(int(defaultPort))),
    debug = data{"debug"}.getBool(true),
    reusePort = data{"reusePort"}.getBool(true),
    secretKey = secretKey,
    appName = appName,
    bufSize = data{"bufSize"}.getInt(defaultBufSize),
    shutdownTimeout = data{"shutdownTimeout"}.getInt(30),
    data = data
  )

proc loadSettings*(configPath: string): Settings =
  let content = readFile(configPath)
  let data = parseJson(content)
  loadSettings(data)

proc `[]`*(settings: Settings, key: string): JsonNode =
  if settings.data.isNil: return newJNull()
  settings.data{key}

proc `[]`*(settings: Settings, key: string, default: JsonNode): JsonNode =
  let val = settings[key]
  if val.isNil: default else: val

proc getStr*(settings: Settings, key: string, default = ""): string =
  let val = settings[key]
  if val.isNil: default else: val.getStr(default)

proc getInt*(settings: Settings, key: string, default = 0): int =
  let val = settings[key]
  if val.isNil: default else: val.getInt(default)

proc getBool*(settings: Settings, key: string, default = false): bool =
  let val = settings[key]
  if val.isNil: default else: val.getBool(default)

proc newGlobalScope*(settings: Settings): GlobalScope =
  GlobalScope(
    router: Router(
      routes: initTable[string, seq[RouteEntry]](),
      namedRoutes: initTable[string, RouteEntry]()
    ),
    settings: settings,
    appData: newTable[string, JsonNode]()
  )
