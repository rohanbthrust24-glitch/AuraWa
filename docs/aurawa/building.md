# Building, versioning and releasing AuraWa

AuraWa is an independently maintained distribution of OpenWA (provenance in [UPSTREAM.md](../../UPSTREAM.md)). This
page is the AuraWa-specific build contract: how an image is built locally, how versions and tags are named, and what
the repository automation does with them. Everything else about the application is upstream OpenWA documentation in
this `docs/` directory and applies unchanged.

## Identity

| Item                   | Value                                                                                                   |
| ---------------------- | ------------------------------------------------------------------------------------------------------- |
| Distribution name      | AuraWa                                                                                                  |
| Published image        | `ghcr.io/rohanbthrust24-glitch/aurawa:<version>` (only after a release; none is published yet)          |
| Local image (default)  | `aurawa:<version>`                                                                                      |
| Upstream base          | the `version` in `package.json` (currently `0.24.0`, i.e. OpenWA v0.24.0)                               |
| Internal package names | unchanged from upstream (`openwa`, `OpenWA` UI/API titles, `X-OpenWA-*` webhook headers, `openwa` user) |

Runtime naming is deliberately left as upstream ships it: renaming would change the API contract that clients such as
AuraClinic depend on and would make future upstream syncs harder.

Every image carries its identity in two places:

- OCI labels: `org.opencontainers.image.version`, `org.opencontainers.image.revision` (the git commit),
  `org.opencontainers.image.source`, `org.opencontainers.image.licenses`, and `aurawa.upstream.repository`.
- Environment: `AURAWA_VERSION` and `AURAWA_REVISION` inside the container. The application never reads them.

The image also ships `/app/LICENSE` (the upstream MIT notice) and `/app/UPSTREAM.md`.

## Version scheme

```text
<upstream version>-aurawa.<N>[-<prerelease>]

0.24.0-aurawa.1        first AuraWa release based on OpenWA 0.24.0
0.24.0-aurawa.2        next AuraWa release on the same upstream base (fixes, AuraWa changes)
0.24.0-aurawa.3-rc.1   a prerelease of 0.24.0-aurawa.3, for testing before it becomes latest
0.25.0-aurawa.1        first AuraWa release after re-basing onto OpenWA 0.25.0 (N restarts at 1)
```

- `package.json` keeps the upstream version. It is **not** bumped for AuraWa releases, because the docs checks, the
  OpenAPI snapshot and the SDK contract checks all track it as the upstream version.
- `N` is a positive integer without leading zeros, incremented for every AuraWa release on the same upstream base.
- A version is a prerelease when it carries a suffix after `N`, or when the upstream base itself is a prerelease.

The git tag is the version with a `v` prefix: `v0.24.0-aurawa.1`. Upstream OpenWA tags (`v0.24.0`) never match the
AuraWa tag pattern, so they can never trigger a release in this repository.

## Local build

Requirements: Docker with BuildKit (the default `docker build` on current Docker releases), network access for the
base image, Debian packages, npm and the pinned Chrome for Testing download. A build takes a few minutes and about
2.3 GB of disk for the final image.

```bash
# From the repository root. Builds aurawa:<version> with the version and commit baked in.
scripts/aurawa-docker-build.sh

# Choose the image name; any further arguments go to `docker build`.
scripts/aurawa-docker-build.sh aurawa-test:local
scripts/aurawa-docker-build.sh aurawa-test:local --no-cache
```

The script derives the identity from git:

| Checkout state                                 | `AURAWA_VERSION`                 | `AURAWA_REVISION`  |
| ---------------------------------------------- | -------------------------------- | ------------------ |
| Clean, exactly at tag `v0.24.0-aurawa.1`       | `0.24.0-aurawa.1`                | `<full sha>`       |
| Clean, any other commit                        | `0.24.0-aurawa.dev.<sha7>`       | `<full sha>`       |
| Uncommitted or untracked (non-ignored) changes | `0.24.0-aurawa.dev.<sha7>.dirty` | `<full sha>-dirty` |

