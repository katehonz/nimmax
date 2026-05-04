## Security Headers Middleware
##
## Adds important HTTP security headers to every response.
## Recommended for all production deployments.
##
## Usage:
##   import nimmax/middlewares/security
##   app.use(securityHeadersMiddleware())

import std/[asyncdispatch, httpcore, strutils]
import ../core/types, ../core/middleware

type
  SecurityConfig* = object
    contentTypeOptions*: bool      ## X-Content-Type-Options: nosniff
    frameOptions*: string          ## X-Frame-Options (DENY, SAMEORIGIN, ALLOW-FROM)
    xssProtection*: bool           ## X-XSS-Protection: 1; mode=block
    hsts*: string                  ## Strict-Transport-Security value
    referrerPolicy*: string        ## Referrer-Policy value
    csp*: string                   ## Content-Security-Policy value

proc defaultSecurityConfig*(): SecurityConfig =
  ## Returns a secure-by-default configuration.
  SecurityConfig(
    contentTypeOptions: true,
    frameOptions: "DENY",
    xssProtection: true,
    hsts: "max-age=63072000; includeSubDomains",
    referrerPolicy: "strict-origin-when-cross-origin",
    csp: "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"
  )

proc securityHeadersMiddleware*(config = defaultSecurityConfig()): HandlerAsync =
  ## Middleware that adds security headers to all responses.
  result = proc(ctx: Context): Future[void] {.async, gcsafe.} =
    let h = ctx.response.headers

    if config.contentTypeOptions:
      h["X-Content-Type-Options"] = "nosniff"

    if config.frameOptions.len > 0:
      h["X-Frame-Options"] = config.frameOptions

    if config.xssProtection:
      h["X-XSS-Protection"] = "1; mode=block"

    if config.hsts.len > 0:
      h["Strict-Transport-Security"] = config.hsts

    if config.referrerPolicy.len > 0:
      h["Referrer-Policy"] = config.referrerPolicy

    if config.csp.len > 0:
      h["Content-Security-Policy"] = config.csp

    # Additional baseline headers
    h["X-Download-Options"] = "noopen"
    h["X-Permitted-Cross-Domain-Policies"] = "none"

    await switch(ctx)
