import std/[strutils, re, tables, options, times]

type
  ValidateResult* = object
    valid*: bool
    errors*: seq[string]

  Validator* = proc(value: string): Option[string] {.gcsafe.}

  FormValidator* = ref object
    rules*: TableRef[string, seq[Validator]]

proc newFormValidator*(): FormValidator =
  FormValidator(rules: newTable[string, seq[Validator]]())

proc addRule*(fv: FormValidator, field: string, validator: Validator) =
  if not fv.rules.hasKey(field):
    fv.rules[field] = @[]
  fv.rules[field].add(validator)

proc validate*(fv: FormValidator, data: TableRef[string, string]): ValidateResult =
  result.valid = true
  result.errors = @[]

  for field, validators in fv.rules:
    let value = data.getOrDefault(field, "")
    for validator in validators:
      let error = validator(value)
      if error.isSome:
        result.valid = false
        result.errors.add(field & ": " & error.get())
        break

proc validateForm*(fv: FormValidator, data: TableRef[string, string]): seq[string] =
  let res = fv.validate(data)
  res.errors

proc required*(msg = ""): Validator =
  let m = msg
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0:
      some(if m.len > 0: m else: "This field is required")
    else:
      none(string)

proc isInt*(msg = ""): Validator =
  let m = msg
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    try:
      discard parseInt(value)
      none(string)
    except ValueError:
      some(if m.len > 0: m else: "Must be an integer")

proc isFloat*(msg = ""): Validator =
  let m = msg
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    try:
      discard parseFloat(value)
      none(string)
    except ValueError:
      some(if m.len > 0: m else: "Must be a number")

proc isBool*(msg = ""): Validator =
  let m = msg
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    let lower = value.toLowerAscii()
    if lower in ["true", "false", "1", "0", "yes", "no", "on", "off"]:
      none(string)
    else:
      some(if m.len > 0: m else: "Must be a boolean value")

proc minValue*(minVal: float, msg = ""): Validator =
  let m = msg
  let mv = minVal
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    try:
      if parseFloat(value) < mv:
        some(if m.len > 0: m else: "Must be at least " & $mv)
      else:
        none(string)
    except ValueError:
      some("Must be a number")

proc maxValue*(maxVal: float, msg = ""): Validator =
  let m = msg
  let mv = maxVal
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    try:
      if parseFloat(value) > mv:
        some(if m.len > 0: m else: "Must be at most " & $mv)
      else:
        none(string)
    except ValueError:
      some("Must be a number")

proc minLength*(minLen: int, msg = ""): Validator =
  let m = msg
  let ml = minLen
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len > 0 and value.len < ml:
      some(if m.len > 0: m else: "Must be at least " & $ml & " characters")
    else:
      none(string)

proc maxLength*(maxLen: int, msg = ""): Validator =
  let m = msg
  let ml = maxLen
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len > ml:
      some(if m.len > 0: m else: "Must be at most " & $ml & " characters")
    else:
      none(string)

proc matchPattern*(pattern: string, msg = ""): Validator =
  let m = msg
  let p = pattern
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    if not value.match(re(p)):
      some(if m.len > 0: m else: "Invalid format")
    else:
      none(string)

proc isEmail*(msg = ""): Validator =
  matchPattern(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$",
               if msg.len > 0: msg else: "Must be a valid email address")

proc isUrl*(msg = ""): Validator =
  matchPattern(r"^https?://[^\s]+$",
               if msg.len > 0: msg else: "Must be a valid URL")

proc equals*(other: string, msg = ""): Validator =
  let m = msg
  let o = other
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value != o:
      some(if m.len > 0: m else: "Values do not match")
    else:
      none(string)

proc oneOf*(values: seq[string], msg = ""): Validator =
  let m = msg
  let v = values
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len > 0 and value notin v:
      some(if m.len > 0: m else: "Must be one of: " & v.join(", "))
    else:
      none(string)

proc notEmpty*(msg = ""): Validator =
  let m = msg
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.strip().len == 0:
      some(if m.len > 0: m else: "Must not be empty")
    else:
      none(string)

proc isAlpha*(msg = ""): Validator =
  let m = msg
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    for c in value:
      if not c.isAlphaAscii():
        return some(if m.len > 0: m else: "Must contain only letters")
    none(string)

proc isAlphanumeric*(msg = ""): Validator =
  let m = msg
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    for c in value:
      if not c.isAlphaNumeric():
        return some(if m.len > 0: m else: "Must contain only letters and numbers")
    none(string)

proc isAlphanumericUnderscore*(msg = ""): Validator =
  let m = msg
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    for c in value:
      if not c.isAlphaNumeric() and c != '_':
        return some(if m.len > 0: m else: "Must contain only letters, numbers, and underscores")
    none(string)

proc isHex*(msg = ""): Validator =
  matchPattern(r"^[0-9a-fA-F]+$",
               if msg.len > 0: msg else: "Must be a valid hex string")

proc isUUID*(version = 4, msg = ""): Validator =
  let m = msg
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    let uuidRegex = r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-" & $(version mod 10) &
                    r"[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
    if not value.match(re(uuidRegex)):
      some(if m.len > 0: m else: "Must be a valid UUID v" & $version)
    else:
      none(string)

proc isDate*(format: string, msg = ""): Validator =
  let m = msg
  let fmt = format
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    try:
      discard parse(value, fmt)
      none(string)
    except CatchableError:
      some(if m.len > 0: m else: "Must be a valid date in format " & fmt)

proc isIP*(version: range[4..6] = 4, msg = ""): Validator =
  let m = msg
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    let v4Regex = r"^(\d{1,3}\.){3}\d{1,3}$"
    let v6Regex = r"^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:)*::([0-9a-fA-F]{1,4}:)*[0-9a-fA-F]{1,4}$"
    let pattern = if version == 4: v4Regex else: v6Regex
    if not value.match(re(pattern)):
      some(if m.len > 0: m else: "Must be a valid IP address")
    else:
      none(string)

proc isCreditCard*(msg = ""): Validator =
  let m = msg
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    var digits: seq[int]
    for c in value:
      if c == ' ' or c == '-': continue
      if not c.isDigit():
        return some(if m.len > 0: m else: "Must be a valid credit card number")
      digits.add(ord(c) - ord('0'))
    if digits.len < 13:
      return some(if m.len > 0: m else: "Must be a valid credit card number")
    var sum = 0
    var alternate = false
    for i in countdown(digits.len - 1, 0):
      var n = digits[i]
      if alternate:
        n = n * 2
        if n > 9: n = n - 9
      sum += n
      alternate = not alternate
    if sum mod 10 != 0:
      some(if m.len > 0: m else: "Must be a valid credit card number")
    else:
      none(string)

proc isInRange*(minVal, maxVal: float, msg = ""): Validator =
  let m = msg
  let mv = minVal
  let xv = maxVal
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    try:
      let v = parseFloat(value)
      if v < mv or v > xv:
        some(if m.len > 0: m else: "Must be between " & $mv & " and " & $xv)
      else:
        none(string)
    except ValueError:
      some("Must be a number")

proc isInRange*(minVal, maxVal: int, msg = ""): Validator =
  let m = msg
  let mv = minVal
  let xv = maxVal
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len == 0: return none(string)
    try:
      let v = parseInt(value)
      if v < mv or v > xv:
        some(if m.len > 0: m else: "Must be between " & $mv & " and " & $xv)
      else:
        none(string)
    except ValueError:
      some("Must be a number")
