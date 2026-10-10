# AuraClinic driver compatibility checklist

The API contract AuraClinic's OpenWA driver depends on, judged by the driver's own acceptance rules, and the result of
running it against an isolated AuraWa container. Background and deployment details are in
[auraclinic-integration.md](auraclinic-integration.md).

Sources: `GenicAppointment/app/packages/Genic/ChannelOpenWa/src/Drivers/OpenWaApi.php` (requests),
`OpenWaWhatsAppDriver.php` (acceptance and error mapping) and `Channel/src/Support/Interactive/PairingState.php` (QR
rule), read without modification. They were read from AuraClinic's uncommitted working copy as last modified on
2026-10-10 (09:21, 11:06 IST) and 2026-10-09 respectively. AuraClinic is under active development, so re-check this
checklist whenever those three files change.

## Request conventions the driver uses

- Laravel HTTP client: `Accept: application/json`, `Content-Type: application/json`, `X-API-Key: <key>`.
- Every `POST` carries a JSON body; one the driver passes no data to (`start`, `logout`) sends `[]`. `GET` and `DELETE`
  send no body.
- Connect timeout 5 s, request timeout 20 s, `start` 5 s. No retries in the client; a timeout or connection error
  becomes `OpenWaUnreachable`.
- Every path id must be a UUID (`/^[0-9a-fA-F]{8}-…-[0-9a-fA-F]{12}$/`) before a request is made.
- "Success" means a 2xx status. Error bodies are never parsed; only status codes are mapped.

## The eleven calls

Essential calls are the ones a working connection cannot do without (pairing, verification, inbound setup, sending).
Lifecycle calls only remove what the essential calls created; they all accept 404 as already done.

