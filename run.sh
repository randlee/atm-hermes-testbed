#!/bin/sh
# hermes-docker-testbed — run script
# Usage: ./run.sh [--persist NAME] [--gateway] [--peer MAC_NAME]
# Isolation guarantees (non-negotiable):
#   - NO host mounts: hermes state = /opt/data, atm state = /root/.atm (in-container)
#   - env: ONLY env/allowlist.env (if present & non-empty); never the host ~/.hermes/.env
# Peer mode (--peer): the ONE documented wall exception (AR item 7, agreed with
# fenix@atm-dev) — publishes 43101 (atm peer https) + 2222 (sshd, key-only)
# and maps MAC_NAME to the host for hostname-based peer trust. OFF by default.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME=hermes-testbed
PERSIST=""
PEER=""
ARGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --persist) PERSIST="$2"; shift 2 ;;
    --gateway) ARGS="$ARGS -e HERMES_GATEWAY=1"; shift ;;
    --peer) PEER="$2"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 1 ;;
  esac
done

# env allowlist — only if the file exists and has at least one non-empty value
ENVFILE="$HERE/env/allowlist.env"
if [ -f "$ENVFILE" ] && grep -q '^[A-Z_]*=.+' "$ENVFILE"; then
  ARGS="$ARGS --env-file $ENVFILE"
fi

docker rm -f "$NAME" >/dev/null 2>&1 || true
if [ -n "$PERSIST" ]; then
  docker volume create "$PERSIST" >/dev/null
  ARGS="$ARGS -v $PERSIST:/opt/data"
fi

if [ -n "$PEER" ]; then
  # Wall exception: two published ports + hostname mapping for peer trust.
  HOST_IP="${PEER_HOST_IP:-host.docker.internal}"
  ARGS="$ARGS -p 43101:43101 -p 2222:22 --add-host ${PEER}:${HOST_IP}"
  echo "PEER MODE: ports 43101/2222 published, --add-host ${PEER}:${HOST_IP}"
  echo "  ssh: ssh -p 2222 -i <testbed key> root@localhost   (key-only)"
fi

docker run -d --name "$NAME" --platform linux/amd64 $ARGS loki/hermes-testbed:testbed
echo "started: $NAME"
sleep 8
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
