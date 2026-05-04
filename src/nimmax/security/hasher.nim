import std/[strutils, base64, sha1]
import ../core/utils

proc hmacSha1(key, message: string): string =
  const blockSize = 64
  var keyAdj = key
  if keyAdj.len > blockSize:
    keyAdj = $secureHash(keyAdj)
  if keyAdj.len < blockSize:
    keyAdj &= repeat('\0', blockSize - keyAdj.len)

  var oKeyPad = newString(blockSize)
  var iKeyPad = newString(blockSize)
  for i in 0 ..< blockSize:
    oKeyPad[i] = chr(ord(keyAdj[i]) xor 0x5c)
    iKeyPad[i] = chr(ord(keyAdj[i]) xor 0x36)

  let innerHash = $secureHash(iKeyPad & message)
  result = $secureHash(oKeyPad & innerHash)

proc pbkdf2HmacSha1(password, salt: string, iterations: int, keyLen: int): string =
  result = newStringOfCap(keyLen)
  var blockNum = 1
  while result.len < keyLen:
    var u = salt
    u.add(chr((blockNum shr 24) and 0xff))
    u.add(chr((blockNum shr 16) and 0xff))
    u.add(chr((blockNum shr 8) and 0xff))
    u.add(chr(blockNum and 0xff))
    var t = hmacSha1(password, u)
    var prev = t
    for i in 1 ..< iterations:
      prev = hmacSha1(password, prev)
      for j in 0 ..< t.len:
        t[j] = chr(ord(t[j]) xor ord(prev[j]))
    result.add(t)
    inc blockNum
  result.setLen(keyLen)

proc hashPassword*(password: string, salt = "", iterations = 260000): string =
  let actualSalt = if salt.len > 0: salt else: encode(randomBytes(16), safe = true)
  let hash = encode(pbkdf2HmacSha1(password, actualSalt, iterations, 32), safe = true)
  "$pbkdf2$" & $iterations & "$" & actualSalt & "$" & hash

proc verifyPassword*(password, hashed: string): bool =
  let parts = hashed.split('$')
  if parts.len != 5 or parts[1] != "pbkdf2":
    return false
  try:
    let iterations = parseInt(parts[2])
    let salt = parts[3]
    let expectedHash = hashPassword(password, salt, iterations)
    return expectedHash == hashed
  except ValueError:
    return false
