#!/bin/sh
# hermes-docker-testbed — run script
# Usage: ./run.sh [--persist NAME] [--gateway] [--peer MAC_NAME] [--release-proof]
# Env: TESTBED_PLATFORM=amd64 (default) | arm64 (native arm64, from 1.4.6 on)
# Isolation guarantees (non-negotiable):
#   - NO host mounts: hermes state = /opt/data, atm state = /root/.atm (in-container)
#   - env: ONLY env/allowlist.env (if present & non-empty); never the host ~/.hermes/.env
# Peer mode (--peer): the ONE documented wall exception (AR item 7, agreed with
# fenix@atm-dev) — publishes 43101 (atm peer https) + 2222 (sshd, key-only)
# and maps MAC_NAME to the host for hostname-based peer trust. OFF by default.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME=hermes-testbed

# Secret-file guard (rand's bulletproof rule, requested by fenix@atm-dev):
# refuse to run if env/allowlist.env has ever been committed/tracked.
if git -C "$HERE" ls-files --error-unmatch env/allowlist.env >/dev/null 2>&1; then
  echo "FATAL: env/allowlist.env is TRACKED BY GIT — secret file must never"
  echo "be committed. git rm --cached env/allowlist.env and re-add via ignore."
  exit 1
fi
PERSIST=""
PEER=""
RELEASE_PROOF=0
ARGS=""
TESTBED_PLATFORM="${TESTBED_PLATFORM:-amd64}"
case "$TESTBED_PLATFORM" in
  amd64) DOCKER_PLAT=linux/amd64 ;;
  arm64) DOCKER_PLAT=linux/arm64 ;;
  *) echo "FATAL: TESTBED_PLATFORM must be amd64 or arm64"; exit 1 ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --persist) PERSIST="$2"; shift 2 ;;
    --gateway) ARGS="$ARGS -e HERMES_GATEWAY=1"; shift ;;
    --peer) PEER="$2"; shift 2 ;;
    --release-proof) RELEASE_PROOF=1; shift ;;
    *) echo "unknown arg: $1"; exit 1 ;;
  esac
done

if [ "$RELEASE_PROOF" -eq 1 ]; then
  MISSING=""
  [ -n "${ATM_CORE_SHA:-}" ] || MISSING="$MISSING ATM_CORE_SHA"
  [ -n "${CI_RUN_ID:-}" ] || MISSING="$MISSING CI_RUN_ID"
  [ -n "${HERMES_FORK_SHA:-}" ] || MISSING="$MISSING HERMES_FORK_SHA"
  if [ -n "$MISSING" ]; then
    echo "FATAL: --release-proof requires:$MISSING" >&2
    exit 1
  fi
  ARGS="$ARGS -e ATM_CORE_SHA -e CI_RUN_ID -e HERMES_FORK_SHA -e TESTBED_RELEASE_PROOF=1"
fi

# env allowlist — only if the file exists and has at least one non-empty value
# (BRE pitfall: `+` is literal in grep without -E — use -E here)
ENVFILE="$HERE/env/allowlist.env"
if [ -f "$ENVFILE" ] && grep -Eq '^[A-Z_][A-Z_0-9]*=[^[:space:]]' "$ENVFILE"; then
  ARGS="$ARGS --env-file $ENVFILE"
fi

docker rm -f "$NAME" >/dev/null 2>&1 || true
if [ -n "$PERSIST" ]; then
  docker volume create "$PERSIST" >/dev/null
  ARGS="$ARGS -v $PERSIST:/opt/data"
fi

if [ -n "$PEER" ]; then
  # Wall exception: two published ports + hostname mapping for peer trust.
  # --add-host wants an IP/keyword: host-gateway resolves to the host from
  # inside the VM on every docker backend (colima included).
  # NOTE: host port 43101 is owned by the Mac's own atm-daemon, so the
  # container's peer interface publishes on HOST port 43102 (container 43101).
  # The host trust entry for this fixture must use --https-port 43102.
  HOST_IP="${PEER_HOST_IP:-host-gateway}"
  ARGS="$ARGS -p ${PEER_HTTP_PORT:-43102}:43101 -p 2222:22 --add-host ${PEER}:${HOST_IP}"
  echo "PEER MODE: ports ${PEER_HTTP_PORT:-43102}->43101, 2222->22 published, --add-host ${PEER}:${HOST_IP}"
  echo "  ssh: ssh -p 2222 -i <testbed key> root@localhost   (key-only)"
fi

IMAGE_TAG=loki/hermes-testbed:testbed
IMAGE_ID=$(docker image inspect "$IMAGE_TAG" --format '{{.Id}}')
docker run -d --name "$NAME" --platform "$DOCKER_PLAT" \
  -e TESTBED_IMAGE_TAG="$IMAGE_TAG" -e TESTBED_IMAGE_ID="$IMAGE_ID" \
  $ARGS "$IMAGE_TAG"
echo "started: $NAME (platform: $DOCKER_PLAT)"
sleep 8
# atm 1.4.4+ hard startup requirement: mTLS peer interface + local identity
# must exist before the daemon starts (harness/setup-mtls.sh, idempotent).
docker exec "$NAME" sh -c '[ -x /opt/testbed/harness/setup-mtls.sh ] && /opt/testbed/harness/setup-mtls.sh' \
  2>&1 | tail -2 || true
docker logs "$NAME" 2>&1 | head -20
echo "---"
docker exec "$NAME" sh -c 'hermes --version; atm --version; herdr --version' 2>&1 | head -3

if [ -n "$PEER" ]; then
  # sshd only runs in peer mode (default runs stay fully walled)
  docker exec "$NAME" sh -c 'mkdir -p /run/sshd && /usr/sbin/sshd' || \
    echo "WARN: sshd failed to start in peer mode"
  # Extract the throwaway peer private key for the Mac's ssh config
  mkdir -p "$HERE/env"
  docker cp "$NAME:/root/.ssh/testbed_peer_key" "$HERE/env/peer-key" 2>/dev/null && \
    chmod 600 "$HERE/env/peer-key" && echo "  peer key extracted: env/peer-key"
fi
