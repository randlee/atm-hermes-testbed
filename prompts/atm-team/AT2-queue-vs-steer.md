---
id: AT2-queue-vs-steer
agent: claude-code
model: haiku
requires: [ANTHROPIC_API_KEY]
timeout_s: 90
report: /opt/testbed/results/prompt-AT2.json
---

You are the atm-team queue/steer agent inside the hermes-docker-testbed
fixture. Your job: distinguish `atm send`'s immediate steer nudge from `atm
queue`'s deferred nudge (atm-core docs/plans/phase-aq/sprint-AQ1-queue-cli.md,
sprint-AQ2-5-queue-delivery-triggers.md) and prove no double delivery, then
emit a structured report. Wait windows below are wait-gates only, never
pass/fail assertions. Do each step in order; if a step fails, record it as
failed and continue.

Context already true in this fixture: the ATM daemon is running; team
`fx-at2` with members `fx-at2-alpha` and `fx-at2-beta` is registered by the
harness before you start. Per the AQ1 contract, `atm queue` mirrors `atm
send`'s CLI surface exactly except the nudge is deferred instead of
immediate; a queued message is durably readable immediately either way.

Steps:

1. Steer send: `ATM_IDENTITY=fx-at2-alpha ATM_TEAM=fx-at2 atm send
   fx-at2-beta "AT2-STEER-1" --team fx-at2`. Exit code 0. Capture the
   message id.
2. Steer log evidence: within a 10s wait-gate (not pass/fail), run `atm log
   filter --level info --match command=send` (or `atm log tail`) and look
   for a steer/nudge dispatch event correlated with the step-1 message.
   Record whatever action/outcome field names you actually observe — the
   docs do not pin one exact event-name string. If no distinguishing event
   is found, record status "skip" with reason "no documented steer-dispatch
   log event name to assert on".
3. Queue send: `ATM_IDENTITY=fx-at2-alpha atm queue fx-at2-beta
   "AT2-QUEUE-1" --team fx-at2`. Exit code 0. Capture the message id.
4. Queue immediate readability: `ATM_IDENTITY=fx-at2-beta atm read --team
   fx-at2 --json` returns the AT2-QUEUE-1 message durably and immediately,
   the same as a sent message (per AQ1 AC: "a queued message is readable
   immediately").
5. No immediate steer for queue: repeat the step-2 log check scoped to the
   step-3 message. Confirm no steer-kind dispatch event is recorded for it
   at send time (a queue-kind marker/suppression event, if visible, is
   expected instead). If the log does not expose enough detail to
   distinguish steer from queue dispatch, record status "skip" with reason
   "no documented log field distinguishes queue suppression from steer
   dispatch".
6. No double delivery: `ATM_IDENTITY=fx-at2-beta atm read --team fx-at2
   --history --json` shows AT2-STEER-1 and AT2-QUEUE-1 each exactly once
   (no duplicate entries for either message).

REPORT CONTRACT — after step 6, write the file
/opt/testbed/results/prompt-AT2.json with exactly this shape (real values):

{
  "schema": "prompt-report-1",
  "test_id": "AT2-queue-vs-steer",
  "agent": "claude-code",
  "steps": [
    {"name": "steer-send", "status": "pass|fail|skip", "detail": ""},
    {"name": "steer-log-evidence", "status": "", "detail": ""},
    {"name": "queue-send", "status": "", "detail": ""},
    {"name": "queue-immediate-readability", "status": "", "detail": ""},
    {"name": "no-immediate-steer-for-queue", "status": "", "detail": ""},
    {"name": "no-double-delivery", "status": "", "detail": ""}
  ],
  "verdict": "pass if no step failed, else fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "", "finished_at": ""
}

Then print the single line: SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT2.json
