#!/bin/sh
# Smoke test: `docker stop` runs the app's graceful shutdown instead of ending in a SIGKILL.
# Usage: OPENWA_SMOKE_IMAGE=<image> ./scripts/smoke-test-graceful-stop.sh
# Requires Docker. Needs no network and no WhatsApp account.
#
# dumb-init stays PID 1 as root and forwards SIGTERM to the openwa process the entrypoint dropped to
# with gosu. Signalling another uid needs CAP_KILL, so under the compose hardening (cap_drop ALL) the
# forward is refused unless KILL is re-added: the app never sees the signal, its drain never runs, and
# Docker SIGKILLs the container when the grace period runs out. This starts the image with the same
# hardening as the openwa-api service in docker-compose.yml, then checks that the app runs as openwa,
# that SIGTERM reaches it (its drain logs appear), and that it exits 0 well before the stop timeout.
# OPENWA_SMOKE_CAP_ADD overrides the capability list, e.g. to show the failure without KILL.
set -e

export DOCKER_BUILDKIT=1

IMAGE_TAG="${OPENWA_SMOKE_IMAGE:-openwa-test-graceful-stop:smoke}"
BUILT_HERE=0
# The openwa-api cap_add list in docker-compose.yml; ci-privilege-gate.spec.ts keeps the two equal.
CAP_ADD="${OPENWA_SMOKE_CAP_ADD:-CHOWN DAC_OVERRIDE FOWNER KILL SETGID SETUID}"
# The drain takes a few seconds with no sessions (SHUTDOWN_DELAY_MS defaults to 3s in production).
# Anything near STOP_TIMEOUT means Docker had to SIGKILL, which is the failure this test exists for.
STOP_TIMEOUT=60
MAX_STOP_SECONDS=30
NAME="openwa-smoke-graceful-$$"

if [ -z "${OPENWA_SMOKE_IMAGE:-}" ]; then
  BUILT_HERE=1
  echo "==> Building test image..."
  docker build -t "$IMAGE_TAG" .
else
  echo "==> Using pre-built image: $IMAGE_TAG"
fi

cleanup() {
  docker rm -f "$NAME" > /dev/null 2>&1 || true
  if [ "$BUILT_HERE" -eq 1 ]; then
    docker rmi "$IMAGE_TAG" > /dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  echo "---- container log (last 40 lines) ----" >&2
  docker logs "$NAME" 2>&1 | tail -40 >&2 || true
  exit 1
}

CAP_ARGS=""
for cap in $CAP_ADD; do
  CAP_ARGS="$CAP_ARGS --cap-add $cap"
done
# A throwaway admin key, so a first boot does not generate one and print it to the log.
KEY=$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')

echo ""
echo "==> Starting the image with the openwa-api hardening (cap_add: $CAP_ADD)..."
# shellcheck disable=SC2086 # CAP_ARGS is a list of flags and must split into words
docker run -d --name "$NAME" --network none --read-only --tmpfs /tmp --tmpfs /app/data \
  --security-opt no-new-privileges:true --cap-drop ALL $CAP_ARGS \
  -e NODE_ENV=production -e API_MASTER_KEY="$KEY" \
  -e HOME=/tmp -e XDG_CONFIG_HOME=/tmp/.config -e XDG_CACHE_HOME=/tmp/.cache \
  "$IMAGE_TAG" > /dev/null

READY=0
for _ in $(seq 1 45); do
  if docker exec "$NAME" curl -sf http://localhost:2785/api/health/ready > /dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 2
done
[ "$READY" -eq 1 ] || fail "the app did not become ready within 90s"
echo "PASS: the app is ready"

APP_USER=$(docker exec "$NAME" sh -c 'ps -o user= -p "$(pgrep -o -x node)"' | tr -d ' ')
[ "$APP_USER" = "openwa" ] || fail "node runs as '$APP_USER', expected openwa"
echo "PASS: node runs as openwa"

echo ""
echo "==> docker stop -t $STOP_TIMEOUT..."
START=$(date +%s)
docker stop -t "$STOP_TIMEOUT" "$NAME" > /dev/null
ELAPSED=$(( $(date +%s) - START ))
EXIT_CODE=$(docker inspect "$NAME" --format '{{.State.ExitCode}}')
echo "    stopped after ${ELAPSED}s with exit code $EXIT_CODE"

LOGS=$(docker logs "$NAME" 2>&1)
for line in 'Entering draining state' 'Graceful shutdown requested' 'Initiating shutdown'; do
  echo "$LOGS" | grep -q "$line" || fail "'$line' was never logged: SIGTERM did not reach the app"
done
echo "PASS: SIGTERM reached the app and its graceful drain ran"

[ "$EXIT_CODE" = "0" ] || fail "exit code $EXIT_CODE (137 means Docker had to SIGKILL)"
[ "$ELAPSED" -lt "$MAX_STOP_SECONDS" ] || fail "the stop took ${ELAPSED}s, close to the ${STOP_TIMEOUT}s timeout"
echo "PASS: exited 0 in ${ELAPSED}s, well before the ${STOP_TIMEOUT}s timeout"

echo ""
echo "Graceful stop smoke test passed"
