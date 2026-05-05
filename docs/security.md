# Security

NimMax provides several security features out of the box.

## CSRF Protection

Cross-Site Request Forgery protection using the double-submit cookie pattern.

### Setup

```nim
app.use(csrfMiddleware())
```

### In Templates

Generate a hidden input field with the CSRF token:

```nim
app.get("/form", proc(ctx: Context) {.async.} =
  let csrfInput = ctx.csrfTokenInput()
  ctx.html("""
    <form method="POST" action="/submit">
      """ & csrfInput & """
      <input type="text" name="name">
      <button type="submit">Submit</button>
    </form>
  """)
)
```

### AJAX Requests

For AJAX/SPA applications, send the token in a header:

```javascript
// Read the CSRF cookie
const token = document.cookie
  .split('; ')
  .find(row => row.startsWith('nimmax_csrf='))
  .split('=')[1];

// Send in header
fetch('/api/data', {
  method: 'POST',
  headers: {
    'X-CSRF-Token': token,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({key: 'value'})
});
```

### Configuration

```nim
app.use(csrfMiddleware(
  tokenName = "csrf_token",     # form field / header name
  cookieName = "csrf_cookie"    # cookie name
))
```

## CORS (Cross-Origin Resource Sharing)

Control which origins can access your API.

### Allow All Origins (Development)

```nim
app.use(corsMiddleware(
  allowOrigins = @["*"],
  allowMethods = @["GET", "POST", "PUT", "DELETE"],
  allowHeaders = @["Content-Type", "Authorization"]
))
```

### Specific Origins (Production)

```nim
app.use(corsMiddleware(
  allowOrigins = @["https://example.com", "https://app.example.com"],
  allowMethods = @["GET", "POST", "PUT", "DELETE", "PATCH"],
  allowHeaders = @["Content-Type", "Authorization", "X-Requested-With"],
  exposeHeaders = @["X-Total-Count", "X-Page-Count"],
  allowCredentials = true,
  maxAge = 3600
))
```

### Exclude Paths

Skip CORS for certain endpoints:

```nim
app.use(corsMiddleware(
  allowOrigins = @["*"],
  excludePaths = @["/health", "/metrics", "/internal"]
))
```

## Basic Authentication

HTTP Basic Authentication for protected areas.

```nim
proc verifyCredentials(username, password: string): bool {.gcsafe.} =
  # In production, use hashed passwords from a database
  return username == "admin" and password == "secure-password"

# Protect all routes
app.use(basicAuthMiddleware("Admin Area", verifyCredentials))

# Or protect specific routes via groups
let admin = app.newGroup("/admin", middlewares = @[
  basicAuthMiddleware("Admin", verifyCredentials)
])
admin.get("/dashboard", dashboardHandler)
```

## Password Hashing

Secure password hashing using PBKDF2.

```nim
import nimmax/security

# Hash a password
let hashed = hashPassword("user-password")
# Returns: "$pbkdf2$260000$salt$hash"

# Verify a password
let isValid = verifyPassword("user-password", hashed)  # true
let isInvalid = verifyPassword("wrong-password", hashed)  # false
```

### In a Registration/Login Flow

```nim
import nimmax/security

# Registration
app.post("/register", proc(ctx: Context) {.async.} =
  let username = ctx.getPostParam("username")
  let password = ctx.getPostParam("password")

  let hashed = hashPassword(password)
  # Store username + hashed in database...

  ctx.json(%*{"status": "registered"})
)

# Login
app.post("/login", proc(ctx: Context) {.async.} =
  let username = ctx.getPostParam("username")
  let password = ctx.getPostParam("password")

  let storedHash = getHashFromDatabase(username)
  if verifyPassword(password, storedHash):
    ctx.session["user"] = username
    ctx.redirect("/dashboard")
  else:
    ctx.html("<p>Invalid credentials</p>", Http401)
)
```

## Cryptographic Signing

Sign data to ensure integrity and authenticity.

### Basic Signing

```nim
import nimmax/security

let signer = newSigner(SecretKey("my-secret-key"))

# Sign data
let signed = signer.sign("user-id:42")
# Returns: "user-id:42.signature"

# Verify signature
let isValid = signer.validate(signed)  # true

# Extract original data
let original = signer.unsign(signed)  # "user-id:42"

# Tampered data fails validation
let tampered = "user-id:42.fake-sig"
let isTampered = signer.validate(tampered)  # false
```

### Timed Signing (Expiration)

Data signatures that expire after a configurable time:

