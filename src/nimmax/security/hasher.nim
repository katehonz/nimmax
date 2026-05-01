import std/[strutils, base64]
import ../core/utils

proc pbkdf2Simple*(password, salt: string, iterations = 260000, keyLen = 32): string =
  var derived = password & salt
  for i in 0 ..< iterations:
    var hash = 0
    for c in derived:
      hash = (hash * 31 + ord(c)) and 0x7fffffff
    derived = $hash & password & salt
  encode(derived[0 ..< min(keyLen, derived.len)], safe = true)

proc hashPassword*(password: string, salt = "", iterations = 260000): string =
  let actualSalt = if salt.len > 0: salt else: encode(randomString(16), safe = true)
  let hash = pbkdf2Simple(password, actualSalt, iterations)
  "$pbkdf2$" & $iterations & "$" & actualSalt & "$" & hash

proc verifyPassword*(password, hashed: string): bool =
  let parts = hashed.split('$')
  if parts.len != 5 or parts[1] != "pbkdf2":
    return false
  let iterations = parseInt(parts[2])
  let salt = parts[3]
  let expectedHash = hashPassword(password, salt, iterations)
  return expectedHash == hashed
