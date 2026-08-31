#!/bin/sh
# setup-peer.sh — container-side cross-host peer wiring (AR item 7, AT3).
# Run INSIDE the container after run.sh --peer. Usage:
#   setup-peer.sh <mac-host> <mac-cert-fingerprint>
# 1. Rebinds the peer interface: 0.0.0.0:43101 + advertise-host matching the
#    container cert (hermes-testbed.local; SAN also covers localhost).
# 2. Adds the Mac as a trusted peer (hostname + cert pin, per trust model).
# 3. Restarts the daemon so the new bind takes effect.
set -eu
MAC_HOST="${1:?usage: setup-peer.sh <mac-host> <mac-fingerprint>}"
MAC_FP="${2:?usage: setup-peer.sh <mac-host> <mac-fingerprint>}"

# advertise-host = localhost: the container cert's SAN covers DNS:localhost,
# so the Mac can dial localhost:<published-port> with fingerprint pinning —
# no /etc/hosts alias needed on the host side.
atm peer interface set --bind 0.0.0.0:43101 --advertise-host localhost --enabled >/dev/null
atm peer trust add --host "$MAC_HOST" --fingerprint "$MAC_FP" --https-port 43101 --yes >/dev/null

pkill -9 -x atm-daemon 2>/dev/null || true
sleep 1
rm -f /root/.atm/daemon/owner.lock /root/.atm/daemon/local-http.json
nohup atm-daemon > /tmp/atm-daemon.log 2>&1 &
i=0
while [ $i -lt 30 ]; do
  [ -f /root/.atm/daemon/local-http.json ] && break
  sleep 1; i=$((i+1))
done
[ -f /root/.atm/daemon/local-http.json ] || { echo "FATAL: daemon did not start"; head -5 /tmp/atm-daemon.log; exit 1; }
chmod -R a+rX /root/.atm/daemon 2>/dev/null || true
chmod -R a+rwX /root/.atm/db /root/.atm/logs 2>/dev/null || true
echo "peer mode configured: advertise=hermes-testbed.local, trusted=$MAC_HOST"
