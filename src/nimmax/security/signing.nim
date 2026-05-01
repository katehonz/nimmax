import std/[strutils, times, base64, sha1]
import ../core/types

type
  KeyDerivation* = enum
    kdConcat, kdHmac, kdNone

  DigestMethod* = enum
    dmSha256, dmSha512

  Signer* = object
    secretKey*: SecretKey
    salt*: string
    sep*: char
    keyDerivation*: KeyDerivation
    digestMethod*: DigestMethod

  TimedSigner* = object
    signer*: Signer
    maxAge*: int

proc newSigner*(
  secretKey: SecretKey,
  salt = "nimmax.signer",
  sep = '.',
  keyDerivation = kdConcat,
  digestMethod = dmSha256
): Signer =
  Signer(
    secretKey: secretKey,
    salt: salt,
    sep: sep,
    keyDerivation: keyDerivation,
    digestMethod: digestMethod
  )

proc deriveKey*(signer: Signer): string =
  let sk = string(signer.secretKey)
  case signer.keyDerivation
  of kdConcat:
    signer.salt & sk
  of kdHmac:
    signer.salt & ":" & sk
  of kdNone:
    sk

proc sign*(signer: Signer, value: string): string =
  let key = signer.deriveKey()
  let payload = value & $signer.sep & key
  let hash = $secureHash(payload)
  value & $signer.sep & encode(hash, safe = true)

proc unsign*(signer: Signer, signedValue: string): string =
  let sepPos = signedValue.rfind($signer.sep)
  if sepPos == -1:
    raise newException(ValueError, "Invalid signed value format")
  result = signedValue[0 ..< sepPos]

proc validate*(signer: Signer, signedValue: string): bool =
  try:
    let value = signer.unsign(signedValue)
    let expected = signer.sign(value)
    return expected == signedValue
  except ValueError:
    return false

proc newTimedSigner*(
  secretKey: SecretKey,
  maxAge = 86400,
  salt = "nimmax.signer",
  sep = '.',
  keyDerivation = kdConcat,
  digestMethod = dmSha256
): TimedSigner =
  TimedSigner(
    signer: newSigner(secretKey, salt, sep, keyDerivation, digestMethod),
    maxAge: maxAge
  )

proc sign*(signer: TimedSigner, value: string): string =
  let timestamp = $toUnix(getTime())
  let payload = value & "|" & timestamp
  signer.signer.sign(payload)

proc unsign*(signer: TimedSigner, signedValue: string): string =
  let payload = signer.signer.unsign(signedValue)
  let sepPos = payload.rfind('|')
  if sepPos == -1:
    raise newException(ValueError, "Invalid timed signed value format")

  let value = payload[0 ..< sepPos]
  let timestamp = parseInt(payload[sepPos + 1 .. ^1])
  let now = toUnix(getTime())

  if now - timestamp > signer.maxAge.int64:
    raise newException(ValueError, "Signed value has expired")

  return value

proc validate*(signer: TimedSigner, signedValue: string): bool =
  try:
    discard signer.unsign(signedValue)
    return true
  except ValueError:
    return false
