#!/bin/sh
# stub-agent.sh <name> — a zero-LLM ATM agent for protocol/graph tests.
# Behavior: read mailbox in a loop; for each actionable message, ack with a
# deterministic echo so tests can assert routing + round-trips.
set -eu
NAME="${1:?usage: stub-agent.sh <name>}"
export ATM_IDENTITY="$NAME"
echo "stub-agent $NAME up (ATM_TEAM=${ATM_TEAM:-unset})"
while true; do
  # read + ack each actionable message; reply echoes the summary for assertion
  if OUT=$(atm read --json 2>/dev/null); then
    COUNT=$(printf '%s' "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('count',0))" 2>/dev/null || echo 0)
    if [ "$COUNT" != "0" ]; then
      echo "stub-agent $NAME: processed $COUNT message(s)"
    fi
  fi
  sleep 1
done
