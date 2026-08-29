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
#                                   # is delayed past the 3.25s budget ->
#                                   # the write landed despite the timeout
#                                   #                                   (branch b).
# Run in the background immediately before the send under test:
#   /opt/testbed/harness/freeze-daemon.sh 4 &
#   /opt/testbed/harness/freeze-daemon.sh 4 --after 300 &
set -eu
SECS="${1:-4}"
AFTER_MS=""
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --after) AFTER_MS="$2"; shift 2 ;;
    *) shift ;;
  esac
done
PID=$(pgrep -f '[a]tm-daemon' | head -1)
if [ -z "$PID" ]; then
  echo "FAIL: no atm-daemon process found" >&2
  exit 1
fi
if [ -n "$AFTER_MS" ]; then
  sleep "$(awk "BEGIN { printf \"%.3f\", $AFTER_MS / 1000 }")"
fi
kill -STOP "$PID"
sleep "$SECS"
kill -CONT "$PID"
echo "daemon pid $PID frozen ${SECS}s${AFTER_MS:+ (after ${AFTER_MS}ms)} and resumed"
