# Upstream Provenance

AuraWa is an independently maintained source copy of OpenWA. It is not a GitHub fork, and upstream
Git history was not imported.

| Item                | Value                                                                |
| ------------------- | -------------------------------------------------------------------- |
| Upstream repository | https://github.com/rmyndharis/OpenWA                                 |
| Upstream version    | `v0.24.0`                                                            |
| Upstream commit     | `e9afb97da44fa1f3c1fdc469a134a706394eda46`                           |
| Upstream tag object | `c59f50c90ebde50f109954e619906dfaf64b61a3` (annotated tag `v0.24.0`) |
| Upstream tree       | `1cc504cd535603cded3af0056986582fd6625a96`                           |
| Date of source copy | 2026-10-10                                                           |

## Source copy

On 2026-10-10 every file tracked at the upstream commit above (1,859 files) was copied into AuraWa, byte- and
mode-identical to the upstream tree (verified by rebuilding a git tree object from the copy and matching the upstream
tree hash, and by `diff -r`). Only upstream's `.git/` history was left out. The upstream `README.md` replaced AuraWa's
original placeholder README.

## AuraWa changes relative to upstream

AuraWa does not modify OpenWA's application code: no file under `src/` (other than the repository-policy spec changes
listed below), `dashboard/` (other than its lockfile), `sdk/` or `test/`, and neither `package.json`, differs from
upstream, and the API, internal package names and `X-OpenWA-*` webhook headers are upstream's. AuraWa's changes are
limited to repository automation, image identity, documentation, security updates of locked dependency versions within
the ranges upstream declares, and deployment configuration (container capabilities and stop grace period).

### 2026-10-10: independent build identity and safe repository automation

