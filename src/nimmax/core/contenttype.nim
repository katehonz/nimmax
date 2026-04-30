import std/[strutils, tables]
import ./types

type
  MediaType* = object
    mainType*: string
    subType*: string
    params*: TableRef[string, string]

proc parseContentType*(headerValue: string): MediaType =
  result.params = newTable[string, string]()
  if headerValue.len == 0:
    result.mainType = "application"
    result.subType = "octet-stream"
    return

  let parts = headerValue.split(';')
  let mimeParts = parts[0].strip().split('/', 1)
  if mimeParts.len == 2:
    result.mainType = mimeParts[0].strip().toLowerAscii()
    result.subType = mimeParts[1].strip().toLowerAscii()
  else:
    result.mainType = parts[0].strip().toLowerAscii()
    result.subType = ""

  for i in 1 ..< parts.len:
    let paramParts = parts[i].strip().split('=', 1)
    if paramParts.len == 2:
      result.params[paramParts[0].strip().toLowerAscii()] = paramParts[1].strip()

proc getCharset*(media: MediaType): string =
  media.params.getOrDefault("charset", "utf-8")

proc getBoundary*(media: MediaType): string =
  media.params.getOrDefault("boundary", "")

proc isMultipart*(media: MediaType): bool =
  media.mainType == "multipart" and media.subType == "form-data"

proc isFormUrlEncoded*(media: MediaType): bool =
  media.mainType == "application" and media.subType == "x-www-form-urlencoded"

proc isJson*(media: MediaType): bool =
  media.mainType == "application" and
  (media.subType == "json" or media.subType.endsWith("+json"))
