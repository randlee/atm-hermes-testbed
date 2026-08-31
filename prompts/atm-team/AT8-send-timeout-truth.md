---
id: AT8-send-timeout-truth
agent: claude-code
model: haiku
requires: [ANTHROPIC_API_KEY]
timeout_s: 180
report: /opt/testbed/results/prompt-AT8.json
since: suite/v1
---

You are the atm-team send-timeout-truth agent inside the hermes-docker-testbed
fixture. Your job is to prove the RETRY DECISION RULE for a client-side send
timeout, not any single fixed outcome. The rule (the real 2026-08-29 incident
contract): after a send returns a client timeout, consult
`~/.atm/logs/atm.log.jsonl` for a send entry with the same request_id —
`"action":"send" ... "outcome":"sent"` — and let that decide:
  (a) entry ABSENT  -> the write never landed, so retry ONCE; expect the
      receiver to end up with exactly one copy;
  (b) entry PRESENT -> the write landed despite the timeout, so do NOT retry;
      expect the receiver to end up with exactly one copy.
Either branch PASSES if the receiver ends up with exactly one copy AND your
retry choice matches what the log shows. Never retry blindly (a blind retry
on branch (b) duplicates the message). Then emit a structured report. Do each
step in order; if a step fails, record it as failed and continue.

Timing facts about this fixture (fenix@atm-dev): a full SIGSTOP BEFORE the
daemon reads the request cannot persist anything — the write is genuinely
lost and the client timeout is truthful. That outcome is CORRECT on both
atm 1.4.3 and 1.4.6; #1095 does not change it (#1095 fixes the
stale-connection-to-restarted-daemon case, which is AT4's territory, not
AT8's). So AT8's result should be the SAME across 1.4.3 and 1.4.6; a
difference would be a finding, not an expected regression signal. The two
freeze timings below deliberately select the branch you get:
  - freeze-daemon.sh 4            (freeze before the send) -> mostly branch (a)
  - freeze-daemon.sh 4 --after 300 (freeze ~300ms AFTER the send starts, so
    the daemon has accepted+persisted but its reply is delayed past the 3.25s
    client budget) -> deterministically branch (b).

Context already true in this fixture: the ATM daemon is running; team
`fx-at8` with members `fx-at8-alpha` and `fx-at8-beta` is registered by the
harness before you start; the harness freeze hook is
/opt/testbed/harness/freeze-daemon.sh (supports `--after <ms>`; the client's
absolute request budget in this fixture is 3.25s). Your default identity is
`fx-at8-alpha`.

Steps:

1. Harness-hook precondition: run `test -x
   /opt/testbed/harness/freeze-daemon.sh`. If not present/executable, record
   status "skip" with reason "harness script missing" for every remaining
   step and stop (still write the full report).
2. Warm-up: `ATM_IDENTITY=fx-at8-alpha ATM_TEAM=fx-at8 atm send fx-at8-beta
   "AT8-WARMUP" --team fx-at8`. Exit code 0 — confirms the daemon is healthy
   before inducing any freeze.

   --- Phase A: freeze BEFORE the send (expected branch (a), write lost) ---
3. Phase-A freeze: run `/opt/testbed/harness/freeze-daemon.sh 4 &`
   immediately before the next step (no --after), so the daemon is frozen
   before it can read the request.
4. Phase-A timeout send: immediately run `ATM_IDENTITY=fx-at8-alpha atm send
   fx-at8-beta "AT8-PHASE-A" --team fx-at8 --json`. Capture the request id
   from the output (record it in `detail`; note if none is visible). Expect a
   non-zero exit code (observed on atm 1.4.3: exit 9, stdout EMPTY, stderr
   `HTTP client request exceeded its absolute request budget`). Record the
   exit code and exact stderr text.
5. Phase-A freeze completed: wait-gate (not pass/fail) until the step-3
   background job exits.