```nim
let signer = newTimedSigner(SecretKey("my-key"), maxAge = 3600)  # 1 hour

# Sign with timestamp
let signed = signer.sign("password-reset-token")

# Validate (checks both signature and expiration)
if signer.validate(signed):
  let data = signer.unsign(signed)
  # Process...
else:
  # Signature invalid or expired
  discard
```

### Use Cases

- Password reset tokens
- Email verification links
- Temporary download URLs
- Session cookie signing
- API request signing

## Security Headers

Add security headers via middleware:

```nim
proc securityHeadersMiddleware(): HandlerAsync =
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    ctx.response.headers["X-Content-Type-Options"] = "nosniff"
    ctx.response.headers["X-Frame-Options"] = "DENY"
    ctx.response.headers["X-XSS-Protection"] = "1; mode=block"
    ctx.response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    ctx.response.headers["Content-Security-Policy"] = "default-src 'self'"
    await switch(ctx)

app.use(securityHeadersMiddleware())
```

## JWT Authentication (Optional)

NimMax provides an optional JWT middleware via `nimmax/jwt`. It is **not imported by default** and does not add a hard dependency to the core framework.

### Installation

Install a JWT library separately (e.g., `jwt-nim-baraba` or `yglukhov/jwt`):

```bash
nimble install jwt
# or
nimble install https://github.com/katehonz/jwt-nim-baraba
```

### HMAC (Symmetric) Verification

```nim
import nimmax
import nimmax/jwt  # <-- opt-in extension

let jwtMw = jwtMiddleware(barabaJwtVerifier("my-secret-key", HS256))

# Protect a group of routes
let api = app.newGroup("/api", middlewares = @[jwtMw])

api.get("/profile", proc(ctx: Context) {.async.} =
  let userId = ctx["jwt_claims"]{"sub"}.getStr("anonymous")
  let role   = ctx["jwt_claims"]{"role"}.getStr("guest")
  ctx.json(%*{"user_id": userId, "role": role})
)
```

### RSA/ECDSA (Asymmetric) Verification

```nim
let publicKey = readFile("public.pem")
let jwtMw = jwtMiddleware(barabaJwtVerifierRSA(publicKey, RS256))
app.use(jwtMw)
```

### Custom Verifier

You can use any JWT library by providing a `JwtVerifier` callback:

```nim
proc myVerifier(token: string): tuple[result: JwtAuthResult, claims: JsonNode] {.gcsafe.} =
  # Integrate your own library here
  if token == "valid":
    return (jwtValid, %*{"sub": "user-42"})
  else:
    return (jwtInvalid, newJObject())

app.use(jwtMiddleware(myVerifier))
```

### Accessing Claims in Handlers

When verification succeeds, claims are stored in `ctx["jwt_claims"]`:

```nim
proc handler(ctx: Context) {.async.} =
  let userId  = ctx["jwt_claims"]{"sub"}.getStr("unknown")
  let isAdmin = ctx["jwt_claims"]{"admin"}.getBool(false)
  # ...
```

### Generating Tokens

Token generation is done outside of the middleware using your JWT library directly:

```nim
import pkg/jwt

var claims = newTable[string, Claim]()
claims["sub"]  = newStringClaim("user-42")
claims["name"] = newStringClaim("John Doe")
claims["exp"]  = newTimeClaim(getTime() + 1.hours)

var token = initJWT(%*{"alg": "HS256", "typ": "JWT"}, claims)
token.sign("my-secret-key")

let tokenString = $token  # Send this to the client
```

### Available Helpers

| Helper | Algorithm | Use Case |
|--------|-----------|----------|
| `barabaJwtVerifier(secret, HS256)` | HMAC | API auth with shared secret |
| `barabaJwtVerifierRSA(pubKey, RS256)` | RSA | API auth with public/private key pair |
| `barabaJwtVerifierRSA(pubKey, ES256)` | ECDSA | Modern asymmetric auth |

## Best Practices

1. **Always use HTTPS** in production — set `secure = true` on cookies
2. **Use CSRF protection** for all state-changing operations
3. **Hash passwords** with `hashPassword()` — never store plain text
4. **Set `httpOnly = true`** on session cookies to prevent XSS access
5. **Use `sameSite = "Strict"`** or `"Lax"` on cookies
6. **Validate all input** using the validation module
7. **Use timed signing** for tokens that should expire
8. **Set CORS origins** to specific domains in production, not `*`
9. **Keep `debug = false`** in production
10. **Rotate `secretKey`** periodically
