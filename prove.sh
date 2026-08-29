#!/bin/sh
# prove.sh — one-command phase-1 seam proof from the host.
# Boots the container, starts the daemon the proven way (detached shell),
# waits out the warm-up empirically required under x86_64 emulation, then
# runs the in-container seam test and prints the verdict.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME=hermes-testbed

echo "== boot =="
"$HERE/run.sh" >/dev/null 2>&1 || "$HERE/run.sh"
echo "container up; settling 15s past s6 stage-2..."
sleep 15

echo "== daemon (detached shell launch) =="
# NOTE: pgrep/pkill -f 'atm-daemon' self-matches this wrapper's own cmdline —
# match the full binary path instead, and key "is it healthy" on the record file.
docker exec "$NAME" sh -c "pkill -9 -f '[a]tm-daemon' 2>/dev/null; sleep 1; rm -f /root/.atm/daemon/owner.lock"
docker exec -d "$NAME" sh -c 'atm-daemon > /tmp/atm-daemon.log 2>&1'
i=0
while [ $i -lt 80 ]; do
  if docker exec "$NAME" test -f /root/.atm/daemon/local-http.json 2>/dev/null; then break; fi
  sleep 1; i=$((i+1))
done
docker exec "$NAME" test -f /root/.atm/daemon/local-http.json || { echo "FAIL: daemon never published endpoint record"; docker exec "$NAME" tail -5 /tmp/atm-daemon.log; exit 1; }
echo "endpoint record published."

echo "== warm-up (45s) =="
sleep 45

echo "== seam test =="
docker exec "$NAME" /opt/hermes/.venv/bin/python /opt/testbed/test-seam.py
RC=$?
echo "== verdict: $([ $RC -eq 0 ] && echo PASS || echo FAIL) =="
exit $RC
