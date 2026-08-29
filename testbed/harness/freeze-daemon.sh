#!/bin/sh
# AT8 harness hook (fenix@atm-dev AT8 send-timeout-truth).
# Induces a deterministic client send timeout while the daemon still persists:
# SIGSTOP the daemon for N seconds (default 4; AT8 client budget is 3.25s),
# then SIGCONT. Run in the background immediately before the send that must
# time out:
#   /opt/testbed/harness/freeze-daemon.sh 4 &
set -eu
SECS="${1:-4}"
PID=$(pgrep -f '[a]tm-daemon' | head -1)
if [ -z "$PID" ]; then
  echo "FAIL: no atm-daemon process found" >&2
  exit 1
fi
kill -STOP "$PID"
sleep "$SECS"
kill -CONT "$PID"
echo "daemon pid $PID frozen ${SECS}s and resumed"
