# Connecting AuraClinic to AuraWa

What AuraClinic needs from a WhatsApp gateway, what AuraWa provides, and the minimum change that will later move
AuraClinic from upstream OpenWA to AuraWa. Nothing here has been applied: AuraClinic and its Docker Compose stack are
unchanged, and the gateway switch is a separate, later phase.

The call-by-call checklist and the result of running it against an isolated AuraWa container are in
[auraclinic-compatibility.md](auraclinic-compatibility.md).

Facts below come from this repository's source (paths relative to the AuraWa root) and from a read-only inspection of
AuraClinic (`GenicAppointment/`; `CO` = `app/packages/Genic/ChannelOpenWa`).

## Why the switch needs no Channel adapter change

AuraWa's application code is OpenWA v0.24.0 unchanged: AuraWa's own changes are limited to repository automation,
image metadata, the bundled license/provenance files and documentation (see [UPSTREAM.md](../../UPSTREAM.md)). Routes,
request/response shapes, auth, webhook format and session behaviour are therefore identical to the gateway AuraClinic
runs today, which is itself built from upstream `v0.24.0` (commit `e9afb97`). The AuraClinic driver pins exactly this
version (`CO/src/Drivers/OpenWaApi.php:15`, `CO/AGENTS.md`), so AuraWa must stay on the v0.24.0 API until the driver
is re-verified against a newer base.

## Current AuraClinic gateway (as deployed today)

From `GenicAppointment/docker-compose.yml` (service `openwa`) and `docker-compose.openwa.yml` (development override):

| Setting         | Value                                                                                                                      |
| --------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Compose project | `genic-clinic-ai-stack`; service `openwa`, only with `--profile openwa`                                                    |
| Image / build   | `image: genic-clinic-ai-openwa:0.24.0`, `build.context: https://github.com/rmyndharis/OpenWA.git#v0.24.0`                  |
| Container       | `genic_clinic_ai_openwa`, `restart: unless-stopped`, `stop_grace_period: 45s`                                              |
| Network         | `genic-clinic-ai`; the php container reaches `http://openwa:2785`                                                          |
| Ports           | none in the base file; the override binds `127.0.0.1:2785:2785` for a host-run app                                         |
| Volume          | `openwa_data:/app/data`                                                                                                    |
| Hardening       | `read_only: true`, `tmpfs: /tmp`, `no-new-privileges`, `cap_drop: ALL`, `cap_add: CHOWN DAC_OVERRIDE FOWNER SETGID SETUID` |
| Limits          | memory 2g (reservation 512m), pids 2048                                                                                    |
| Healthcheck     | `curl -f http://localhost:2785/api/health/ready`, every 30s, timeout 10s, 3 retries, 30s start period                      |
| Webhook path    | override adds `extra_hosts: <OPENWA_CALLBACK_HOST>:host-gateway` and `SSRF_ALLOWED_HOSTS=<OPENWA_CALLBACK_HOST>`           |

AuraClinic configuration (`CO/src/Config/openwa.php`): `OPENWA_ENABLED`, `OPENWA_URL` (scheme, host and optional port;
no path), `OPENWA_ADMIN_KEY`, `OPENWA_CALLBACK_URL` (falls back to `APP_URL`). Compose also reads `OPENWA_CALLBACK_HOST`.

## Docker service and image identity for AuraWa

- Image: `ghcr.io/rohanbthrust24-glitch/aurawa:<version>` once a release exists, or a local build from
  `scripts/aurawa-docker-build.sh` ([building.md](building.md)). Pin an exact version (`0.24.0-aurawa.1`), never
  `latest`.
- Same entrypoint, command, port, user and filesystem layout as the current image: `dumb-init` →
  `docker-entrypoint.sh` → `node dist/main` (`Dockerfile`), listening on `2785`, dropping from root to the `openwa`
  user (uid/gid 997) after fixing ownership of `/app/data` (`docker-entrypoint.sh`).
- Identity can be checked on a running container with `printenv AURAWA_VERSION AURAWA_REVISION`.

## Environment variables

Nothing is strictly required for the SQLite default; these are what AuraClinic's deployment relies on. Keep the
current compose `environment:` block as it is.

