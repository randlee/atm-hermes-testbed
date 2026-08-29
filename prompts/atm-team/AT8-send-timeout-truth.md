---
id: AT8-send-timeout-truth
agent: claude-code
model: haiku
requires: [ANTHROPIC_API_KEY]
timeout_s: 120
report: /opt/testbed/results/prompt-AT8.json
since: suite/v1
---

You are the atm-team send-timeout-truth agent inside the hermes-docker-testbed
fixture. Your job: prove that a client-side send timeout is NOT the same as a
failed write (atm-core crates/atm-http-runtime/src/client.rs:
`AtmErrorCode::WaitTimeout`, "HTTP client request exceeded its absolute
request budget") — the write can still land durably, so the correct response
is to check the log before retrying, never to retry blindly — then emit a
structured report. Do each step in order; if a step fails, record it as
failed and continue.

Context already true in this fixture: the ATM daemon is running; team
`fx-at8` with members `fx-at8-alpha` and `fx-at8-beta` is registered by the
harness before you start; the harness freeze hook is
/opt/testbed/harness/freeze-daemon.sh (SIGSTOPs the atm-daemon process for N
seconds, default 4, then SIGCONTs it; the client's absolute request budget in
this fixture is 3.25s, so a 4s freeze reliably induces a client timeout while
the daemon is still able to persist the write once resumed). Your default
identity is `fx-at8-alpha`.

Steps:

1. Harness-hook precondition: run `test -x
   /opt/testbed/harness/freeze-daemon.sh`. If not present/executable, record
   status "skip" with reason "harness script missing" for every remaining
   step and stop (still write the full report).
2. Warm-up: `ATM_IDENTITY=fx-at8-alpha ATM_TEAM=fx-at8 atm send fx-at8-beta
   "AT8-WARMUP" --team fx-at8`. Exit code 0 — confirms the daemon is healthy
   before inducing the freeze.
3. Freeze in background: run `/opt/testbed/harness/freeze-daemon.sh 4 &`
   immediately before the next step, so the daemon is frozen while the
   timing-critical send below is issued.
4. Timeout send: immediately run `ATM_IDENTITY=fx-at8-alpha atm send
   fx-at8-beta "AT8-TIMEOUT-1" --team fx-at8 --json`. Expect a non-zero exit
   code. Observed on atm 1.4.3 with a 4s freeze: exit code 9, stdout EMPTY,
   stderr `HTTP client request exceeded its absolute request budget` (the
   client's hard request-budget abort — NOT a WaitTimeout JSON shape;
   WaitTimeout / ATM_WAIT_TIMEOUT is the read-wait path). Record the exit
   code and exact stderr text you observe.
5. Let the freeze finish: wait-gate (not pass/fail) until the background
   freeze-daemon.sh job from step 3 exits.
6. Log truth check: search `~/.atm/logs/atm.log.jsonl` (via `atm log filter
   --match command=send` or `atm log tail`, per
   docs/user-documents/doctor-and-log.md) for an entry correlated with the
   step-4 request (by the message text `AT8-TIMEOUT-1`). Determine which of
   two outcomes occurred and record it in `detail`:
   (a) DURABLE ACCEPT — a log entry shows the write was accepted despite the
       client timeout, and/or step 8 finds the message delivered; or
   (b) WRITE LOST — no such entry and step 8 finds no message. (Empirical on
       atm 1.4.3 with a full 4s SIGSTOP freeze: the client's budget abort
       tears down the request and the write does NOT land — outcome (b). The
       slow-but-alive case from the 2026-08-29 incident is outcome (a). The
       whole point of this test is to measure which one THIS daemon build
       exhibits, so do not assume.)
7. Retry decision FROM EVIDENCE: if step 6 shows (a) durable accept, record
   that you did NOT resend `AT8-TIMEOUT-1` (blind retry risks duplicate
   delivery — "send timeout != failed write"). If step 6 shows (b) lost,
   record that a retry IS justified for this outcome (the write never landed,
   so there is no duplicate risk) — but still do not resend inside this
   test; note the policy conclusion in `detail`.
8. Delivery count: `ATM_IDENTITY=fx-at8-beta ATM_TEAM=fx-at8 atm list
   fx-at8-beta --all --json` — count occurrences of `AT8-TIMEOUT-1` in
   rows[]. Record the exact count (0 or 1; on atm 1.4.3 freeze, expect 0).
   The verdict for this step is pass as long as the count matches the step-6
   outcome; a count of 2 (duplicate) or a mismatch with step 6 is a fail.

REPORT CONTRACT — after step 8 (or immediately after step 1 if skipped),
write the file /opt/testbed/results/prompt-AT8.json with exactly this shape
(real values):

{
  "schema": "prompt-report-1",
  "test_id": "AT8-send-timeout-truth",
  "agent": "claude-code",
  "steps": [
    {"name": "harness-hook-precondition", "status": "pass|fail|skip", "detail": ""},
    {"name": "warm-up-send", "status": "", "detail": ""},
    {"name": "freeze-triggered", "status": "", "detail": ""},
    {"name": "timeout-send-observed", "status": "", "detail": ""},
    {"name": "freeze-completed", "status": "", "detail": ""},
    {"name": "log-truth-check", "status": "", "detail": ""},
    {"name": "no-retry-decision", "status": "", "detail": ""},
    {"name": "exactly-one-delivered-copy", "status": "", "detail": ""}
  ],
  "verdict": "pass if no step failed, else fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "", "finished_at": ""
}

Then print the single line: SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT8.json
