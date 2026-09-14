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
Capture exact JSON excerpts in each report detail. Task reminders use
atm-core's documented 60-second default: poll every five seconds for at most
150 seconds (two intervals plus scheduling margin). A timeout is FAIL; do not
tune or retry.

Rules for every case:

- Never read SQLite, daemon logs, processes, or terminal panes. Never run
  `env`, `ps`, or `strings`. Never read another prompt's report under
  `/opt/testbed/results/`.
- When a case names an event (queued, ready, reminder, started, reassigned,
  cancelled), PASS requires that event to appear in `atm task events
  <task-id> --json` output, as an `events[].event` or `handoffs[].kind` value
  (for example `task_ready`, `task_reminder`). A queue position or task state
  is not an event.
- Every detail quotes the actual CLI command and its output. Never write an
  inference as evidence; if the output does not show it, the step fails.
- Before the next case starts, close every task the case created with `atm
  task close`, so the assignee starts each case idle with an empty queue.
- Select the caller on each command with `--as <member> --team <team>` (or
  an `ATM_IDENTITY=<member> ATM_TEAM=<team>` prefix). Never read ATM config
  files; use `--help` for usage.
- Wait only in the foreground: a Bash polling loop with `sleep`, each Bash
  call at most 100 seconds, repeated as needed. Never run a command in the
  background and never use ScheduleWakeup or any delay/wakeup tool: this run
  is `claude -p`, which exits at the end of the turn, so a deferred wakeup
  never happens and no report is written.

Run these cases with unique task ids containing the current Unix timestamp:

1. Assign one task with `atm task assign`, start it as beta with `atm task
   start`, then query alpha's unread mail with `atm list --unread --json` and
   read the matching message. PASS only if the public message/task operation
   identifies the started task before alpha performs that read.
2. Assign two tasks in order, start the second as beta, then run `atm task
   list --json` as beta. PASS only if the started task is active and ordered
   ahead of the still-assigned task.
3. Assign one task and do not start it. Poll `atm task events <task-id>
   --json` until at least two `task_reminder` events are visible. PASS only
   if the task remains assigned and both reminders are durable through the
   CLI.

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