A plain `docker build .` still works and produces the same application, but its labels read `dev` / `unknown`, which
marks it as an unidentified build. Use the script for anything that will be tested or deployed.

Check what an image is:

```bash
docker image inspect aurawa:0.24.0-aurawa.1 \
  --format '{{index .Config.Labels "org.opencontainers.image.version"}} {{index .Config.Labels "org.opencontainers.image.revision"}}'
docker run --rm --entrypoint printenv aurawa:0.24.0-aurawa.1 AURAWA_VERSION AURAWA_REVISION
```

## Repository automation

| Workflow                                 | Trigger                              | What it does in AuraWa                                                                                                                                                                                                                                                                                                |
| ---------------------------------------- | ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci.yml`                                 | push / pull request to `main`        | Every upstream validation gate (lint, type-check, audits, unit, e2e, PostgreSQL, dashboard, shell scripts, chart, actionlint), then a two-architecture image build with the non-root, graceful-stop and engine-library smoke tests. **Never logs in to a registry or pushes an image.**                               |
| `release.yml`                            | push of a tag matching `v*-aurawa.*` | Validates the tag against `package.json`, re-runs the gates, pushes a staging image to GHCR, boot-smokes and Trivy-scans it on amd64 and arm64, attests provenance, then promotes the tested digest to `<version>` and (non-prereleases only) `latest`, verifies the tags anonymously and creates the GitHub Release. |
| `security-scan.yml`                      | weekly (Wednesday 03:00 UTC), manual | `npm audit` of both dependency trees, base-image digest drift check, and a Trivy scan of `latest` once a stable AuraWa release exists (skipped with a notice before that).                                                                                                                                            |
| `sdk-ci.yml`                             | changes under `sdk/`                 | SDK tests, unchanged.                                                                                                                                                                                                                                                                                                 |
| `*-sdk-release.yml`, `split-php-sdk.yml` | SDK tags / `sdk/php` pushes          | Publishing jobs run **only** in the upstream repository (`rmyndharis/OpenWA`): the SDK packages are upstream-owned. The PHP SDK tests in `split-php-sdk.yml` still run.                                                                                                                                               |
| Dependabot                               | weekly / monthly                     | npm (root and dashboard), GitHub Actions pins, the Dockerfile base digest and the compose images, unchanged from upstream.                                                                                                                                                                                            |

The only path that publishes an image is a pushed AuraWa release tag. An ordinary push to `main`, a pull request, an
SDK tag or an imported upstream tag cannot publish anything.

## Cutting a release (when one is wanted)

No release has been made yet. When one is:

1. Make sure `main` is green in CI and `UPSTREAM.md` lists every AuraWa change.
2. Tag the commit and push the tag:

   ```bash
   git tag -a v0.24.0-aurawa.1 -m "AuraWa 0.24.0-aurawa.1"
   git push origin v0.24.0-aurawa.1
   ```

3. Watch the Release workflow. It publishes `ghcr.io/rohanbthrust24-glitch/aurawa:0.24.0-aurawa.1` (and `latest` for a
   non-prerelease) only after the boot smoke and the image scan pass.

First-release notes:

- GHCR creates the `aurawa` package on the first push. If GitHub creates it as private, the anonymous
  `verify-published` job fails even though the image was promoted; set the package's visibility to public in the
  package settings (or keep it private and accept that job's failure) and re-run the job.
- `RELEASE_PAT` is optional; without it the GitHub Release is authored by `github-actions[bot]`.
- A prerelease tag (`v0.24.0-aurawa.1-rc.1`) publishes only its exact tag, which is the safe way to produce an image
  for staging tests before it becomes `latest`.

## Re-basing onto a newer upstream release

1. Copy the new upstream tag's tracked files over the tree (the same method recorded in `UPSTREAM.md`), then re-apply
   the AuraWa changes listed there.
2. `package.json` now carries the new upstream version; AuraWa versions restart at `-aurawa.1`.
3. Update `UPSTREAM.md` (version, commit, tree, date, change list) and the base version named in the README notice.
4. Run CI, then tag.
