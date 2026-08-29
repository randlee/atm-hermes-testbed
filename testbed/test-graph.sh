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