| File                                                                                            | Change                                                                                                                                                                                                                                                                                                                                                                | Why                                                                                                   |
| ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `.github/workflows/ci.yml`                                                                      | The `docker` job builds and smoke-tests both architectures but no longer logs in, holds `packages: write`, pushes, or moves a `:main` tag                                                                                                                                                                                                                             | An ordinary push must not publish an image                                                            |
| `.github/workflows/release.yml`                                                                 | Triggers only on `v*-aurawa.*` tags; the lint job validates the tag against `package.json` and decides the prerelease flag once; publishes to `ghcr.io/<this repo>` only (Docker Hub and upstream's namespace removed); tags the exact version plus `latest` for non-prereleases; staging cleanup uses this repo's package name; release notes name the upstream base | Image publishing tied to an intentional AuraWa release, never to upstream tags or upstream registries |
| `.github/workflows/security-scan.yml`                                                           | The weekly image scan skips with a notice until a stable AuraWa release exists (only on an HTTP 404 from the releases API)                                                                                                                                                                                                                                            | `latest` does not exist before the first release; audit and base-image drift jobs unchanged           |
| `.github/workflows/{js,python,java,php}-sdk-release.yml`, `.github/workflows/split-php-sdk.yml` | Publishing jobs guarded with `if: github.repository == 'rmyndharis/OpenWA'`                                                                                                                                                                                                                                                                                           | The SDK packages and the PHP split repository are upstream-owned                                      |
| `.github/FUNDING.yml`                                                                           | Removed                                                                                                                                                                                                                                                                                                                                                               | GitHub's Sponsor button would present upstream's personal funding link as AuraWa's                    |
| `.github/ISSUE_TEMPLATE/*.yml`, `SECURITY.md`                                                   | Docs, security-advisory and SECURITY links point to AuraWa; SECURITY.md routes reports to AuraWa and notes upstream coordination                                                                                                                                                                                                                                      | Vulnerability reports about AuraWa should reach its maintainers                                       |
| `README.md`                                                                                     | AuraWa notice at the top; CI and version badges point to AuraWa; upstream support link moved into the notice                                                                                                                                                                                                                                                          | Clear identity without rewriting upstream documentation                                               |
| `Dockerfile`                                                                                    | Copies `LICENSE` and `UPSTREAM.md` into `/app`; adds `AURAWA_VERSION` / `AURAWA_REVISION` build args, matching `ENV`, and OCI labels, all after the last heavy layer                                                                                                                                                                                                  | MIT notice ships with every image; every image identifies its exact source revision                   |
| `scripts/aurawa-docker-build.sh`                                                                | New: supported local build command that derives version and commit from git                                                                                                                                                                                                                                                                                           | Reproducible, identifiable local builds                                                               |
| `docs/aurawa/building.md`, `docs/aurawa/auraclinic-integration.md`                              | New                                                                                                                                                                                                                                                                                                                                                                   | Build, versioning and release contract; AuraClinic integration contract                               |
| `docs/aurawa/auraclinic-compatibility.md`                                                       | New (2026-10-10 standalone compatibility test)                                                                                                                                                                                                                                                                                                                        | AuraClinic driver checklist and the isolated test result                                              |
| `src/common/ci-privilege-gate.spec.ts`, `src/common/release-gate-parity.spec.ts`                | Repository-policy assertions updated to AuraWa's policy (CI never publishes; one prerelease rule decided by the release tag step)                                                                                                                                                                                                                                     | These specs read the workflow files; they pinned upstream's publishing policy                         |
| `UPSTREAM.md`                                                                                   | This file                                                                                                                                                                                                                                                                                                                                                             | Provenance and change record                                                                          |

### 2026-10-10: dependency security updates (lockfiles only)

The first AuraWa CI run failed its audit gate on advisories published after the copied lockfiles were generated. Each
fixed version lies inside the range the dependency tree already declares, so both `package.json` files are unchanged
and no override was added; upstream's own CHANGELOG likewise bumps the lockfile when the range allows and uses an
override only when it does not. `@modelcontextprotocol/sdk` and `shell-quote` are locked at the first fixed release even
though newer in-range releases exist, to keep the change minimal.

| Lockfile                      | Package (how it enters)                                                                                        | Version         | Advisories                                                                          | Ships in the image           |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------- | --------------- | ----------------------------------------------------------------------------------- | ---------------------------- |
| `package-lock.json`           | `proxy-addr` (via `express`, `^2.0.7`)                                                                         | 2.0.7 → 2.0.8   | GHSA-jqcg-44mw-7w3h (critical)                                                      | yes                          |
| `package-lock.json`           | `@modelcontextprotocol/sdk` (direct, `^1.30.0`)                                                                | 1.30.0 → 1.31.0 | GHSA-6qxp-vccf-f47h (high)                                                          | yes                          |
| `package-lock.json`           | `sharp` (direct, `^0.35.4`), with its `@img/sharp-*` 0.35.5 and `@img/sharp-libvips-*` 1.3.4 platform packages | 0.35.4 → 0.35.5 | GHSA-wq5f-xc86-pv6w (high)                                                          | yes                          |
| `package-lock.json`           | `shell-quote` (via `concurrently`; upstream's override `^1.10.0`)                                              | 1.10.0 → 1.11.0 | GHSA-pqg4-j6r4-53mv (critical)                                                      | no (dev)                     |
| `package-lock.json`           | `handlebars` (via `ts-jest`, `^4.7.9`)                                                                         | 4.7.9 → 4.7.10  | GHSA-8r5x-fm3f-whwj, GHSA-p8wg-vrv2-v86f (critical), GHSA-xw65-4hp5-5hc7 (moderate) | no (dev)                     |
| `dashboard/package-lock.json` | `source-map-js` (via `postcss` and `css-tree`, `^1.2.1`)                                                       | 1.2.1 → 1.2.2   | GHSA-68fv-2mgg-jv7q (high)                                                          | no (dashboard build tooling) |

When AuraWa is re-based onto a newer upstream release, keep these versions only if that release's lockfiles still
carry older ones.

### 2026-10-10: graceful shutdown (`CAP_KILL` and stop grace period)

`docker stop` never reached the app: `dumb-init` stays PID 1 as root and forwards `SIGTERM` to the `openwa` process
that `gosu` dropped to, and signalling another uid needs `CAP_KILL`, which the compose and chart hardening
(`cap_drop: ALL` plus five capabilities) removed. The forward was refused, the graceful drain never ran, and every
stop ended in a SIGKILL after the grace period (exit 137). Reproduced in disposable containers: adding `KILL` gives a
graceful exit 0 in about 3 s. Upstream's later `main` makes the same `KILL` change in its compose file and chart and
raises the grace period to 75 s; this backports only those settings. No application or image change.

| File                                                                                              | Change                                                                                                                                                 | Why                                                                                 |
| ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| `docker-compose.yml`                                                                              | `KILL` added to the `openwa-api` `cap_add`; `stop_grace_period` 45s → 75s, comment recomputed for this code's drain bounds                             | Let `SIGTERM` reach the app; leave room for drain + engine teardown + webhook drain |
| `docker-compose.dev.yml`                                                                          | `KILL` added; grace period deliberately left at Docker's default, with a comment                                                                       | Development stops quickly (no drain delay); documented trade-off                    |
| `charts/openwa/values.yaml`                                                                       | `KILL` added to `containerSecurityContext.capabilities.add`; `terminationGracePeriodSeconds` 45 → 75; comments updated                                 | Same fix for Kubernetes; the non-root start needs none of the capabilities          |
| `docs/12-troubleshooting-faq.md`, `docs/13-horizontal-scaling.md`, `docs/30-plugin-sandboxing.md` | Capability lists include `KILL` and say why                                                                                                            | Keep the documented hardening equal to the shipped one                              |
| `scripts/smoke-test-graceful-stop.sh`                                                             | New: runs the image under the compose hardening and asserts the drain logs, exit 0 well before the timeout, and the `openwa` user                      | Proves a stop reaches the app; fails (137, no drain) without `KILL`                 |
| `.github/workflows/ci.yml`                                                                        | The `docker` job runs the graceful-stop smoke test after the non-root check                                                                            | Gate the fix on every push                                                          |
| `src/common/ci-privilege-gate.spec.ts`                                                            | New drift checks: both compose files, the chart and the smoke test share the six capabilities; CI runs the smoke test; compose and chart agree on 75 s | A future change cannot drop `KILL` silently                                         |

AuraClinic's compose file has the same hardening and needs the same two settings when it switches to AuraWa
(`docs/aurawa/auraclinic-integration.md`).

### Reviewed and deliberately left as upstream

- Runtime branding: the OpenAPI contact (`src/config/swagger.config.ts`, mirrored in `openapi.json`), dashboard titles,
  the `openwa` user and package name, `X-OpenWA-*` headers. Changing them alters the API contract clients depend on.
- `charts/openwa` image and metadata (image `ghcr.io/rmyndharis/openwa`, upstream home/sources; only the capability
  and grace-period values changed, above): AuraClinic does not use the chart, and AuraWa has no published image yet.
  Repoint it together with the first AuraWa release if the chart is ever used.
- `docker-compose.yml` / `docker-compose.dev.yml` otherwise: upstream's reference stack; they build from the local
  source.
- `CHANGELOG.md` and `docs/` (other than `docs/aurawa/`): upstream's history and documentation.
- `.github/dependabot.yml`, `sdk-ci.yml`, `.env.example`, `.env.minimal`: still correct for AuraWa.

## Keeping this record current

Every AuraWa change to a file that came from upstream must be added to the change list above, so the divergence from
upstream stays auditable and can be re-applied when AuraWa is re-based onto a newer OpenWA release
(docs/aurawa/building.md).

## License obligations

OpenWA is distributed under the MIT License, `Copyright (c) 2026 Yudhi Armyndharis and OpenWA
Contributors`. The upstream `LICENSE` file is retained unchanged at the repository root and is copied into every
AuraWa image as `/app/LICENSE`.

The MIT License requires the copyright notice and permission notice to be included in all copies or
substantial portions of the software. Keep `LICENSE` and the upstream copyright notice in this
repository, in source distributions, and in any distributed builds or images derived from it, even if
the code is later modified or renamed. Third-party dependencies (see `package-lock.json`,
`dashboard/package-lock.json` and the SDK manifests under `sdk/`) carry their own licenses, which
continue to apply.
