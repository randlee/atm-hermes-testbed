#!/bin/sh
# test.sh — the whole integration test in one command, no arguments.
#
#   ./test.sh
#
# Installs the three things in colima (Hermes fork, herdr, latest ATM prerelease), starts the ATM
# daemon and the Hermes gateway inside the container, sends the seven sentences that run the five
# atm-* skills, collects the seven reports and prints PASS or FAIL with the exact versions tested.
# Nothing on this Mac is touched: no host daemon, no host trust store, no peer link. Everything the
# fixture needs comes from URLs; the only local input is env/allowlist.env (ANTHROPIC_API_KEY).
#
# Exit code: 0 = PASS (seven reports, every one PASS), 1 = FAIL, 2 = could not run (says why).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME=hermes-testbed
TEAM=testbed
O="oversight@$TEAM"                     # every report goes here (a roster identity inside the fixture)
R="stub-alpha@$TEAM stub-beta@$TEAM tester@$TEAM hermes@$TEAM oversight@$TEAM"
F="$NAME"                               # fixture name in the reports
ATM_REPO=randlee/atm-core
RUN_DIR="$HERE/.cache/results/$(date -u +%Y%m%dT%H%M%SZ)"
PHASE_DEADLINE=${PHASE_DEADLINE:-600}   # seconds to wait for each group of reports

die() { echo "CANNOT RUN: $*" >&2; exit 2; }
step() { echo "== $(date -u +%H:%M:%SZ) $*"; }

# ── 0. preconditions ────────────────────────────────────────────────────────────────────────────
for c in gh docker git python3 shasum; do command -v "$c" >/dev/null 2>&1 || die "$c not installed"; done
gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
[ -s "$HERE/env/allowlist.env" ] && grep -Eq '^ANTHROPIC_API_KEY=[^[:space:]]' "$HERE/env/allowlist.env" \
  || die "env/allowlist.env with ANTHROPIC_API_KEY=... is missing (copy env/allowlist.env.example and fill it)"
if ! docker info >/dev/null 2>&1; then
  command -v colima >/dev/null 2>&1 || die "docker is not reachable and colima is not installed (brew install colima docker)"
  step "colima start"; colima start || die "colima start failed"
  docker info >/dev/null 2>&1 || die "docker still not reachable after colima start"
fi
mkdir -p "$HERE/.cache" "$RUN_DIR"

# ── 1. inputs, all from the network ─────────────────────────────────────────────────────────────
step "resolve inputs"
TAG="$(gh api "repos/$ATM_REPO/git/matching-refs/tags/prerelease/" --jq '.[].ref' | sed 's|^refs/tags/||' | sort -V | tail -1)"
[ -n "$TAG" ] || die "no prerelease/vX.Y.Z tag in $ATM_REPO"
V="${TAG#prerelease/v}"
OBJ="$(gh api "repos/$ATM_REPO/git/ref/tags/$TAG" --jq '.object.type+" "+.object.sha')"
case "$OBJ" in
  "tag "*)    SHA="$(gh api "repos/$ATM_REPO/git/tags/${OBJ#tag }" --jq '.object.sha')" ;;
  "commit "*) SHA="${OBJ#commit }" ;;
  *) die "cannot resolve $TAG" ;;
esac
PRE="$(gh run list -R "$ATM_REPO" --workflow prerelease-archive.yml --branch "$TAG" --json databaseId,conclusion \
       --jq 'first(.[]|select(.conclusion=="success"))|.databaseId')"
[ -n "$PRE" ] || die "no successful prerelease-archive.yml run for $TAG"
CI="$(gh api "repos/$ATM_REPO/actions/runs?head_sha=$SHA&per_page=50" \
      --jq 'first(.workflow_runs[]|select(.path==".github/workflows/ci.yml" and .conclusion=="success"))|.id')"
