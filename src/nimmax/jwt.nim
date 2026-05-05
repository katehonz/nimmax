## NimMax JWT Integration (Optional Extension)
##
## This module provides JWT middleware for NimMax but is NOT imported by default.
## To use it, install a JWT library (e.g., jwt-nim-baraba / yglukhov/jwt) and add
## `import nimmax/jwt` to your application.
##
## The module is designed to work with any JWT library via the `JwtVerifier`
## callback. It also includes convenience helpers for the `jwt` package
## (jwt-nim-baraba / yglukhov/jwt).

import std/[asyncdispatch, strutils, httpcore, json, tables]
import ./core/types, ./core/middleware, ./core/context, ./core/utils

# ---------------------------------------------------------------------------
# Generic JWT middleware (works with any JWT library)
# ---------------------------------------------------------------------------

type
  JwtAuthResult* = enum
    jwtValid
    jwtMissing
    jwtInvalid
    jwtExpired

  JwtVerifier* = proc(token: string): tuple[result: JwtAuthResult, claims: JsonNode] {.gcsafe.}

proc jwtMiddleware*(
  verifier: JwtVerifier,
  headerName = "Authorization",
  schema = "Bearer"
): HandlerAsync =
  ## Creates a JWT authentication middleware.
  ##
  ## The `verifier` callback receives the raw token string and must return
  ## whether it is valid plus the decoded claims as JsonNode.
  ##
  ## On success, claims are stored in `ctx["jwt_claims"]` so handlers can
  ## access them via `ctx["jwt_claims"]{"sub"}.getStr()`.
  ##
  ## Example::
  ##
  ##   let verifyToken = proc(token: string): auto =
  ##     # call your JWT library here
  ##     (jwtValid, claimsNode)
  ##
  ##   app.use(jwtMiddleware(verifyToken))
  ##   app.get("/api/profile") do (ctx: Context):
  ##     let userId = ctx["jwt_claims"]{"sub"}.getStr("anonymous")
  ##     await ctx.json(%*{ "user": userId })
  ##
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let authHeader = ctx.request.headers.getHeader(headerName, "")
    var token = ""

    if schema.len == 0:
      token = authHeader.strip()
    elif authHeader.len > schema.len + 1 and
         authHeader.toLowerAscii.startsWith(schema.toLowerAscii & " "):
      token = authHeader[(schema.len + 1)..^1].strip()

    if token.len == 0:
      ctx.response.code = Http401
      ctx.response.body = "Unauthorized: missing token"
      return

    let (status, claims) = verifier(token)
    case status
    of jwtValid:
      ctx["jwt_claims"] = claims
      await switch(ctx)
    of jwtExpired:
      ctx.response.code = Http401
      ctx.response.body = "Unauthorized: token expired"
    of jwtInvalid:
      ctx.response.code = Http401
      ctx.response.body = "Unauthorized: invalid token"
    of jwtMissing:
      ctx.response.code = Http401
      ctx.response.body = "Unauthorized: missing token"

proc requireJwtClaims*(
  ctx: Context,
  key: string
): JsonNode =
  ## Helper to safely read a JWT claim from context.
  ## Returns an empty JsonNode if the claim is missing.
  if ctx.ctxData.hasKey("jwt_claims"):
    result = ctx["jwt_claims"]{key}
  else:
    result = newJNull()

# ---------------------------------------------------------------------------
# Convenience helpers for jwt-nim-baraba (yglukhov/jwt)
#
# Install: nimble install jwt
#          OR nimble install https://github.com/katehonz/jwt-nim-baraba
# ---------------------------------------------------------------------------

import pkg/jwt
export jwt.SignatureAlgorithm, jwt.InvalidToken

proc barabaJwtVerifier*(
  secret: string,
  alg: SignatureAlgorithm = HS256
): JwtVerifier =
  ## Convenience constructor for jwt-nim-baraba (yglukhov/jwt).
  ##
  ## Usage::
  ##
  ##   let jwtMw = jwtMiddleware(barabaJwtVerifier("my-secret", HS256))
  ##   app.use(jwtMw)
  ##
  result = proc(token: string): tuple[result: JwtAuthResult, claims: JsonNode] {.gcsafe.} =
    try:
      let jwt = toJWT(token)
      if jwt.verify(secret, alg):
        return (jwtValid, %jwt.claims)
      else:
        return (jwtInvalid, newJObject())
    except InvalidToken:
      # toJWT raises InvalidToken on malformed input
      return (jwtInvalid, newJObject())
    except CatchableError:
      # verify() internally checks exp/nbf/i and returns false,
      # but any unexpected error is treated as invalid
      return (jwtInvalid, newJObject())

proc barabaJwtVerifierRSA*(
  publicKey: string,
  alg: SignatureAlgorithm = RS256
): JwtVerifier =
  ## RSA/ECDSA verifier for jwt-nim-baraba using a public key.
  ##
  ## Usage::
  ##
  ##   let jwtMw = jwtMiddleware(barabaJwtVerifierRSA(readFile("pub.pem"), RS256))
  ##   app.use(jwtMw)
  ##
  result = proc(token: string): tuple[result: JwtAuthResult, claims: JsonNode] {.gcsafe.} =
    try:
      let jwt = toJWT(token)
      if jwt.verify(publicKey, alg):
        return (jwtValid, %jwt.claims)
      else:
        return (jwtInvalid, newJObject())
    except InvalidToken:
      return (jwtInvalid, newJObject())
    except CatchableError:
      return (jwtInvalid, newJObject())
