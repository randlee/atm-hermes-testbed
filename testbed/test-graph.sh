#!/bin/sh
# test-graph.sh — run the infrastructure-verification matrix INSIDE the
# container. Usage: test-graph.sh [tier-a|tier-b|tier-c|tier-d|all] [run-suffix]
# Deterministic: every suite uses fresh team names keyed on the suffix.
# Each suite emits a machine-readable result at /opt/testbed/results/tier-<x>.json
# (schema v1, citable as AR evidence).
set -eu
PY=/opt/hermes/.venv/bin/python
SUFFIX="${2:-$(date +%s)}"
TIER="${1:-all}"
RC=0

run_suite() {
  echo "=========================================="
  echo "SUITE: $1 ($SUFFIX)"
  echo "=========================================="
  "$PY" "$2" "$SUFFIX" || RC=1
}

# atm 1.4.4+ hard requirement: mTLS peer interface + local TLS identity must
# exist BEFORE the daemon starts (otherwise: "mTLS requires one enabled peer
# interface" / "configured local identity"). Run it here only if the daemon
# is not up yet (it writes the peer config tables directly); a running daemon
# means config is already complete. Canonical fresh-run order:
#   run.sh -> harness/setup-mtls.sh -> atm-daemon -> test-graph.sh
if ! pgrep -f '[a]tm-daemon' >/dev/null 2>&1 && [ -x /opt/testbed/harness/setup-mtls.sh ]; then
  /opt/testbed/harness/setup-mtls.sh || echo "WARN: mTLS bootstrap failed"
fi

if [ "$TIER" = "tier-a" ] || [ "$TIER" = "all" ]; then
  run_suite "TIER-A mailbox semantics" /opt/testbed/test-tier-a.py
fi
if [ "$TIER" = "tier-b" ] || [ "$TIER" = "all" ]; then
  run_suite "TIER-B seam + envelope fidelity" /opt/testbed/test-tier-b.py
fi
if [ "$TIER" = "tier-c" ] || [ "$TIER" = "all" ]; then
  run_suite "TIER-C tmux surface" /opt/testbed/test-tier-c.py
fi
if [ "$TIER" = "tier-d" ] || [ "$TIER" = "all" ]; then
  run_suite "TIER-D herdr surface" /opt/testbed/test-tier-d.py
fi

echo "=========================================="
echo "results:"
ls -1 /opt/testbed/results/*.json 2>/dev/null || echo "(none)"
if [ "$RC" -eq 0 ]; then
  echo "MATRIX VERDICT: PASS"
else
  echo "MATRIX VERDICT: FAIL"
fi
exit "$RC"
