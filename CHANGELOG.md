# Changelog

All notable changes to NimMax are documented in this file.

## [1.2.0] — 2026-05-16

### Framework Universality
- **Hunos is now an optional dependency** — removed from `nimmax.nimble` requires. Install only if you need the multi-threaded backend:
  ```bash
  nimble install hunos
  nim c --threads:on --mm:arc -d:nimmaxHunos app.nim
  ```
- **Zippy is now optional in compression middleware** — compile with `-d:nimmaxNoZippy` to disable compression and skip the zippy dependency.
- Added conditional compilation guards to Hunos backend files with clear error messages.

### Documentation
- Updated `README.md` with new v1.1 features and optional dependency notes.
- Updated `docs/api-reference.md` with all new v1.1+ procedures.
- Updated `docs/getting-started.md`, `docs/middleware.md`, `docs/request-response.md`, `docs/hunos-backend.md`.
- Added `CHANGELOG.md`.

---

## [1.1.0] — 2026-05-16

### Deficiency Fixes (NimForum Migration)
- **`makeUri()`** — URL builder respecting `X-Forwarded-Proto` for reverse proxies.
- **`clientIP()`** — client IP accessor with `X-Forwarded-For` and `X-Real-IP` support.
- **`getParam()` / `getParamInt()` / `getParamFloat()` / `getParamBool()`** — unified parameter access (tries path → query → post).
- **`setCookieEnum()`** — type-safe cookie setter using stdlib `SameSite` enum.
- **`cond()` / `halt()`** — Jester-style control flow helpers.
- **`resp()`** — Jester-compatible parameter order overloads.
- **`formBodyMiddleware()`** — automatic POST body parsing for form data.
- **`loadNimmaxConfig()`** — renamed from `loadConfig` to avoid naming collisions; old name kept as deprecated alias.

---

## [1.0.0] — 2026-04-30

### Initial Release
- Pattern-based routing with named parameters and wildcards
- Onion-model middleware pipeline with composition
- Type-safe parameter access (`getInt`, `getFloat`, `getBool` → `Option[T]`)
- Session management (in-memory and signed-cookie backends)
- CSRF protection, CORS, basic auth
- Static file serving with ETag, Range requests, caching
- WebSocket support (RFC 6455)
- JSON body parsing middleware
- Response streaming (chunked transfer encoding)
- gzip/deflate compression (zippy)
- OpenAPI / Swagger generation
- LRU/LFU cache with TTL
- Cryptographic signing and PBKDF2 password hashing
- Rate limiting with sliding window
- Request ID tracing
- Graceful shutdown
- i18n support
- Testing utilities (mock requests, run-once, debug output)
- Environment configuration (JSON, `.env`, env vars)
- Optional Hunos multi-threaded backend