[ -n "$CI" ] || die "no successful ci.yml run for $SHA (the commit under $TAG)"
ARCH="$(if [ "$(uname -m)" = arm64 ] || [ "$(uname -m)" = aarch64 ]; then echo aarch64; else echo x86_64; fi)"
echo "atm $V = $TAG @ $(echo "$SHA" | cut -c1-9); prerelease-archive run $PRE; ci run $CI; arch $ARCH"

ATM_DIR="$HERE/.cache/atm-$V"; WHEELS="$HERE/.cache/wheels-$V"
if [ ! -f "$ATM_DIR/atm_${V}_${ARCH}-unknown-linux-gnu.tar.gz" ]; then
  rm -rf "$ATM_DIR"; gh run download "$PRE" -R "$ATM_REPO" -n "${ARCH}-unknown-linux-gnu" -D "$ATM_DIR" || die "tarball download failed"
fi
if ! ls "$WHEELS"/hermes_atm-*.whl >/dev/null 2>&1; then
  rm -rf "$WHEELS"; gh run download "$CI" -R "$ATM_REPO" -n "hermes-atm-wheels-linux-$(if [ "$ARCH" = aarch64 ]; then echo aarch64; else echo x86_64; fi)" -D "$WHEELS" || die "wheels download failed"
fi

# ── 2. install everything into the image (Hermes fork from its URL, herdr release, ATM prerelease) ─
step "build (10-20 min the first time, seconds when nothing changed)"
ATM_TARBALL="$ATM_DIR/atm_${V}_${ARCH}-unknown-linux-gnu.tar.gz" WHEELS_DIR="$WHEELS" "$HERE/build.sh" all > "$RUN_DIR/build.log" 2>&1 \
  || { tail -30 "$RUN_DIR/build.log"; die "build failed (full log: $RUN_DIR/build.log)"; }
HERMES_SHA="$(cat "$HERE/.cache/hermes-sha")"
grep -E '^(base context|atm tarball override|wheels override):' "$RUN_DIR/build.log"

# ── 3. start: daemon, herdr, roster, hermes-atm hook, gateway, Claude Code tester ────────────────
step "start the fixture"
"$HERE/run.sh" --gateway --no-peer > "$RUN_DIR/run.log" 2>&1 || { tail -20 "$RUN_DIR/run.log"; die "run.sh failed (full log: $RUN_DIR/run.log)"; }
grep '^bringup:' "$RUN_DIR/run.log"
VERSIONS="$(docker exec "$NAME" sh -c 'printf "hermes %s | %s | %s\n" "$(hermes --version 2>/dev/null | tail -1)" "$(atm-daemon --version)" "$(herdr --version)"')"
echo "$VERSIONS"

# ── 4. seven sentences, seven reports ───────────────────────────────────────────────────────────
# t: the Claude Code tester (tester@testbed) is nudged over ATM as stub-alpha.
# h: the Hermes agent (hermes@testbed) is driven with the headless CLI as the hermes user (the
#    receiver injects only into a Telegram adapter until atm-core #1307 lands). Runs in the background.
t() { printf '%s\n' "$1" | docker exec -i -e ATM_IDENTITY=stub-alpha -e ATM_TEAM=$TEAM "$NAME" atm send tester --requires-ack --stdin >/dev/null \
        && echo "sent to tester: ${1%% and send*}" || echo "SEND FAILED to tester: $1"; }
h() { skill=$1; shift
      printf '%s\n' "$1" | docker exec -i "$NAME" sh -c 'cat > /tmp/smoke-prompt.md; chmod 644 /tmp/smoke-prompt.md'
      echo "sent to hermes: ${1%% and send*}"
      docker exec -e ATM_IDENTITY=hermes -e ATM_TEAM=$TEAM "$NAME" hermes -p default chat --query-file /tmp/smoke-prompt.md \
        --skills "$skill" -m claude-haiku-4-5-20251001 --provider anthropic --yolo --accept-hooks --max-turns 60 --in /opt/data \
        > "$RUN_DIR/hermes-$skill.log" 2>&1 & }

