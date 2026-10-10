#!/usr/bin/env bash
#
# AuraWa local image build.
#
# Builds the production image from this checkout with its identity baked in: the AuraWa version and
# the exact git commit land in the image's OCI labels and in AURAWA_VERSION / AURAWA_REVISION, so
# any image can be traced back to the source it was built from (docs/aurawa/building.md).
#
# Usage: scripts/aurawa-docker-build.sh [image-ref] [extra docker build args...]
#   image-ref defaults to aurawa:<version>; a first argument starting with '-' is a docker build
#   option, not an image-ref (scripts/aurawa-docker-build.sh --no-cache).
#
# Version:  a clean checkout exactly at an AuraWa release tag (v0.24.0-aurawa.1) builds that
#           version (0.24.0-aurawa.1); anything else builds <package.json version>-aurawa.dev.<sha>.
# Revision: the full commit SHA, with a -dirty suffix when tracked or untracked (non-ignored)
#           files differ from that commit, because then the image is not that commit's source.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

base="$(sed -n 's/^  "version": "\([^"]*\)",$/\1/p' package.json | head -n 1)"
if [ -z "$base" ]; then
  echo "aurawa-docker-build: could not read the version from package.json" >&2
  exit 1
fi

sha="$(git rev-parse HEAD)"
short="$(git rev-parse --short=7 HEAD)"
# --no-optional-locks: a status read must not rewrite the index of the checkout being built.
dirty=""
if [ -n "$(git --no-optional-locks status --porcelain)" ]; then
  dirty="yes"
fi

tag="$(git tag --points-at HEAD --list "v${base}-aurawa.*" | head -n 1)"
if [ -n "$tag" ] && [ -z "$dirty" ]; then
  version="${tag#v}"
else
  version="${base}-aurawa.dev.${short}${dirty:+.dirty}"
fi
revision="${sha}${dirty:+-dirty}"

image="aurawa:${version}"
if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
  image="$1"
  shift
fi

echo "Building ${image}"
echo "  AURAWA_VERSION=${version}"
echo "  AURAWA_REVISION=${revision}"
docker build \
  --build-arg "AURAWA_VERSION=${version}" \
  --build-arg "AURAWA_REVISION=${revision}" \
  --tag "$image" \
  "$@" \
  .
