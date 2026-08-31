#!/bin/sh
# AT4 harness hook (fenix@atm-dev AT4 daemon-restart-in-session).
# Restarts the containerized atm-daemon with zero manual steps: kill the
# running daemon (match the binary, never a wrapper), clear the stale owner
# lock, relaunch detached, wait-gate on the endpoint record.
# Self-elevates: prompt agents run non-root but the daemon is root-owned
# (sudoers scope: this exact path only).
if [ "$(id -u)" != 0 ]; then
  exec sudo "$0" "$@"
fi
set -eu
# Exact-name kill: -f matches the full command line, which would hit the
# calling agent itself (its argv carries the AT4 prompt text mentioning
# atm-daemon). -x matches the daemon's comm exactly.
pkill -9 -x atm-daemon 2>/dev/null || true
sleep 1
rm -f /root/.atm/daemon/owner.lock
nohup atm-daemon > /tmp/atm-daemon.log 2>&1 &
i=0
while [ $i -lt 60 ]; do
  if [ -f /root/.atm/daemon/local-http.json ]; then
    # The daemon republishes the endpoint record 0600 on every start.
    # Re-open read access for non-root prompt agents (the AT4 agent keeps
    # using the daemon after this restart — its session must survive it).
    chmod -R a+rX /root/.atm/daemon 2>/dev/null || true
    chmod -R a+rwX /root/.atm/db /root/.atm/logs 2>/dev/null || true
    echo "daemon restarted (endpoint record published)"
    exit 0
  fi
  sleep 1; i=$((i+1))
done
echo "FAIL: daemon did not republish local-http.json within 60s" >&2
exit 1
