---
id: AT6-template-task-dispatch
agent: claude-code
model: haiku
requires: [ANTHROPIC_API_KEY]
timeout_s: 120
report: /opt/testbed/results/prompt-AT6.json
since: suite/v1
---

You are the atm-team template-dispatch agent inside the hermes-docker-testbed
fixture. Your job: prove the `atm compose`/`atm send --template` rendered
task-dispatch path from atm-core docs/team-protocol.md ("Send Content, Not
Paths") and docs/atm/cli-reference (`--template`/`--vars`/`--var`), including
the ack -> work -> completion flow from docs/team-protocol.md, then emit a
structured report. Do each step in order; if a step fails, record it as
failed and continue.

Context already true in this fixture: the ATM daemon is running; team
`fx-at6` with members `fx-at6-alpha` and `fx-at6-beta` is registered by the
harness before you start; your workspace root is /opt/testbed/at6. Your
default identity is `fx-at6-alpha`.

Steps:

1. Author a minimal template at /opt/testbed/at6/at6-task.xml.j2 with YAML
   frontmatter (`name: at6-task`, `version: 1.0.0`, `format: xml`,
   `required_variables: [task_id, description]`) and body
   `<atm-task id="{{ task_id }}"><description>{{ description
   }}</description></atm-task>`.
2. Local preview (no mailbox mutation): `ATM_IDENTITY=fx-at6-alpha ATM_TEAM=fx-at6
   atm compose --template /opt/testbed/at6/at6-task.xml.j2 --var
   task_id=AT6-TASK-1 --var description="reply PASS or FAIL over ATM"`. Exit
   code 0. The rendered output contains the literal strings `AT6-TASK-1` and
   `reply PASS or FAIL over ATM` — not the raw `{{ task_id }}` /
   `{{ description }}` placeholders.
3. Dispatch: `ATM_IDENTITY=fx-at6-alpha atm send fx-at6-beta --team fx-at6
   --template /opt/testbed/at6/at6-task.xml.j2 --var task_id=AT6-TASK-1
   --var description="reply PASS or FAIL over ATM" --task-id AT6-TASK-1`.
   Exit code 0. Per docs/atm/commands/send.md, a task-linked send implies
   `requires_ack = true`.
4. Receive and verify rendering: `ATM_IDENTITY=fx-at6-beta atm read --team
   fx-at6 --json` returns a message whose body contains the same rendered
   variable substitutions as step 2 (not raw placeholders), with `task_id`
   `AT6-TASK-1` and a requires-ack flag set. Capture its message id.
5. Ack: `ATM_IDENTITY=fx-at6-beta atm ack <message_id> "ack, working on
   AT6-TASK-1" --team fx-at6`. Exit code 0.
6. PASS/FAIL completion report over ATM: `ATM_IDENTITY=fx-at6-beta atm send
   fx-at6-alpha "task complete: AT6-TASK-1 PASS" --team fx-at6`. Exit
   code 0.
7. Sender-side confirmation: `ATM_IDENTITY=fx-at6-alpha atm read --team
   fx-at6 --history --json` shows both the step-5 ack and the step-6
   PASS/FAIL completion.

REPORT CONTRACT — after step 7, write the file
/opt/testbed/results/prompt-AT6.json with exactly this shape (real values):

{
  "schema": "prompt-report-1",
  "test_id": "AT6-template-task-dispatch",
  "agent": "claude-code",
  "steps": [
    {"name": "template-authored", "status": "pass|fail|skip", "detail": ""},
    {"name": "compose-preview-rendered", "status": "", "detail": ""},
    {"name": "template-send-dispatched", "status": "", "detail": ""},
    {"name": "receiver-rendering-verified", "status": "", "detail": ""},
    {"name": "ack-sent", "status": "", "detail": ""},
    {"name": "pass-fail-report-sent", "status": "", "detail": ""},
    {"name": "sender-history-confirmed", "status": "", "detail": ""}
  ],
  "verdict": "pass if no step failed, else fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "", "finished_at": ""
}

Then print the single line: SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT6.json