REPORTS=0
# wait_for N: poll the oversight inbox until N reports have arrived in total (or the deadline passes),
# printing every START/WAIT line as it arrives and saving every report. Never stops the run.
wait_for() {
  want=$1; t0=$(date +%s)
  while :; do
    ids="$(docker exec -e ATM_IDENTITY=oversight -e ATM_TEAM=$TEAM "$NAME" atm list --unread --json 2>/dev/null \
           | python3 -c 'import json,sys
for r in json.load(sys.stdin).get("rows", []): print(r["message_id"])' 2>/dev/null)"
    for id in $ids; do
      body="$(docker exec -e ATM_IDENTITY=oversight -e ATM_TEAM=$TEAM "$NAME" atm read --message-id "$id" 2>/dev/null | sed -n '/^Body:/,$p' | tail -n +2)"
      case "$body" in
        "ATM TEST REPORT"*)
          REPORTS=$((REPORTS+1)); printf '%s\n' "$body" > "$RUN_DIR/report-$REPORTS.txt"
          echo "REPORT $REPORTS: $(printf '%s\n' "$body" | grep -E '^(skill|agent|result):' | tr '\n' ' ')" ;;
        "ATM TEST START"*|"ATM TEST WAIT"*) echo "$body" | head -1 ;;
        *) echo "other message from the fixture ($(printf '%s' "$body" | wc -c | tr -d ' ') bytes)" ;;
      esac
    done
    [ "$REPORTS" -ge "$want" ] && return 0
    [ $(( $(date +%s) - t0 )) -ge "$PHASE_DEADLINE" ] && { echo "DEADLINE: $REPORTS/$want reports after ${PHASE_DEADLINE}s; moving on"; return 1; }
    sleep 10
  done
}

step "atm-setup-environment (tester + hermes)"
t "run the atm-setup-environment skill on fixture $F (expected roster: $R) and send the report to $O"
h atm-setup-environment "run the atm-setup-environment skill on fixture $F (expected roster: $R) and send the report to $O"
wait_for 2
step "atm-smoke (tester + hermes)"
t "run the atm-smoke skill against hermes@$TEAM on fixture $F and send the report to $O"
h atm-smoke "run the atm-smoke skill against tester@$TEAM on fixture $F and send the report to $O"
wait_for 4
step "atm-hermes-ready (tester)"
t "run the atm-hermes-ready skill for hermes@$TEAM on fixture $F and send the report to $O"
wait_for 5
step "atm-nudge-roundtrip (tester + hermes)"
t "run the atm-nudge-roundtrip skill as tester against hermes@$TEAM on fixture $F and send the report to $O"
h atm-nudge-roundtrip "run the atm-nudge-roundtrip skill as responder on fixture $F and send the report to $O"
wait_for 7
wait  # background hermes chats

# ── 5. verdict ──────────────────────────────────────────────────────────────────────────────────
step "verdict"
PASSED=$(cat "$RUN_DIR"/report-*.txt 2>/dev/null | grep -c '^result: PASS' || true)
if [ "$REPORTS" -eq 7 ] && [ "$PASSED" -eq 7 ]; then VERDICT=PASS; else VERDICT=FAIL; fi
{
  echo "$VERDICT  reports $REPORTS/7, PASS $PASSED/7"
  echo "atm:    $V ($TAG @ $(echo "$SHA" | cut -c1-9), prerelease-archive run $PRE, ci run $CI)"
  echo "hermes: randlee/hermes-agent @ $(echo "$HERMES_SHA" | cut -c1-9)"
  echo "$VERSIONS"
  for f in "$RUN_DIR"/report-*.txt; do [ -f "$f" ] && grep -E '^(skill|agent|result):' "$f" | tr '\n' ' ' && echo; done
  echo "reports and logs: $RUN_DIR"
  echo "the fixture is still running: docker exec $NAME ... ; ./teardown.sh when done"
} | tee "$RUN_DIR/result.txt"
[ "$VERDICT" = PASS ]
