# Validation

NimMax includes a declarative form validation system with 15+ built-in validators.

## Basic Usage

```nim
import nimmax/validater

# Create a validator
let form = newFormValidator()

# Add rules
form.addRule("email", required())
form.addRule("email", isEmail())
form.addRule("name", required())
form.addRule("name", minLength(2))
form.addRule("name", maxLength(100))
form.addRule("age", isInt())
form.addRule("age", minValue(0))
form.addRule("age", maxValue(150))

# Validate POST data
app.post("/register", proc(ctx: Context) {.async.} =
  let errors = form.validateForm(ctx.request.postParams)
  if errors.len > 0:
    ctx.json(%*{"errors": errors}, Http422)
    return

  # Process valid data
  let email = ctx.getPostParam("email")
  let name = ctx.getPostParam("name")
  ctx.json(%*{"status": "registered", "email": email})
)
```

## ValidateResult

The `validate` method returns a structured result:

```nim
let result = form.validate(ctx.request.postParams)
if not result.valid:
  for error in result.errors:
    echo error
  # "email: This field is required"
  # "age: Must be at least 0"
```

## Built-in Validators

### Required

```nim
required()                # "This field is required"
required("Custom message") # custom error message
```

### Type Validators

```nim
isInt()       # Must be a valid integer
isFloat()     # Must be a valid float
isBool()      # Must be a boolean (true/false/1/0/yes/no)
isEmail()     # Must be a valid email address
isUrl()       # Must be a valid URL (http:// or https://)
```

### Numeric Range

```nim
minValue(0)           # Minimum value: 0
maxValue(150)         # Maximum value: 150
```

### String Length

```nim
minLength(2)          # At least 2 characters
maxLength(100)        # At most 100 characters
```

### Pattern Matching

```nim
matchPattern("^[A-Z]{2}\\d{4}$")   # Custom regex
matchPattern("^[A-Z]{2}\\d{4}$", "Must be 2 letters followed by 4 digits")
```

### Equality

```nim
equals("expected_value")              # Must equal exact string
equals(confirmPassword, "Passwords must match")  # with custom message
```

### One Of

```nim
oneOf(@["red", "green", "blue"])      # Must be one of the listed values
oneOf(@["admin", "user", "guest"], "Invalid role")
```

## Custom Validators

Create your own validators by writing a proc that takes a string and returns `Option[string]`:

```nim
proc noSpaces(msg = ""): Validator =
  let m = msg
  result = proc(value: string): Option[string] {.gcsafe.} =
    if ' ' in value:
      some(if m.len > 0: m else: "Must not contain spaces")
    else:
      none(string)

# Use it
form.addRule("username", noSpaces())
```

### Composite Validator

```nim
proc strongPassword(): Validator =
  result = proc(value: string): Option[string] {.gcsafe.} =
    if value.len < 8:
      return some("Password must be at least 8 characters")
    if not value.contains({'A'..'Z'}):
      return some("Password must contain an uppercase letter")
    if not value.contains({'a'..'z'}):
      return some("Password must contain a lowercase letter")
    if not value.contains({'0'..'9'}):
      return some("Password must contain a digit")
    none(string)

form.addRule("password", required())
form.addRule("password", strongPassword())
```

## Validating JSON Data

```nim
proc registerHandler(ctx: Context) {.async.} =
  let data = parseJson(ctx.request.body)

  # Convert JSON to string table for validation
  var params = newTable[string, string]()
  for key, val in data:
    params[key] = val.getStr()

  let errors = form.validateForm(params)
  if errors.len > 0:
    ctx.json(%*{"errors": errors}, Http422)
    return
```

## Example: Registration Form

```nim
import nimmax, nimmax/validater, json

let registerForm = newFormValidator()
registerForm.addRule("username", required())
registerForm.addRule("username", minLength(3))
registerForm.addRule("username", maxLength(30))
registerForm.addRule("email", required())
registerForm.addRule("email", isEmail())
registerForm.addRule("password", required())
registerForm.addRule("password", minLength(8))
registerForm.addRule("confirm_password", required())

app.post("/register", proc(ctx: Context) {.async.} =
  let errors = registerForm.validateForm(ctx.request.postParams)

  if ctx.getPostParam("password") != ctx.getPostParam("confirm_password"):
    errors.add("confirm_password: Passwords do not match")

  if errors.len > 0:
    ctx.json(%*{"errors": errors}, Http422)
    return

  # Create user...
  ctx.json(%*{"status": "ok"}, Http201)
)
```
