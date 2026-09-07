#!/bin/sh
# AT8 harness hook (fenix@atm-dev AT8 send-timeout-truth).
# SIGSTOPs the atm-daemon process for N seconds (default 4), then SIGCONTs it.
# The client's absolute request budget in the fixture is 3.25s.
#
# Two timing variants select the AT8 branch under test:
#   freeze-daemon.sh 4              # freeze BEFORE the send is issued.
#                                   # The daemon never reads the request -> the
#                                   # write is genuinely lost, the client's
#                                   # ATM_WAIT_TIMEOUT is truthful  (branch a).
#   freeze-daemon.sh 4 --after 300  # sleep <ms> first, THEN freeze, so the
#                                   # send has started and the daemon has
#                                   # accepted+persisted it, but its response
#                                   # is delayed past the 3.25s budget -> the
#                                   # write landed despite the timeout (branch b).
#
# NO-SUDO execution model (solar@atm-dev P0 ruling, 2026-09-07): invoked OUT
# OF BAND by the outer coordinator via `docker exec hermes-testbed ...` (root
# by default; no sudo/sudoers). Two coordination modes:
#   --trigger <file>  ARM-AND-WAIT: hook arms immediately, then waits for the
#                     unprivileged agent to `touch <file>` right before its
#                     send (the agent's own timing, no cross-boundary race).
#                     With --after, the <ms> delay starts at trigger time —
#                     this is what makes branch (b) deterministic under the
#                     no-sudo model.
#   (no --trigger)    legacy immediate mode for coordinator-timed runs.
# Writes markers/at8-armed when armed and markers/at8-done after SIGCONT.
if [ "$(id -u)" != 0 ]; then
  echo "FATAL: must run as root via docker exec (no-sudo model); refusing" >&2
  exit 1
fi
set -eu
SECS="${1:-4}"
AFTER_MS=""
TRIGGER=""
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --after) AFTER_MS="$2"; shift 2 ;;
    --trigger) TRIGGER="$2"; shift 2 ;;
    *) shift ;;
  esac
done
MARKERS=/opt/testbed/results/markers
mkdir -p "$MARKERS"
chmod 777 "$MARKERS" 2>/dev/null || true
rm -f "$MARKERS/at8-armed" "$MARKERS/at8-done"
PID=$(pgrep -f '[a]tm-daemon' | head -1)
if [ -z "$PID" ]; then
  echo "FAIL: no atm-daemon process found" >&2
  exit 1
fi
date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKERS/at8-armed"
chmod 666 "$MARKERS/at8-armed" 2>/dev/null || true
if [ -n "$TRIGGER" ]; then
  rm -f "$TRIGGER"
  i=0
  while [ $i -lt 300 ]; do
    [ -f "$TRIGGER" ] && break
    sleep 0.1; i=$((i+1))
  done
  if [ ! -f "$TRIGGER" ]; then
    echo "FAIL: trigger $TRIGGER never appeared (30s)" >&2
    exit 1
  fi
fi
if [ -n "$AFTER_MS" ]; then
  sleep "$(awk "BEGIN { printf \"%.3f\", $AFTER_MS / 1000 }")"
fi
kill -STOP "$PID"
sleep "$SECS"
kill -CONT "$PID"
date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKERS/at8-done"
chmod 666 "$MARKERS/at8-done" 2>/dev/null || true
echo "daemon pid $PID frozen ${SECS}s${AFTER_MS:+ (after ${AFTER_MS}ms)}${TRIGGER:+ (trigger $TRIGGER)} and resumed"
