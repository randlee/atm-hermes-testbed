#!/bin/sh
# AT4 harness hook (fenix@atm-dev AT4 daemon-restart-in-session).
# Restarts the containerized atm-daemon with zero manual steps: kill the
# running daemon (match the binary, never a wrapper), clear the stale owner
# lock, relaunch detached, wait-gate on the endpoint record.
#
# NO-SUDO execution model (solar@atm-dev P0 ruling, 2026-09-07): this hook is
# invoked OUT OF BAND by the outer coordinator via `docker exec hermes-testbed
# /opt/testbed/harness/restart-daemon.sh` (docker exec defaults to root; no
# sudo, no sudoers). The unprivileged fixture agent never calls it — it only
# touches markers/at4-ready and polls markers/at4-done (written below).
if [ "$(id -u)" != 0 ]; then
  echo "FATAL: must run as root via docker exec (no-sudo model); refusing" >&2
  exit 1
fi
set -eu
MARKERS=/opt/testbed/results/markers
mkdir -p "$MARKERS"
chmod 777 "$MARKERS"
# Clear BOTH markers up front: a stale at4-ready from a previous run would
# fire the restart before the agent is in position.
rm -f "$MARKERS/at4-ready" "$MARKERS/at4-done"
# READY/DONE marker protocol (no-sudo model): the unprivileged agent signals
# it is mid-session by touching markers/at4-ready; we wait for it (bounded),
# restart, then write markers/at4-done. The agent polls at4-done and only
# then performs its post-restart ATM actions.
i=0
while [ $i -lt 120 ]; do
  [ -f "$MARKERS/at4-ready" ] && break
  sleep 1; i=$((i+1))
done
if [ ! -f "$MARKERS/at4-ready" ]; then
  echo "FAIL: markers/at4-ready never appeared (agent not in position)" >&2
  exit 1
fi
# Exact-name kill: -f matches the full command line, which would hit the
# calling agent itself (its argv carries the AT4 prompt text mentioning
# atm-daemon). -x matches the daemon's comm exactly.
pkill -9 -x atm-daemon 2>/dev/null || true
sleep 1
# Remove the STALE endpoint record so the wait-gate targets the NEW daemon's
# publish (without this, the loop sees the killed daemon's leftover file and
# chmods it — then the new daemon rewrites it 0600 afterwards).
rm -f /root/.atm/daemon/owner.lock /root/.atm/daemon/local-http.json
nohup atm-daemon > /tmp/atm-daemon.log 2>&1 &
i=0
while [ $i -lt 60 ]; do
  if [ -f /root/.atm/daemon/local-http.json ]; then
    sleep 1  # let the publish settle before re-opening perms
    # The daemon publishes the endpoint record 0600 on every start.
    # Re-open read access for non-root prompt agents (the AT4 agent keeps
    # using the daemon after this restart — its session must survive it).
    chmod -R a+rX /root/.atm/daemon 2>/dev/null || true
    chmod -R a+rwX /root/.atm/db /root/.atm/logs 2>/dev/null || true
    date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKERS/at4-done"
    chmod 666 "$MARKERS/at4-done" 2>/dev/null || true
    echo "daemon restarted (endpoint record published); at4-done written"
    exit 0
  fi
  sleep 1; i=$((i+1))
done
echo "FAIL: daemon did not republish local-http.json within 60s" >&2
exit 1