| #   | Driver method      | Request                                                                                                  | Key            | Tier      | Driver accepts                                                                                                          |
| --- | ------------------ | -------------------------------------------------------------------------------------------------------- | -------------- | --------- | ----------------------------------------------------------------------------------------------------------------------- |
| 1   | `createSession`    | `POST /api/sessions` `{name:"ac-<ulid>"}`                                                                | admin          | Essential | 2xx and `id` is a UUID                                                                                                  |
| 2   | `startSession`     | `POST /api/sessions/{id}/start` `[]`                                                                     | admin          | Essential | 2xx, **or a timeout after 5 s** (OpenWA keeps starting)                                                                 |
| 3   | `session`          | `GET /api/sessions/{id}`                                                                                 | admin / scoped | Essential | 2xx; `status` in the session enum; `phone` digits `^[1-9]\d{6,14}$` once `ready`; `restriction.kind` / `expiresAt`      |
| 4   | `qr`               | `GET /api/sessions/{id}/qr`                                                                              | admin          | Essential | 2xx and `qrCode` matches `^data:image/png;base64,[A-Za-z0-9+/]+={0,2}$`, at most 65,536 characters                      |
| 5   | `createSessionKey` | `POST /api/auth/api-keys` `{name:"auraclinic-<id>", role:"operator", allowedSessions:[id]}`              | admin          | Essential | 2xx, `id` is a UUID, `apiKey` a non-empty string                                                                        |
| 6   | `createWebhook`    | `POST /api/sessions/{id}/webhooks` `{url, events:["message.received"], secret:<64 chars>, retryCount:5}` | scoped         | Essential | 2xx and `id` is a UUID; 400 → not configured, 401/403 → auth, 404 → revoked                                             |
| 7   | `sendText`         | `POST /api/sessions/{id}/messages/send-text` `{chatId:"<digits>@c.us", text}`                            | scoped         | Essential | 2xx with `messageId` (string, ≤191 chars); 401/403 → auth; 429 → retry; 5xx → retry; 400/404/409 → re-read session (#3) |
| 8   | `logout`           | `POST /api/sessions/{id}/logout` `[]`                                                                    | admin          | Lifecycle | any answer (the delete that follows decides)                                                                            |
| 9   | `deleteSession`    | `DELETE /api/sessions/{id}`                                                                              | admin          | Lifecycle | 2xx or 404                                                                                                              |
| 10  | `deleteKey`        | `DELETE /api/auth/api-keys/{keyId}`                                                                      | admin          | Lifecycle | 2xx or 404                                                                                                              |
| 11  | `deleteWebhook`    | `DELETE /api/sessions/{id}/webhooks/{webhookId}`                                                         | admin          | Lifecycle | 2xx or 404                                                                                                              |

Contract points around the calls:

- A scoped key must be refused (401/403) on other sessions and on admin-only routes, and a deleted key must get 401.
- Deleting a session must also remove its webhooks (the driver never deletes them separately on revoke).
- Inbound deliveries carry `X-OpenWA-Signature: sha256=<64 lowercase hex>`, the HMAC-SHA256 of the raw body with the
  webhook secret, and the envelope `{event, timestamp, sessionId, idempotencyKey, deliveryId, data}`; the driver
  requires `event == "message.received"` and a matching `sessionId`.
- Webhook targets on private addresses (Docker service names, `host-gateway`) need `SSRF_ALLOWED_HOSTS`.

## Result: 2026-10-10 standalone run

**36 of 36 checks passed. No compatibility gap was found for anything testable without a linked WhatsApp account.**

Tested build: image `aurawa:0.24.0-aurawa.dev.c508065.dirty`
(`sha256:eaeaf88915cccea2101a500fde20ee04c3aeb29f8683cf76358a252680ffa4f5`), built from AuraWa working tree
`52295eda241e2ae2770daac1b7cc179feafa1668` (OpenWA v0.24.0 application code, AuraWa changes per `UPSTREAM.md`).

Setup: one container on a dedicated bridge network, a new dedicated volume, `127.0.0.1:2786` only, AuraClinic's
environment and hardening (read-only root filesystem, `tmpfs /tmp`, dropped capabilities, 2 GB / 2048 pids) with a
freshly generated test admin key, plus a local receiver container on the same network listed in `SSRF_ALLOWED_HOSTS`.
The existing gateway, its network and its volume were not touched. All test resources were removed afterwards.

| Call / behaviour                | Observed                                                                                                                                      | Driver outcome            |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| Health                          | `/api/health/live` 200; `/api/health/ready` 200 (both databases up); `/api/health` without key omits `version`                                | compose healthcheck ok    |
| Auth                            | no key 401, wrong key 401, admin `X-API-Key` 200; errors `{statusCode, message, error}`                                                       | as mapped                 |
| 1 `createSession`               | 201, UUID `id`, `status: created`; same name again 409                                                                                        | accepted / 409 mapped     |
| 2 `startSession`                | **no answer within 5 s** (browser start)                                                                                                      | timeout accepted          |
| 3 `session`                     | `initializing` → `qr_ready` within about 15 s; `phone` and `restriction` present (`null`)                                                     | pairing proceeds          |
| 4 `qr`                          | 200, PNG data URL, 6,386 characters; 400 before the session is started (driver shows "starting")                                              | accepted                  |
| 5 `createSessionKey`            | 201, UUID `id`, non-empty `apiKey`                                                                                                            | accepted                  |
| Scoped key isolation            | own session 200; other session, create session, mint key, delete other session all 403                                                        | as required               |
| 6 `createWebhook`               | 201 with the scoped key, UUID `id`, `events: ["message.received"]`, `active: true`, secret not echoed                                         | accepted                  |
| SSRF                            | non-allow-listed private URL 400 `Destination address is not allowed`                                                                         | 400 → not configured      |
| Signed delivery                 | test delivery reached the receiver; signature valid under the driver's algorithm; envelope and `X-OpenWA-*` headers as above; `event: "test"` | would be ignored with 200 |
| 7 `sendText` (error paths only) | session not linked: 409; after logout: 400 `not active`                                                                                       | re-read session           |
| 11 `deleteWebhook`              | 204, then 404                                                                                                                                 | accepted both             |
| 8 `logout`                      | 200 for a never-linked session                                                                                                                | ignored                   |
| 9 `deleteSession`               | 204, then 404; both engines' auth directories purged                                                                                          | accepted both             |
| 10 `deleteKey`                  | 204, then 404; the deleted key gets 401                                                                                                       | accepted both             |
| Webhook cascade                 | listed before the session delete, gone (404) after                                                                                            | as relied on              |

Observations that are not gaps:

- `start` outlasts the driver's 5 s timeout on every cold browser start. This is the case the driver was written for:
  the pairing continues by polling.
- The driver's comments expect a never-linked session to refuse `logout`; AuraWa answers 200. The driver ignores the
  logout answer and deletes the session either way.
- After both sessions were deleted, `sessions/` kept only `.wa-web-cache`, a shared copy of the WhatsApp Web client
  page, not per-session data.

## Needs a controlled test with an authorised WhatsApp test account

Not verified here, and not to be claimed until that test runs:

- Linking: `authenticating` → `ready`, the digits-only `phone`, and the scoped-key verification on a `ready` session.
- `sendText` success: the 201 `{messageId, timestamp}` shape and the `messageId` format, plus 429 behaviour.
- Inbound `message.received`: the `data` fields the driver reads (`id`, `type`, `fromMe`, `isGroup`,
  `isStatusBroadcast`, `kind`, `from` as `@c.us` or `@lid` with `senderPhone`, `body`, `timestamp`, `contact.*`), and
  real retry/backoff over five attempts.
- `logout` of a linked session (device removed from the phone), `action_required` / `restriction`, and session restore
  with `AUTO_START_SESSIONS=true` after a container restart.
