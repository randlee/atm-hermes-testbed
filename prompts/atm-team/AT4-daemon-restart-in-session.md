---
id: AT4-daemon-restart-in-session
agent: claude-code
model: haiku
requires: [ANTHROPIC_API_KEY]
timeout_s: 180
report: /opt/testbed/results/prompt-AT4.json
since: suite/v1
---

You are the atm-team daemon-restart agent inside the hermes-docker-testbed
fixture. Your job: prove that a mid-session atm-daemon restart, triggered by
the harness restart hook, requires zero manual recovery steps and causes no
message loss or duplication (atm-core
docs/plans/phase-aq/sprint-AQ1-9-hermes-atm-wheel-verification.md; reconnect
behavior documented in crates/atm-http-runtime/src/client.rs). Do each step
in order; if a step fails, record it as failed and continue.

Context already true in this fixture: the ATM daemon is running; team
`fx-at4` with members `fx-at4-alpha` and `fx-at4-beta` is registered by the
harness before you start; the harness restart hook is
/opt/testbed/harness/restart-daemon.sh (kills atm-daemon, clears the stale
owner lock, relaunches it detached, and internally wait-gates up to 60s on
/root/.atm/daemon/local-http.json reappearing before exiting 0, or exits
non-zero on failure). Your default identity is `fx-at4-alpha`.

Steps:

1. Harness-hook precondition: run `test -x
   /opt/testbed/harness/restart-daemon.sh`. If it is not present/executable,
   record status "skip" with reason "harness script missing" for every
   remaining step and stop (still write the full report).
2. Pre-restart baseline: `ATM_IDENTITY=fx-at4-alpha ATM_TEAM=fx-at4 atm send
   fx-at4-beta "AT4-PRE-1" --team fx-at4`. Exit code 0. Then
   `ATM_IDENTITY=fx-at4-beta atm read --team fx-at4 --history --json` and
   record the message count as `count_before` (must include AT4-PRE-1).
3. Trigger restart: run `/opt/testbed/harness/restart-daemon.sh`. Expect
   exit code 0 (the script itself is the wait-gate on
   /root/.atm/daemon/local-http.json reappearing; do not add your own extra
   wait loop beyond letting the script finish).
4. Post-restart send, zero manual steps: `ATM_IDENTITY=fx-at4-alpha atm send
   fx-at4-beta "AT4-POST-1" --team fx-at4`. Exit code 0 with no retries, no
   re-authentication, and no other manual recovery command between step 3
   and this send.
5. Post-restart read: `ATM_IDENTITY=fx-at4-beta atm read --team fx-at4
   --history --json`. Exit code 0.
6. No loss, no duplication: the step-5 result contains AT4-PRE-1 and
   AT4-POST-1 each exactly once, and the total count equals `count_before +
   1`.

REPORT CONTRACT — after step 6 (or immediately after step 1 if skipped),
write the file /opt/testbed/results/prompt-AT4.json with exactly this shape
(real values):

{
  "schema": "prompt-report-1",
  "test_id": "AT4-daemon-restart-in-session",
  "agent": "claude-code",
  "steps": [
    {"name": "harness-hook-precondition", "status": "pass|fail|skip", "detail": ""},
    {"name": "pre-restart-baseline", "status": "", "detail": ""},
    {"name": "restart-triggered", "status": "", "detail": ""},
    {"name": "post-restart-send", "status": "", "detail": ""},
    {"name": "post-restart-read", "status": "", "detail": ""},
    {"name": "no-loss-no-duplication", "status": "", "detail": ""}
  ],
  "verdict": "pass if no step failed, else fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "", "finished_at": ""
}

Then print the single line: SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT4.json