| Variable                                                        | Why AuraClinic needs it                                                                                                                                                                                                                                                                  |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `NODE_ENV=production`                                           | Production security defaults (also baked into the image).                                                                                                                                                                                                                                |
| `ENGINE_TYPE=whatsapp-web.js`                                   | Global engine choice; session auth state on the volume is engine-specific.                                                                                                                                                                                                               |
| `API_MASTER_KEY`                                                | Seeds the admin key **only when the `api_keys` table is empty** (`src/modules/auth/auth.service.ts`). In production it must be ≥32 characters and not a known default, or startup fails (`src/config/bootstrap-security.ts`). If unset, a random key is written to `/app/data/.api-key`. |
| `AUTO_START_SESSIONS=true`                                      | Default is `false` (`src/config/feature-flags.ts`); without it linked sessions stay stopped after a restart.                                                                                                                                                                             |
| `SSRF_ALLOWED_HOSTS=<callback host>`                            | Webhook (and media) SSRF protection is on by default and blocks private addresses, which includes Docker service IPs and `host-gateway` (`src/common/security/ssrf-guard.ts`). The callback hostname must be listed and must resolve when the webhook is registered.                     |
| `WEBHOOK_MEDIA_INLINE_MAX_BYTES=0`, `RESOLVE_LID_TO_PHONE=true` | The driver expects no inlined media and a `senderPhone` for `@lid` senders.                                                                                                                                                                                                              |
| `SERVE_DASHBOARD=false`, `ENABLE_SWAGGER=false`                 | Keeps the gateway API-only.                                                                                                                                                                                                                                                              |
| `HOME=/tmp`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` under `/tmp`   | Required with `read_only: true`; Chromium and the entrypoint need a writable `/tmp` (`docker-entrypoint.sh` exits if the XDG dirs cannot be created).                                                                                                                                    |

Redis, PostgreSQL and the queue are optional and unused (`REDIS_ENABLED`/`QUEUE_ENABLED` default to false).

## API endpoint and authentication contract

- Base URL: `http://openwa:2785` from the php container, `http://127.0.0.1:2785` from a host-run app. All routes are
  under `/api`; there is no API versioning (`src/config/app-validation.ts`).
- Auth: `X-API-Key: <key>` (or `Authorization: Bearer <key>`) checked by the global `ApiKeyGuard`
  (`src/modules/auth/guards/api-key.guard.ts`). Roles rank viewer < operator < admin. A key with `allowedSessions` is
  refused (403) on other sessions and on unscoped-only routes such as `POST /api/sessions` and `/api/auth/api-keys`.
- Unknown request-body fields are rejected with 400; errors use NestJS's default `{statusCode, message, error}` shape.

The eleven calls the AuraClinic driver makes (`CO/src/Drivers/OpenWaApi.php`), all present in AuraWa unchanged:

| Call                                                                                          | Key            | AuraClinic reads                                               |
| --------------------------------------------------------------------------------------------- | -------------- | -------------------------------------------------------------- |
| `POST /api/sessions` `{name}`                                                                 | admin          | `id`                                                           |
| `POST /api/sessions/{id}/start`                                                               | admin          | success (a timeout is treated as accepted)                     |
| `GET /api/sessions/{id}`                                                                      | admin / scoped | `status`, `phone`, `restriction.kind`, `restriction.expiresAt` |
| `GET /api/sessions/{id}/qr`                                                                   | admin          | `qrCode` (`data:image/png;base64,…`)                           |
| `POST /api/sessions/{id}/logout`                                                              | admin          | —                                                              |
| `DELETE /api/sessions/{id}`                                                                   | admin          | success or 404                                                 |
| `POST /api/auth/api-keys` `{name, role:"operator", allowedSessions:[id]}`                     | admin          | `id`, `apiKey`                                                 |
| `DELETE /api/auth/api-keys/{keyId}`                                                           | admin          | success or 404                                                 |
| `POST /api/sessions/{id}/messages/send-text` `{chatId:"<digits>@c.us", text}`                 | scoped         | `messageId` (201 `{messageId, timestamp}`)                     |
| `POST /api/sessions/{id}/webhooks` `{url, events:["message.received"], secret, retryCount:5}` | scoped         | `id`                                                           |
| `DELETE /api/sessions/{id}/webhooks/{webhookId}`                                              | admin          | success or 404                                                 |

Session `status` values (`src/modules/session/entities/session.entity.ts`): `created`, `initializing`, `qr_ready`,
`authenticating`, `ready`, `disconnected`, `action_required`, `failed`. `phone` is digits only.

## Outbound send behaviour

`POST /api/sessions/{id}/messages/send-text` (operator role) returns 201 `{messageId, timestamp}` once the message is
handed to WhatsApp; that is acceptance, not delivery. A session that was never started returns 400; an engine that
exists but is not ready returns 409 (`src/modules/message/message-send.service.ts`,
`src/common/errors/engine-not-ready.error.ts`). There is no send idempotency key. The driver maps 401/403 to an auth
failure, 429 and 5xx to retryable, and re-reads the session on 400/404/409 (`CO/src/Drivers/OpenWaWhatsAppDriver.php`).

## Inbound webhook behaviour

- Registered per session through the API only; there is no global webhook URL variable
  (`src/modules/webhook/webhook.controller.ts`). AuraClinic registers `message.received` with its own 64-character
  secret and `retryCount: 5`.
