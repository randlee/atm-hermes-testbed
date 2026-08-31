#!/bin/sh
# run-prompts.sh — Tier E prompt-suite executor (runs INSIDE the container).
# Usage: run-prompts.sh <prompt-id>   e.g. run-prompts.sh E0 | AT0 | AT3
# Prompts live at /opt/testbed/prompts/{hermes,atm-team}/<id>-*.md.
# Verdict source: the prompt-report-1 JSON the agent writes under /opt/testbed/results/.
set -eu
ID="${1:?usage: run-prompts.sh <prompt-id>}"
HERMES_PROMPT=$(ls /opt/testbed/prompts/hermes/${ID}-*.md 2>/dev/null | head -1)
AT_PROMPT=$(ls /opt/testbed/prompts/atm-team/${ID}-*.md 2>/dev/null | head -1)
RESULTS=/opt/testbed/results

# --- frontmatter helper: extract a YAML scalar from the prompt file
fm() { sed -n "s/^$2: *//p" "$1" | head -1 | tr -d '"' ; }

if [ -n "$HERMES_PROMPT" ]; then
  AGENT=hermes
  PROMPT="$HERMES_PROMPT"
elif [ -n "$AT_PROMPT" ]; then
  AGENT=claude-code
  PROMPT="$AT_PROMPT"
else
  echo "FATAL: no prompt found for id $ID"; exit 2
fi
MODEL=$(fm "$PROMPT" model)
TIMEOUT=$(fm "$PROMPT" timeout_s)
REPORT=$(fm "$PROMPT" report)
echo "prompt: $PROMPT (agent=$AGENT model=${MODEL:-default} timeout=${TIMEOUT:-300}s)"

[ -n "${ANTHROPIC_API_KEY:-}" ] || { echo "SKIP: ANTHROPIC_API_KEY not present"; exit 3; }

# hermes passes the model ID straight to the API — aliases 404 (verified:
# "haiku" → HTTP 404 model: haiku). Map aliases to real IDs; the anthropic
# plugin profile's default_aux_model pins the haiku one. claude-code (the AT
# leg) keeps the alias — its CLI resolves them natively.
if [ "$AGENT" = hermes ]; then
  case "$MODEL" in
    haiku)  MODEL=claude-haiku-4-5-20251001 ;;
    sonnet) MODEL=claude-sonnet-4-5-20250929 ;;
    opus)   MODEL=claude-opus-4-1-20250805 ;;
  esac
fi

# --- per-prompt harness preconditions ---------------------------------------
case "$ID" in
  E0)
    # team + members the E0 prompt assumes already exist
    atm teams add e0-smoke >/dev/null 2>&1 || true
    ATM_IDENTITY=fx-e0-alpha ATM_TEAM=e0-smoke atm teams add-member e0-smoke fx-e0-alpha \
      --agent-type stub --home-dir /opt/testbed/e0 >/dev/null 2>&1 || true
    ATM_IDENTITY=fx-e0-beta ATM_TEAM=e0-smoke atm teams add-member e0-smoke fx-e0-beta \
      --agent-type stub --home-dir /opt/testbed/e0 >/dev/null 2>&1 || true
    mkdir -p /opt/testbed/e0
    ;;
  AT3)
    # peer-mode gate: only meaningful when the container was started --peer
    [ -f /root/.ssh/testbed_peer_key ] || { echo "SKIP: AT3 requires peer mode (--peer)"; exit 3; }
    ;;
  AT7)
    # prerelease dispatch gate: needs the herdr backend (atm >= 1.4.4 dispatch)
    strings /usr/local/bin/atm-daemon 2>/dev/null | grep -qi herdr || \
      { echo "SKIP: AT7 needs a daemon carrying the herdr backend"; exit 3; }
    ;;
esac

rm -f "$REPORT"

# --- execute ----------------------------------------------------------------
# The fork image sets HERMES_WRITE_SAFE_ROOT=/opt/data, which denies the
# agent writing reports/results under /opt/testbed. Extend it (multi-prefix
# via os.pathsep) so prompt agents can write their report + workspace there.
export HERMES_WRITE_SAFE_ROOT="${HERMES_WRITE_SAFE_ROOT:-/opt/data}:/opt/testbed"

# The hermes agent runs as user 'hermes' (uid 10000) but /opt/testbed is
# root-owned (write denial at the OS level). Give the fixture dirs to the
# agent user so report + workspace writes succeed.
id hermes >/dev/null 2>&1 && chown -R hermes /opt/testbed/results /opt/testbed/e0 2>/dev/null || true

# The daemon's state lives under /root/.atm (root-only), but prompt agents
# run non-root and must reach the endpoint record + mail.db + logs (E0 found
# this: 'failed to inspect local runtime directory' from uid 10000). Open
# traversal on /root (711 = traverse, no listing) and read/write on the atm
# state tree. Isolated fixture container — acceptable wall relaxation.
chmod 711 /root 2>/dev/null || true
chmod -R a+rwX /root/.atm 2>/dev/null || true

if [ "$AGENT" = hermes ]; then
  hermes chat --query-file "$PROMPT" \
    ${MODEL:+-m "$MODEL"} --provider anthropic \
    --yolo --max-turns 60 ${TIMEOUT:+--run-budget "$TIMEOUT"} \
    --in /opt/testbed 2>&1 | tail -40
else
  command -v claude >/dev/null 2>&1 || /opt/testbed/harness/install-claude-code.sh
  claude -p "$(cat "$PROMPT")" --dangerously-skip-permissions \
    --model "${MODEL:-haiku}" 2>&1 | tail -40
fi

# --- verdict ----------------------------------------------------------------
# Agents sometimes write the report next to their workspace instead of the
# exact path in the frontmatter; fall back to locating it.
if [ ! -f "$REPORT" ]; then
  FOUND=$(find /opt/testbed -name "$(basename "$REPORT")" -type f 2>/dev/null | head -1)
  [ -n "$FOUND" ] && { cp -f "$FOUND" "$REPORT" 2>/dev/null || REPORT="$FOUND"; }
fi
if [ -f "$REPORT" ]; then
  VERDICT=$(python3 -c "import json;print(json.load(open('$REPORT')).get('verdict','?'))" 2>/dev/null || echo parse-error)
  echo "VERDICT ${ID}: $VERDICT ($REPORT)"
else
  echo "VERDICT ${ID}: no-report (agent did not write $REPORT)"
  exit 1
fi