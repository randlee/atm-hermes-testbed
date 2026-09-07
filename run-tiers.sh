#!/bin/sh
# run-tiers.sh — HOST-side coordinator for the infra matrix (tiers A-D).
# Supplies the four self-carried provenance envs required by result.py's
# evidence-integrity gate (five-fix bundle item 3), cross-checks the pinned
# image digest, runs the tiers in order, and copies result JSONs out.
#
# Usage: PINNED_DIGEST=sha256:... ATM_CORE_SHA=<sha> CI_RUN_ID=<run> \
#        HERMES_FORK_SHA=<sha> ./run-tiers.sh [outdir]
#
# Defaults come from results-run-v153/asset-provenance.txt + the base-image
# build worktree, so the v1.5.3 run needs no arguments; any explicit env
# overrides. REFUSES to run when digest/inputs mismatch (fail-closed).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME=hermes-testbed
OUT="${1:-$HERE/results-run-v153}"
PROV="$HERE/results-run-v153/asset-provenance.txt"

# --- derive defaults (v1.5.3 run) ------------------------------------------
PINNED_DIGEST="${PINNED_DIGEST:-$(grep '^image:' "$PROV" | grep -o 'sha256:[0-9a-f]*' | head -1)}"
ATM_CORE_SHA="${ATM_CORE_SHA:-$(grep '^atm_core_sha:' "$PROV" | awk '{print $2}')}"
# wheels CI run (headSha == tag sha) — the archive run id is also recorded;
# CI_RUN_ID cites the WHEELS run per the CATALOG provenance rule.
CI_RUN_ID="${CI_RUN_ID:-$(grep '^wheels_ci_run:' "$PROV" | awk '{print $2}')}"
HERMES_FORK_SHA="${HERMES_FORK_SHA:-$(git -C "$HOME/Documents/github/hermes-agent-randlee-worktrees/testbed-build" rev-parse HEAD 2>/dev/null || true)}"

[ -n "$PINNED_DIGEST" ] && [ -n "$ATM_CORE_SHA" ] && [ -n "$CI_RUN_ID" ] && [ -n "$HERMES_FORK_SHA" ] || {
  echo "FATAL: could not derive all provenance inputs (digest/atm sha/run/fork sha)"; exit 1; }

# --- fail-closed digest check ----------------------------------------------
ACTUAL="$(docker inspect "$NAME" --format '{{.Image}}')"
[ "$ACTUAL" = "$PINNED_DIGEST" ] || {
  echo "FATAL: container image $ACTUAL != pinned $PINNED_DIGEST"; exit 1; }
echo "digest OK: $PINNED_DIGEST"
echo "provenance: atm_core=$ATM_CORE_SHA ci_run=$CI_RUN_ID fork=$HERMES_FORK_SHA"

# --- sync harness (docker-cp; product layers untouched, no rebuild) ---------
for f in result.py seam_harness.py test-tier-a.py test-tier-b.py test-tier-c.py test-tier-d.py; do
  docker cp "$HERE/testbed/$f" "$NAME:/opt/testbed/$f"
done

# --- run tiers with the provenance envs -------------------------------------
RC=0
for t in a b c d; do
  echo "=== TIER $t ==="
  docker exec \
    -e TESTBED_IMAGE_ID="$PINNED_DIGEST" \
    -e ATM_CORE_SHA="$ATM_CORE_SHA" \
    -e CI_RUN_ID="$CI_RUN_ID" \
    -e HERMES_FORK_SHA="$HERMES_FORK_SHA" \
    "$NAME" /opt/hermes/.venv/bin/python "/opt/testbed/test-tier-$t.py" || RC=1
done

# --- collect evidence --------------------------------------------------------
mkdir -p "$OUT"
for t in a b c d; do
  docker cp "$NAME:/opt/testbed/results/tier-$t.json" "$OUT/tier-$t.json"
done
# post-run doctor summary (sanitized: status + code counts only)
docker exec "$NAME" atm doctor --json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
f={}
for x in d.get('findings') or []:
    k=f\"{x.get('severity','?')}/{x.get('code','?')}\"
    f[k]=f.get(k,0)+1
print(json.dumps({'status':(d.get('summary') or {}).get('status'),'findings':f},indent=1))
" > "$OUT/doctor-post-run.json" || true
echo "=== evidence in $OUT; matrix rc=$RC ==="
exit $RC