6. Phase-A log truth check: search `~/.atm/logs/atm.log.jsonl` (via `atm log
   filter` or `atm log tail`, per docs/user-documents/doctor-and-log.md) for
   a send entry correlated with the step-4 request — prefer matching by the
   captured request id, else by message text `AT8-PHASE-A`. Record in
   `detail` whether you found `"action":"send"..."outcome":"sent"` (PRESENT)
   or not (ABSENT), and how you correlated. For phase A expect ABSENT.
7. Phase-A retry decision: apply the rule. If step 6 = ABSENT, retry ONCE:
   `ATM_IDENTITY=fx-at8-alpha atm send fx-at8-beta "AT8-PHASE-A" --team
   fx-at8 --json` (the daemon is thawed now). Record that you retried and its
   exit code. If step 6 = PRESENT (unexpected for phase A), do NOT retry and
   record why.
8. Phase-A delivery count: `ATM_IDENTITY=fx-at8-beta ATM_TEAM=fx-at8 atm list
   fx-at8-beta --all --json` — count occurrences of `AT8-PHASE-A` in rows[].
   PASS this step only if the count is exactly 1 AND your step-7 choice
   matched the step-6 log outcome. Record the count.

   --- Phase B: freeze AFTER the send starts (expected branch (b), landed) ---
9. Phase-B freeze: run `/opt/testbed/harness/freeze-daemon.sh 4 --after 300 &`
   and IMMEDIATELY run the next step, so the send starts before the freeze
   lands and the daemon persists it but its reply is delayed past the budget.
10. Phase-B timeout send: immediately run `ATM_IDENTITY=fx-at8-alpha atm send
    fx-at8-beta "AT8-PHASE-B" --team fx-at8 --json`. Capture the request id.
    Expect a non-zero exit code (client budget abort). Record exit code and
    stderr.
11. Phase-B freeze completed: wait-gate until the step-9 background job exits.
12. Phase-B log truth check: same as step 6 but for `AT8-PHASE-B`. For phase B
    expect PRESENT (the daemon accepted+persisted before the reply timed out).
    Record PRESENT/ABSENT and the correlation method.
13. Phase-B retry decision: apply the rule. If step 12 = PRESENT, do NOT
    retry; record that you did not and why. If step 12 = ABSENT (unexpected
    for phase B), retry once and record it.
14. Phase-B delivery count: `atm list fx-at8-beta --all --json` as
    fx-at8-beta — count occurrences of `AT8-PHASE-B`. PASS only if count == 1
    AND your step-13 choice matched the step-12 log outcome.

REPORT CONTRACT — after step 14 (or immediately after step 1 if skipped),
write the file /opt/testbed/results/prompt-AT8.json with exactly this shape
(real values):

{
  "schema": "prompt-report-1",
  "test_id": "AT8-send-timeout-truth",
  "agent": "claude-code",
  "steps": [
    {"name": "harness-hook-precondition", "status": "pass|fail|skip", "detail": ""},
    {"name": "warm-up-send", "status": "", "detail": ""},
    {"name": "phase-a-freeze-before-send", "status": "", "detail": ""},
    {"name": "phase-a-timeout-send-observed", "status": "", "detail": ""},
    {"name": "phase-a-freeze-completed", "status": "", "detail": ""},
    {"name": "phase-a-log-truth-check", "status": "", "detail": ""},
    {"name": "phase-a-retry-decision", "status": "", "detail": ""},
    {"name": "phase-a-exactly-one-copy", "status": "", "detail": ""},
    {"name": "phase-b-freeze-after-send-start", "status": "", "detail": ""},
    {"name": "phase-b-timeout-send-observed", "status": "", "detail": ""},
    {"name": "phase-b-freeze-completed", "status": "", "detail": ""},
    {"name": "phase-b-log-truth-check", "status": "", "detail": ""},
    {"name": "phase-b-no-retry-decision", "status": "", "detail": ""},
    {"name": "phase-b-exactly-one-copy", "status": "", "detail": ""}
  ],
  "verdict": "pass if no step failed, else fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "", "finished_at": ""
}

Then print the single line: SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT8.json
