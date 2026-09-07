#!/bin/sh
# at8-calibrate.sh — HGC-023 RTT calibration marker reader (coordinator-side).
# fenix authorization 01M1WXW9R9Z7KH69CDVR4F6122; draft 01M1WXZXVH1A178ARNNQE3NX72.
#
# Runs on the HOST (coordinator) or anywhere with the markers dir mounted.
# Waits (bounded) for the fixture agent's markers/at8-rtt, validates it, and
# prints the calibrated freeze delay for freeze-daemon.sh --after:
#
#   after_ms = clamp( (rtt_ms + 1) / 2 , 300, 1500 )      # nearest int half
#
# Contract (fail-closed, never default/tune/retry):
#   - marker file contract: ASCII digits + trailing newline ONLY
#   - validation: regex ^[0-9]+$ and numeric range 1..60000
#   - missing or invalid  -> exit 1, stderr EXACTLY:
#       FAIL: calibration marker missing/invalid
#   - success -> stdout: "after_ms=<n> source_rtt_ms=<n>"
#
# Env overrides (deterministic helper tests use these; production defaults
# are the contract values):
#   MARKERS_DIR  default /opt/testbed/results/markers
#   WAIT_S       default 120   (bounded wait for the marker to appear)
set -eu
MARKERS="${MARKERS_DIR:-/opt/testbed/results/markers}"
WAIT_S="${WAIT_S:-120}"
RTT_FILE="$MARKERS/at8-rtt"

fail() { echo "FAIL: calibration marker missing/invalid" >&2; exit 1; }

# bounded wait: poll every 0.5s up to WAIT_S
deadline=$(( $(date +%s) + WAIT_S ))
while [ ! -f "$RTT_FILE" ]; do
  [ "$(date +%s)" -ge "$deadline" ] && fail
  sleep 0.5
done

RTT=$(cat "$RTT_FILE" 2>/dev/null || true)
# strip exactly one trailing newline; anything else (spaces, extra lines,
# non-digits) is invalid per the file contract.
RTT=$(printf '%s' "$RTT")
case "$RTT" in
  ''|*[!0-9]*) fail ;;
esac
# numeric range 1..60000
[ "$RTT" -ge 1 ] 2>/dev/null || fail
[ "$RTT" -le 60000 ] 2>/dev/null || fail

AFTER=$(( (RTT + 1) / 2 ))
[ "$AFTER" -lt 300 ] && AFTER=300
[ "$AFTER" -gt 1500 ] && AFTER=1500
echo "after_ms=$AFTER source_rtt_ms=$RTT"
