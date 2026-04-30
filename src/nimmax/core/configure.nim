import std/[os, json, tables, strutils]
import ./types, ./settings

type
  Env* = ref object
    data*: TableRef[string, string]

proc loadEnv*(path = ".env"): Env =
  result = Env(data: newTable[string, string]())
  if not fileExists(path):
    return
  for line in readFile(path).splitLines():
    let stripped = line.strip()
    if stripped.len == 0 or stripped.startsWith('#'):
      continue
    let parts = stripped.split('=', 1)
    if parts.len == 2:
      result.data[parts[0].strip()] = parts[1].strip()

proc get*(env: Env, key: string, default = ""): string =
  env.data.getOrDefault(key, default)

proc getOrDefault*(env: Env, key: string, default = ""): string =
  env.data.getOrDefault(key, default)

proc contains*(env: Env, key: string): bool =
  env.data.hasKey(key)

proc loadConfig*(configDir = ".config", envName = ""): JsonNode =
  let env = if envName.len > 0: envName
            else: getEnv("NIMMAX_ENV", "config")
  let configPath = configDir / ("config." & env & ".json")
  let defaultPath = configDir / "config.json"

  if fileExists(configPath):
    return parseFile(configPath)
  elif fileExists(defaultPath):
    return parseFile(defaultPath)
  else:
    return newJObject()

proc newAppFromConfig*(configDir = ".config", envName = ""): Settings =
  let config = loadConfig(configDir, envName)
  loadSettings(config)