- Delivery: `POST <url>` with JSON envelope `{event, timestamp, sessionId, idempotencyKey, deliveryId, data}`
  (`src/modules/webhook/webhook-delivery.service.ts`) and headers `X-OpenWA-Event`, `X-OpenWA-Idempotency-Key`,
  `X-OpenWA-Delivery-Id`, `X-OpenWA-Retry-Count`, and `X-OpenWA-Signature: sha256=<hex HMAC-SHA256 of the raw body>`
  (`src/modules/webhook/utils/deliver-once.ts`).
- Retries: `retryCount` is the total number of attempts, with exponential backoff from `WEBHOOK_RETRY_DELAY` (5 s) and a
  per-attempt `WEBHOOK_TIMEOUT` (10 s). Redirects are never followed and count as failures
  (`src/common/security/ssrf-guard.ts`).
- AuraClinic receives it at `POST /channels/webhooks/openwa_whatsapp/{connection ULID}` on its callback URL, verifies
  `x-openwa-signature` in constant time, requires `event == message.received` and a matching `sessionId`, and answers
  200 with an empty body (`app/packages/Genic/Admin/src/Support/Channel/ChannelWebhookRouter.php`).

## Persistent data and sessions

Everything lives under `/app/data`, which must be one persistent volume:

| Path                         | Contents                                                     |
| ---------------------------- | ------------------------------------------------------------ |
| `main.sqlite`                | API keys and audit log                                       |
| `openwa.sqlite`              | sessions, webhooks, messages                                 |
| `sessions/session-<uuid>/`   | whatsapp-web.js login state, named by the session row's UUID |
| `media/`, `plugins/`         | local media storage, plugins                                 |
| `.api-key`, `.env.generated` | generated bootstrap key and first-boot defaults              |

The databases and the session folders must stay together: login folders are keyed by database UUIDs, and losing
`main.sqlite` invalidates every API key AuraClinic stores. Because AuraWa runs the same code, the existing
`openwa_data` volume is format-compatible with AuraWa, but it holds live WhatsApp sessions. Test AuraWa against a
**separate** volume first, and back up `openwa_data` (`scripts/backup.sh`) before any switch that reuses it.

## Health checks

All health routes are public and unauthenticated (`src/modules/health/health.controller.ts`):

- `GET /api/health/live` → 200 `{status:"ok"}` whenever the process serves HTTP.
- `GET /api/health/ready` → 200 when both SQLite databases answer `SELECT 1` within 3 s; 503 while draining for
  shutdown or when a database is unavailable. It does **not** check WhatsApp session state.
- `GET /api/health` → `{status, timestamp}`.

The image keeps `curl` and the same `HEALTHCHECK`, so AuraClinic's compose healthcheck works unchanged. Session health
is visible only through `GET /api/sessions/{id}`, which AuraClinic already polls.

## Networking

- Internal port `2785`; no host port is needed for the php container. Keep the development override's
  `127.0.0.1:2785:2785` binding (loopback only) for a host-run app.
- Join the `genic-clinic-ai` network under the service name `openwa` so `OPENWA_URL=http://openwa:2785` keeps working.
- Webhooks go from the gateway to AuraClinic, so the callback host must be reachable from the container
  (`extra_hosts: <host>:host-gateway` for a host-run app) and listed in `SSRF_ALLOWED_HOSTS`.
- Outbound internet access to WhatsApp Web is required at runtime.

## The minimum switch (later phase, not applied)

The image source changes, and two container settings change with it; the service name, environment, volume, network
and healthcheck stay as they are:

```yaml
openwa:
  # was: build.context https://github.com/rmyndharis/OpenWA.git#v0.24.0 + image genic-clinic-ai-openwa:0.24.0
  image: ghcr.io/rohanbthrust24-glitch/aurawa:0.24.0-aurawa.1
  stop_grace_period: 75s # was 45s
  cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, KILL, SETGID, SETUID] # KILL is new
```

`KILL` is what lets a stop reach the app. AuraClinic's current hardening (`cap_drop: ALL` plus the five capabilities
above it) leaves `dumb-init`, PID 1 as root, unable to forward `SIGTERM` to the `openwa` process, so every `docker stop`
or restart skips the graceful drain and ends in a SIGKILL. This was reproduced with the same image and fixed in
AuraWa's own compose files and chart; it applies to the current OpenWA gateway too, since its image and hardening are
the same. The 75s grace covers the drain's bounds (see `docker-compose.yml`).

Building from source instead is also possible
(`build.context: https://github.com/rohanbthrust24-glitch/AuraWa.git#v0.24.0-aurawa.1` with
`args: {AURAWA_VERSION: 0.24.0-aurawa.1, AURAWA_REVISION: <commit>}`). Without the args the image is labelled
`dev`/`unknown`.

AuraClinic's own docs and comments that say "OpenWA v0.24.0" stay accurate for the API but would need a wording update
when the switch happens; that is an AuraClinic change for that phase.
