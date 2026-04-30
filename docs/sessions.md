# Sessions

NimMax provides session management with pluggable backends.

## Session Backends

### In-Memory Sessions

Sessions are stored in server memory. Fastest option, but sessions are lost on server restart.

```nim
app.use(sessionMiddleware(
  backend = sbMemory,
  sessionName = "nimmax_session",
  maxAge = 86400,        # 24 hours
  path = "/",
  httpOnly = true,
  secure = false,
  sameSite = "Lax"
))
```

### Signed Cookie Sessions

Session data is serialized, signed, and stored directly in the cookie. No server-side storage needed.

```nim
app.use(sessionMiddleware(
  backend = sbSignedCookie,
  secretKey = SecretKey("my-secret-key"),
  sessionName = "nimmax_session",
  maxAge = 86400
))
```

**Pros**: No server-side storage, horizontally scalable.
**Cons**: Cookie size limit (~4KB), data visible (though signed) to client.

## Using Sessions

### Reading and Writing

```nim
# Set session values
app.post("/login", proc(ctx: Context) {.async.} =
  let username = ctx.getPostParam("username")
  let password = ctx.getPostParam("password")

  if authenticate(username, password):
    ctx.session["user"] = username
    ctx.session["role"] = "admin"
    ctx.session["login_time"] = $now()
    ctx.redirect("/dashboard")
  else:
    ctx.html("<p>Invalid credentials</p>", Http401)
)

# Read session values
app.get("/dashboard", proc(ctx: Context) {.async.} =
  let user = ctx.session["user"]
  if user.len == 0:
    ctx.redirect("/login")
    return
  ctx.html("<h1>Welcome, " & escapeHtml(user) & "!</h1>")
)
```

### Session Operations

```nim
# Get a value
let value = ctx.session["key"]

# Set a value
ctx.session["key"] = "value"

# Delete a value
ctx.session.del("key")

# Check if key exists
if ctx.session.hasKey("user"):
  discard

# Get length
let count = ctx.session.len()

# Clear all session data
ctx.session.clear()

# Iterate over all pairs
for (key, value) in ctx.session.pairs():
  echo key & " = " & value
```

### Session Properties

```nim
ctx.session.newCreated   # true if this is a new session
ctx.session.modified     # true if session data was changed
ctx.session.accessed     # true if session data was read
```

## Flash Messages

Flash messages are one-time messages stored in the session. They are automatically removed after reading.

### Setting Flash Messages

```nim
app.post("/create", proc(ctx: Context) {.async.} =
  # ... create item ...
  ctx.flash("Item created successfully!", flSuccess)
  ctx.redirect("/items")
)
```

### Reading Flash Messages

```nim
app.get("/items", proc(ctx: Context) {.async.} =
  let messages = ctx.getFlashedMsgs()
  var html = "<ul>"
  for msg in messages:
    html &= "<li>" & escapeHtml(msg) & "</li>"
  html &= "</ul>"
  # ... render page with messages ...
)
```

### Flash Message Categories

```nim
# Set with category
ctx.flash("Item created!", flSuccess)    # "success"
ctx.flash("Check your email", flInfo)    # "info"
ctx.flash("Name is required", flWarning) # "warning"
ctx.flash("Permission denied", flError)  # "error"

# Read with categories
let messages = ctx.getFlashedMsgsWithCategory()
for (level, msg) in messages:
  case level
  of flSuccess: echo "[SUCCESS] " & msg
  of flInfo:    echo "[INFO] " & msg
  of flWarning: echo "[WARNING] " & msg
  of flError:   echo "[ERROR] " & msg
```

### Flash Message HTML Helper

```nim
proc renderFlashMessages(ctx: Context): string =
  result = ""
  let messages = ctx.getFlashedMsgsWithCategory()
  for (level, msg) in messages:
    let cssClass = case level
      of flSuccess: "alert-success"
      of flInfo:    "alert-info"
      of flWarning: "alert-warning"
      of flError:   "alert-error"
    result &= """<div class="""" & cssClass & """">""" & escapeHtml(msg) & "</div>"
```

## Logout

```nim
app.get("/logout", proc(ctx: Context) {.async.} =
  ctx.session.clear()
  ctx.deleteCookie("nimmax_session")
  ctx.redirect("/login")
)
```
