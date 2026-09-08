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
# The wheels are uploaded by an early ci.yml job, so the run's overall conclusion does not matter;
# a missing artifact fails the download below.
CI="$(gh api "repos/$ATM_REPO/actions/workflows/ci.yml/runs?head_sha=$SHA" --jq 'first(.workflow_runs[])|.id')"
[ -n "$CI" ] || die "no ci.yml run for $SHA (the commit under $TAG)"
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
VERSIONS="$(docker exec "$NAME" sh -c 'printf "hermes %s | %s | %s\n" "$(hermes --version 2>/dev/null | grep -im1 hermes)" "$(atm-daemon --version)" "$(herdr --version)"')"
echo "$VERSIONS"
docker exec "$NAME" atm doctor --json 2>/dev/null | python3 -c 'import json,sys; json.dump(json.load(sys.stdin).get("herdr",{}), sys.stdout, indent=1)' > "$RUN_DIR/herdr-doctor.json"
HERDR_TRANSPORT="$(python3 -c 'import json,sys
e=json.load(open(sys.argv[1])).get("endpoints",[])
print(", ".join(sorted({"%s (%s)" % (x.get("transport","?"), x.get("state","?")) for x in e})) or "no herdr endpoint observed")' "$RUN_DIR/herdr-doctor.json")"
echo "herdr transport (fixture daemon, atm doctor): $HERDR_TRANSPORT"

# ── 4. seven sentences, seven reports ───────────────────────────────────────────────────────────
# t: the Claude Code tester (tester@testbed) is nudged over ATM as stub-alpha.
# h: the Hermes gateway agent (hermes@testbed) is nudged the same way (atm-core #1307 landed in 1.5.8: the
#    hermes-atm receiver injects into the api_server platform). Run 3 (1.5.8) proved a headless CLI hermes
#    beside the gateway loses the race for the partner's message: one identity, one actor.
t() { printf '%s\n' "$1" | docker exec -i -e ATM_IDENTITY=stub-alpha -e ATM_TEAM=$TEAM "$NAME" atm send tester --requires-ack --stdin >/dev/null \
        && echo "sent to tester: ${1%% and send*}" || echo "SEND FAILED to tester: $1"; }
h() { printf '%s\n' "$1" | docker exec -i -e ATM_IDENTITY=stub-alpha -e ATM_TEAM=$TEAM "$NAME" atm send hermes --requires-ack --stdin >/dev/null \
        && echo "sent to hermes: ${1%% and send*}" || echo "SEND FAILED to hermes: $1"; }

REPORTS=0; SLOTS_SEEN=""; DISTINCT=0
# wait_for N: poll the oversight inbox until N distinct (skill, agent) reports have arrived in total (or
# the deadline passes), printing every START/WAIT line as it arrives and saving every report. A repeated
# report for the same slot is saved but not counted (run 6: a duplicate collapsed two phases into one and
# the simultaneous sentences made the gateway's pong late). Never stops the run.
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
          slot="$(printf '%s\n' "$body" | grep -E '^(skill|agent):' | tr '\n' ' ')"
          case "$slot" in
            "skill: atm-setup-environment "*|"skill: atm-smoke "*|"skill: atm-hermes-ready "*|"skill: atm-nudge-roundtrip "*)
              case "$SLOTS_SEEN" in *"|$slot|"*) dup=" (repeat, not counted)" ;; *) SLOTS_SEEN="$SLOTS_SEEN|$slot|"; DISTINCT=$((DISTINCT+1)); dup="" ;; esac ;;
            *) dup=" (not one of the seven, not counted)" ;;   # e.g. an atm-troubleshoot report from a root-cause pass (run 7)
          esac
          echo "REPORT $REPORTS: $(printf '%s\n' "$body" | grep -E '^(skill|agent|result):' | tr '\n' ' ')$dup" ;;
        "ATM TEST START"*|"ATM TEST WAIT"*) echo "$body" | head -1 ;;
        *) echo "other message from the fixture ($(printf '%s' "$body" | wc -c | tr -d ' ') bytes)" ;;
      esac
    done
    [ "$DISTINCT" -ge "$want" ] && return 0
    [ $(( $(date +%s) - t0 )) -ge "$PHASE_DEADLINE" ] && { echo "DEADLINE: $DISTINCT/$want reports after ${PHASE_DEADLINE}s; moving on"; return 1; }
    sleep 10
  done
}

step "atm-setup-environment (tester + hermes)"
t "run the atm-setup-environment skill on fixture $F (expected roster: $R) and send the report to $O"
h "run the atm-setup-environment skill on fixture $F (expected roster: $R) and send the report to $O"
wait_for 2
step "atm-smoke (tester + hermes)"
t "run the atm-smoke skill against hermes@$TEAM on fixture $F and send the report to $O"
h "run the atm-smoke skill against tester@$TEAM on fixture $F and send the report to $O"
wait_for 4
step "atm-hermes-ready (tester)"
t "run the atm-hermes-ready skill for hermes@$TEAM on fixture $F and send the report to $O"
wait_for 5
step "atm-nudge-roundtrip (tester + hermes)"
t "run the atm-nudge-roundtrip skill as tester against hermes@$TEAM on fixture $F and send the report to $O"
h "run the atm-nudge-roundtrip skill as responder on fixture $F and send the report to $O"
wait_for 7

