#!/bin/sh
# cold-probe.sh — run INSIDE a fresh container; measures daemon warm-up time.
# Starts the daemon at T0, registers the roster, activates the hook, then
# sends a probe every 5s until the first nudge lands; prints elapsed seconds.
set -u
T0=$(date +%s)
/root/.atm-probe-marker 2>/dev/null
nohup atm-daemon > /tmp/atm-daemon.log 2>&1 &
export ATM_IDENTITY=stub-beta ATM_TEAM=testbed
while [ ! -f /root/.atm/daemon/local-http.json ]; do sleep 0.2; done
echo "endpoint record at +$(( $(date +%s) - T0 ))s"
atm teams add-member testbed stub-alpha --agent-type stub --home-dir /opt/testbed >/dev/null 2>&1
atm teams update-member testbed stub-alpha --workspace-root /opt/testbed --harness hermes >/dev/null 2>&1
atm teams add-member testbed stub-beta --agent-type stub --home-dir /opt/testbed >/dev/null 2>&1
atm teams update-member testbed stub-beta --workspace-root /opt/testbed --harness hermes >/dev/null 2>&1
/opt/hermes/.venv/bin/python /opt/testbed/test-seam.py >/tmp/probe.log 2>&1 &
SEAM_PID=$!
i=0
while [ $i -lt 24 ]; do
  sleep 5
  i=$((i+1))
  if tail -1 /tmp/probe.log | grep -q "^PASS"; then
    echo "FIRST NUDE DELIVERY at +$(( $(date +%s) - T0 ))s"
    tail -2 /tmp/probe.log
    kill $SEAM_PID 2>/dev/null
    exit 0
  fi
done
echo "no delivery within 120s"; tail -3 /tmp/probe.log; exit 1
