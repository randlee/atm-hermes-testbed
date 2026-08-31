---
id: AT0-ack-discipline
agent: claude-code
model: haiku
requires: [ANTHROPIC_API_KEY]
timeout_s: 120
report: /opt/testbed/results/prompt-AT0.json
since: suite/v1
---

You are the atm-team ack-discipline agent inside the hermes-docker-testbed
fixture. Your job: prove the mandatory dogfooding message flow from
docs/team-protocol.md (atm-core) — ack, then work, then completion, in that
order, visible in the sender's own history — then emit a structured report.
Do each step in order. Do not skip a step; if a step fails, record it as
failed and continue.

Context already true in this fixture: the ATM daemon is running; team
`fx-at0` with members `fx-at0-alpha` and `fx-at0-beta` is registered by the
harness before you start; your default identity is `fx-at0-beta`; your
workspace root is /opt/testbed/at0.

Steps:

1. Task envelope: with `ATM_IDENTITY=fx-at0-alpha ATM_TEAM=fx-at0`, run
   `atm send fx-at0-beta "AT0-TASK-1: create /opt/testbed/at0/at0-proof.txt
   containing the text at0-ok" --team fx-at0 --requires-ack --task-id
   AT0-TASK-1`. Exit code 0.
2. Receive as fx-at0-beta: `ATM_IDENTITY=fx-at0-beta atm read --team fx-at0
   --json` returns the message from step 1 with `task_id` `AT0-TASK-1` and a
   requires-ack flag set. Capture its message id.
3. Ack per docs/team-protocol.md: `ATM_IDENTITY=fx-at0-beta atm ack
   <message_id> "ack, working on AT0-TASK-1" --team fx-at0`. Exit code 0.
4. Do the trivial task: create /opt/testbed/at0/at0-proof.txt with exactly
   the content `at0-ok`.
5. Completion message: `ATM_IDENTITY=fx-at0-beta atm send fx-at0-alpha "task
   complete: AT0-TASK-1 done, wrote at0-proof.txt" --team fx-at0`. Exit
   code 0.
6. Sender-side order: `ATM_IDENTITY=fx-at0-alpha atm read --team fx-at0
   --history --json` shows both the step-3 ack reply body and the step-5
   completion body, with the ack entry ordered strictly before the
   completion entry by timestamp/sequence.

REPORT CONTRACT — after step 6, write the file
/opt/testbed/results/prompt-AT0.json with exactly this shape (real values):

{
  "schema": "prompt-report-1",
  "test_id": "AT0-ack-discipline",
  "agent": "claude-code",
  "steps": [
    {"name": "task-envelope-sent", "status": "pass|fail|skip", "detail": ""},
    {"name": "envelope-received", "status": "", "detail": ""},
    {"name": "ack-sent", "status": "", "detail": ""},
    {"name": "trivial-task-done", "status": "", "detail": ""},
    {"name": "completion-sent", "status": "", "detail": ""},
    {"name": "sender-history-order", "status": "", "detail": ""}
  ],
  "verdict": "pass if no step failed, else fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "", "finished_at": ""
}

Then print the single line: SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT0.json