# ── 5. verdict ──────────────────────────────────────────────────────────────────────────────────
step "verdict"
# One slot per (skill, agent); a skill that reports twice fills its slot once and the last report wins.
SLOTS="$(cat "$RUN_DIR"/report-*.txt 2>/dev/null | python3 -c '
import sys,re
slots={}
for block in sys.stdin.read().split("ATM TEST REPORT")[1:]:
    skill=re.search(r"^skill: (\S+)",block,re.M); agent=re.search(r"^agent: (\S+)",block,re.M); result=re.search(r"^result: (PASS|FAIL)",block,re.M)
    if skill and agent and result and skill.group(1) in ("atm-setup-environment","atm-smoke","atm-hermes-ready","atm-nudge-roundtrip"):
        slots[(skill.group(1),agent.group(1))]=result.group(1)
print(len(slots), sum(1 for v in slots.values() if v=="PASS"))')"
FILLED=${SLOTS% *}; PASSED=${SLOTS#* }
if [ "$FILLED" -eq 7 ] && [ "$PASSED" -eq 7 ]; then VERDICT=PASS; else VERDICT=FAIL; fi
{
  echo "$VERDICT  skills reported $FILLED/7, PASS $PASSED/7 ($REPORTS report messages)"
  echo "atm:    $V ($TAG @ $(echo "$SHA" | cut -c1-9), prerelease-archive run $PRE, ci run $CI)"
  echo "hermes: randlee/hermes-agent @ $(echo "$HERMES_SHA" | cut -c1-9)"
  echo "$VERSIONS"
  echo "herdr transport: $HERDR_TRANSPORT (atm doctor --json .herdr.endpoints[].transport; bringup writes [herdr] transport=\"socket\" to /root/.atm.toml)"
  for f in "$RUN_DIR"/report-*.txt; do
    [ -f "$f" ] || continue
    grep -E '^(skill|agent|result):' "$f" | tr '\n' ' '; echo
    grep -E '^ +[0-9]+ FAIL' "$f" | sed 's/^/      /'      # every failed step with its cause line
  done
  echo "reports and logs: $RUN_DIR"
  echo "the fixture is still running: docker exec $NAME ... ; ./teardown.sh when done"
} | tee "$RUN_DIR/result.txt"

# ── 6. evidence bundle in atm-core's site/reports shape ─────────────────────────────────────────
# Byte-for-byte copies of the run's outputs plus the two files the report index needs (an index.html and a
# smoke envelope, see atm-core .just/generate_report_index.py). Publish: copy $RUN_DIR/site/* into
# atm-core site/reports/ on an evidence branch and run `python3 .just/generate_report_index.py` there.
SITE_REL="smoke/linux/$F/$(basename "$RUN_DIR")-colima-hermes-skills"
SITE="$RUN_DIR/site/$SITE_REL"; mkdir -p "$SITE"
cp "$RUN_DIR"/result.txt "$RUN_DIR"/herdr-doctor.json "$SITE"/; cp "$RUN_DIR"/report-*.txt "$SITE"/ 2>/dev/null || true
python3 - "$SITE" "$SITE_REL" "$VERDICT" "$F" <<'PY2'
import html, json, os, sys, datetime
site, rel, verdict, host = sys.argv[1:5]
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
files = sorted(f for f in os.listdir(site) if f != "index.html" and not f.endswith(".envelope.json"))
result = open(os.path.join(site, "result.txt")).read()
links = "".join('<li><a href="%s">%s</a></li>' % (html.escape(f), html.escape(f)) for f in files)
open(os.path.join(site, "index.html"), "w").write(
    "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
    "<title>ATM colima integration: hermes skills</title>"
    "<style>body{font:16px system-ui,sans-serif;max-width:64rem;margin:2rem auto;padding:0 1rem;line-height:1.5}pre{background:#f7f9fa;padding:1rem;overflow:auto}</style></head>"
    "<body><h1>ATM colima integration: hermes skills</h1><p>Fixture <code>%s</code> (atm-hermes-testbed <code>./test.sh</code>), generated %s. Verdict: <strong>%s</strong>.</p>"
    "<h2>result.txt</h2><pre>%s</pre><h2>Files (unedited run outputs)</h2><ul>%s</ul></body></html>\n"
    % (html.escape(host), html.escape(now), html.escape(verdict), html.escape(result), links))
json.dump({"schema_version": 1, "report_type": "smoke", "generated_at": now, "host_label": host,
           "report_html": rel + "/index.html", "status": verdict},
          open(os.path.join(site, "smoke.envelope.json"), "w"), indent=2)
PY2
echo "site evidence: $RUN_DIR/site ($SITE_REL)"
[ "$VERDICT" = PASS ]
