import std/[strutils, random, times, tables]
import ./types

proc getHeader*(headers: HttpHeaders, key: string, default = ""): string =
  if headers.hasKey(key):
    $headers[key]
  else:
    default

proc randomString*(length: int = 32): string =
  randomize()
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  result = newString(length)
  for i in 0 ..< length:
    result[i] = chars[rand(chars.len - 1)]

proc randomBytes*(length: int): seq[byte] =
  result = newSeq[byte](length)
  for i in 0 ..< length:
    result[i] = byte(rand(255))

proc escapeHtmlContent*(s: string): string =
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '<': result.add("&lt;")
    of '>': result.add("&gt;")
    of '&': result.add("&amp;")
    of '"': result.add("&quot;")
    of '\'': result.add("&#x27;")
    else: result.add(c)

proc parseCookies*(cookieHeader: string): TableRef[string, string] =
  result = newTable[string, string]()
  if cookieHeader.len == 0:
    return
  for pair in cookieHeader.split(';'):
    let parts = pair.strip().split('=', 1)
    if parts.len == 2:
      tables.`[]=`(result, parts[0].strip(), parts[1].strip())

proc parseQueryParams*(query: string): TableRef[string, string] =
  result = newTable[string, string]()
  if query.len == 0:
    return
  for pair in query.split('&'):
    let parts = pair.split('=', 2)
    if parts.len >= 1:
      let key = decodeUrl(parts[0])
      let value = if parts.len == 2: decodeUrl(parts[1]) else: ""
      result[key] = value

proc currentTime*(): string =
  $now()

proc getContentType*(ext: string): string =
  case ext
  of ".html", ".htm": "text/html; charset=utf-8"
  of ".css": "text/css; charset=utf-8"
  of ".js": "application/javascript; charset=utf-8"
  of ".json": "application/json; charset=utf-8"
  of ".xml": "application/xml; charset=utf-8"
  of ".txt": "text/plain; charset=utf-8"
  of ".png": "image/png"
  of ".jpg", ".jpeg": "image/jpeg"
  of ".gif": "image/gif"
  of ".svg": "image/svg+xml"
  of ".ico": "image/x-icon"
  of ".woff": "font/woff"
  of ".woff2": "font/woff2"
  of ".ttf": "font/ttf"
  of ".pdf": "application/pdf"
  of ".zip": "application/zip"
  of ".gz": "application/gzip"
  else: "application/octet-stream"
