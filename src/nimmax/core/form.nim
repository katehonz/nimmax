import std/[strutils, tables]
import ./types, ./exceptions, ./contenttype

proc parseMultipartBody*(body, boundary: string): FormPart =
  result.data = newTable[string, seq[string]]()
  result.files = newTable[string, seq[FormFile]]()

  let delimiter = "--" & boundary
  var pos = 0

  while pos < body.len:
    let startIdx = body.find(delimiter, pos)
    if startIdx == -1:
      break

    let afterDelimiter = startIdx + delimiter.len
    if afterDelimiter >= body.len:
      break

    if body[afterDelimiter] == '-' and afterDelimiter + 1 < body.len and
       body[afterDelimiter + 1] == '-':
      break

    var headerEnd: int
    if body[afterDelimiter] == '\r':
      headerEnd = body.find("\r\n\r\n", afterDelimiter)
    else:
      headerEnd = body.find("\n\n", afterDelimiter)

    if headerEnd == -1:
      break

    let headersStr = body[afterDelimiter ..< headerEnd]
    var contentStart: int
    if body[headerEnd] == '\r':
      contentStart = headerEnd + 4
    else:
      contentStart = headerEnd + 2

    let nextBoundary = body.find(delimiter, contentStart)
    if nextBoundary == -1:
      break

    var contentEnd = nextBoundary
    if contentEnd >= 2 and body[contentEnd - 2 .. contentEnd - 1] == "\r\n":
      contentEnd -= 2
    elif contentEnd >= 1 and body[contentEnd - 1] == '\n':
      contentEnd -= 1

    let content = body[contentStart ..< contentEnd]

    var name = ""
    var filename = ""
    var contentType = ""

    for line in headersStr.splitLines():
      let lowerLine = line.toLowerAscii()
      if lowerLine.startsWith("content-disposition:"):
        for param in line[line.find(':') + 1 .. ^1].split(';'):
          let kv = param.strip().split('=', 1)
          if kv.len == 2:
            let k = kv[0].strip().toLowerAscii()
            var v = kv[1].strip()
            if v.startsWith('"') and v.endsWith('"'):
              v = v[1 .. ^2]
            if k == "name":
              name = v
            elif k == "filename":
              filename = v
      elif lowerLine.startsWith("content-type:"):
        contentType = line[line.find(':') + 1 .. ^1].strip()

    if name.len > 0:
      if filename.len > 0:
        if not result.files.hasKey(name):
          result.files[name] = @[]
        result.files[name].add(FormFile(
          filename: filename,
          contentType: contentType,
          body: content
        ))
      else:
        if not result.data.hasKey(name):
          result.data[name] = @[]
        result.data[name].add(content)

    pos = nextBoundary

proc parseFormParams*(body: string, contentType: string): FormPart =
  let media = parseContentType(contentType)
  if media.isFormUrlEncoded:
    result.data = newTable[string, seq[string]]()
    result.files = newTable[string, seq[FormFile]]()
    for pair in body.split('&'):
      let parts = pair.split('=', 2)
      if parts.len >= 1:
        let key = decodeUrl(parts[0])
        let value = if parts.len == 2: decodeUrl(parts[1]) else: ""
        if not result.data.hasKey(key):
          result.data[key] = @[]
        result.data[key].add(value)
  elif media.isMultipart:
    let boundary = media.getBoundary()
    if boundary.len == 0:
      raise newFormParseError("Missing boundary in multipart content type")
    result = parseMultipartBody(body, boundary)
  else:
    result.data = newTable[string, seq[string]]()
    result.files = newTable[string, seq[FormFile]]()

proc getFormValue*(form: FormPart, key: string): string =
  if form.data.hasKey(key) and form.data[key].len > 0:
    form.data[key][0]
  else:
    ""

proc getFormValues*(form: FormPart, key: string): seq[string] =
  form.data.getOrDefault(key, @[])

proc getFormFile*(form: FormPart, key: string): FormFile =
  if form.files.hasKey(key) and form.files[key].len > 0:
    form.files[key][0]
  else:
    FormFile()

proc getFormFiles*(form: FormPart, key: string): seq[FormFile] =
  form.files.getOrDefault(key, @[])

proc hasFormField*(form: FormPart, key: string): bool =
  form.data.hasKey(key)

proc hasFormFile*(form: FormPart, key: string): bool =
  form.files.hasKey(key)
