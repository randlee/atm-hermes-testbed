#!/bin/sh
# hermes-docker-testbed — run script
# Usage: ./run.sh [--persist NAME] [--gateway] [--peer MAC_NAME] [--no-peer]
# Peer mode is ON by default with MAC_NAME = this host (hostname -s): the
# container daemon and the host daemon are cross-host peers from the start, so
# the oversight agent sends test sentences and receives reports over ATM.
# Env: TESTBED_PLATFORM=arm64|amd64 (default: host arch)
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
PEER="$(hostname -s)"
ARGS=""
# Default = host architecture (Apple Silicon -> arm64, Intel -> amd64); override only for a cross-arch run.
TESTBED_PLATFORM="${TESTBED_PLATFORM:-$(if [ "$(uname -m)" = arm64 ] || [ "$(uname -m)" = aarch64 ]; then echo arm64; else echo amd64; fi)}"
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
    --no-peer) PEER=""; shift ;;
    *) echo "unknown arg: $1"; exit 1 ;;
  esac
done

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

docker run -d --name "$NAME" --platform "$DOCKER_PLAT" $ARGS loki/hermes-testbed:testbed
echo "started: $NAME (platform: $DOCKER_PLAT)"
sleep 8
# atm 1.4.4+ hard startup requirement: mTLS peer interface + local identity
# must exist before the daemon starts (harness/setup-mtls.sh, idempotent).
docker exec "$NAME" sh -c '[ -x /opt/testbed/harness/setup-mtls.sh ] && /opt/testbed/harness/setup-mtls.sh' \
  2>&1 | tail -2 || true
docker logs "$NAME" 2>&1 | head -20
echo "---"
docker exec "$NAME" sh -c 'hermes --version 2>/dev/null; atm-daemon --version; herdr --version' 2>&1 | grep -vE '^(Install|$)' | head -4

if [ -n "$PEER" ]; then
  # Cross-host peer trust, both directions, every start. Nothing manual is left
  # except the one-time /etc/hosts line checked at the end.
  ATM_HOST_FP="$(atm peer certificate show --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["fingerprint"])')"
  docker exec "$NAME" sh -c "/opt/testbed/harness/setup-peer.sh '$PEER' '$ATM_HOST_FP'" 2>&1 | tail -1
  ATM_CONTAINER_FP="$(docker exec "$NAME" sh -c 'atm peer certificate show --json' | python3 -c 'import json,sys;print(json.load(sys.stdin)["fingerprint"])')"
  ATM_PEER_NAME="atm-hermes-testbed.local"
  if atm peer trust list --json | grep -q "\"$ATM_PEER_NAME\""; then
    atm peer trust replace --host "$ATM_PEER_NAME" --fingerprint "$ATM_CONTAINER_FP" --https-port "${PEER_HTTP_PORT:-43102}" --yes >/dev/null
  else
    atm peer trust add --host "$ATM_PEER_NAME" --fingerprint "$ATM_CONTAINER_FP" --https-port "${PEER_HTTP_PORT:-43102}" --yes >/dev/null
  fi
  echo "peer trust: host trusts $ATM_PEER_NAME:${PEER_HTTP_PORT:-43102}; container trusts $PEER"
  # The trust store is snapshotted at daemon start (crates/peer-tls): the host daemon must restart
  # to see a new or replaced fixture fingerprint (the image's cert changes on every image build).
  LABEL="$(launchctl list 2>/dev/null | awk '/com\.atm\.daemon/ {print $3; exit}')"
  if [ -n "$LABEL" ]; then
    launchctl kickstart -k "gui/$(id -u)/$LABEL" && echo "host daemon restarted ($LABEL)"
  else
    echo "WARN: no launchd atm-daemon found; restart the host daemon by hand so it loads the new trust entry"
  fi
  # Host -> container over the peer link needs the fixture name to resolve AND atm-core #1309
  # (the daemon dials the fixed port 43101, not the trust entry's 43102). Until #1309 lands the
  # link is used container -> host only (reports); sentences go in via `docker exec -i`. Warn, never stop.
  if ! grep -q "$ATM_PEER_NAME" /etc/hosts; then
    echo "note: /etc/hosts lacks '127.0.0.1 $ATM_PEER_NAME' (only needed for host->container sends, blocked by atm-core #1309 anyway)"
  fi
  # sshd only runs in peer mode (--no-peer runs stay fully walled)
  docker exec "$NAME" sh -c 'mkdir -p /run/sshd && /usr/sbin/sshd' || \
    echo "WARN: sshd failed to start in peer mode"
  # Extract the throwaway peer private key for the Mac's ssh config
  mkdir -p "$HERE/env"
  docker cp "$NAME:/root/.ssh/testbed_peer_key" "$HERE/env/peer-key" 2>/dev/null && \
    chmod 600 "$HERE/env/peer-key" && echo "  peer key extracted: env/peer-key"
fi

# Everything inside the container: daemon (after trust), perms, herdr, roster, hermes-atm hook,
# gateway restart, Claude Code tester via hmux. Rerunnable. See harness/bringup.sh.
docker exec -e TESTBED_CHAT_ID="${TESTBED_CHAT_ID:-1}" "$NAME" /opt/testbed/harness/bringup.sh 2>&1 | grep "^bringup:"
