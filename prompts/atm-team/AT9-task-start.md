---
id: AT9-task-start
agent: claude-code
model: sonnet
timeout_s: 600
report: /opt/testbed/results/prompt-AT9.json
since: suite/v3
---

# AT9 — task start

Exercise the ATM task-start contract as `fx-at9-alpha` (assigner) and
`fx-at9-beta` (assignee) in team `fx-at9`. Use only public ATM CLI commands.
Do not read a database, daemon log, process, or terminal pane. Capture exact
JSON excerpts in each report detail. Task reminders use atm-core's documented
60-second default: poll every five seconds for at most 150 seconds (two
intervals plus scheduling margin). A timeout is FAIL; do not tune or retry.

Run these cases with unique task ids containing the current Unix timestamp:

1. Assign one task with `atm task assign`, start it as beta with `atm task
   start`, then query alpha's unread mail with `atm list --unread --json` and
   read the matching message. PASS only if the public message/task operation
   identifies the started task before alpha performs that read.
2. Assign two tasks in order, start the second as beta, then run `atm task
   list --json` as beta. PASS only if the started task is active and ordered
   ahead of the still-assigned task.
3. Assign one task and do not start it. Poll `atm task events <task-id>
   --json` until at least two reminder events are visible. PASS only if the
   task remains assigned and both reminders are durable through the CLI.

Close every created task through `atm task close`; cleanup failure is a
failed step. Write `/opt/testbed/results/prompt-AT9.json` with exactly this
shape, replacing placeholders with real values. Verdict passes only when
every step passes:

```json
{
  "schema": "prompt-report-1",
  "test_id": "AT9-task-start",
  "agent": "claude-code",
  "steps": [
    {"name": "started-line-at-write-time", "status": "pass|fail|skip", "detail": "exact CLI JSON excerpt"},
    {"name": "out-of-order-start-reorders-queue", "status": "pass|fail|skip", "detail": "exact CLI JSON excerpt"},
    {"name": "unstarted-task-keeps-reminding", "status": "pass|fail|skip", "detail": "exact CLI JSON excerpt"},
    {"name": "cleanup", "status": "pass|fail|skip", "detail": "exact CLI result"}
  ],
  "verdict": "pass|fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "RFC3339 timestamp",
  "finished_at": "RFC3339 timestamp"
}
```

Then print exactly:

`SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT9.json`
