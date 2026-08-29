#!/bin/sh
# AT4 harness hook (fenix@atm-dev AT4 daemon-restart-in-session).
# Restarts the containerized atm-daemon with zero manual steps: kill the
# running daemon (match the binary, never a wrapper), clear the stale owner
# lock, relaunch detached, wait-gate on the endpoint record.
set -eu
pkill -9 -f '[a]tm-daemon' 2>/dev/null || true
sleep 1
rm -f /root/.atm/daemon/owner.lock
nohup atm-daemon > /tmp/atm-daemon.log 2>&1 &
i=0
while [ $i -lt 60 ]; do
  if [ -f /root/.atm/daemon/local-http.json ]; then
    echo "daemon restarted (endpoint record published)"
    exit 0
  fi
  sleep 1; i=$((i+1))
done
echo "FAIL: daemon did not republish local-http.json within 60s" >&2
exit 1
