---
id: AT10-assignment
agent: claude-code
model: sonnet
timeout_s: 900
report: /opt/testbed/results/prompt-AT10.json
since: suite/v3
---

# AT10 — assignment and task pass

Exercise task assignment as `fx-at10-alpha`, `fx-at10-beta`, and
`fx-at10-gamma` in team `fx-at10`. Use only public ATM CLI and JSON output.
Poll only public CLI observations at one-second intervals with a 30-second
deadline. Record exact command output or JSON excerpts in each report detail.

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

Use unique timestamped task ids and run these cases:

1. Assign three tasks to idle beta. Through `atm task events --json`, verify
   queued positions 1, 2, 3 and exactly one ready task. Run `atm list
   --pending-ack --json` as beta right after each of the three assignments
   (three separate runs) and quote all three outputs; each must report zero.
2. Start and complete the ready task. Verify through task events/list that
   the next task becomes ready within one bounded poll pass.
3. As assigner alpha, reassign a queued beta task to gamma. Public mail/events
   must show closed with reassigned outcome to beta and queued to gamma.
4. Assign tasks A then B to idle beta and wait until A shows `task_ready`.
   Then move B to head with `atm task move <B> --head`. PASS only if B's
   events then show exactly one `task_ready` and A's events still show exactly
   one `task_ready` (no duplicate ready event on either task).
5. As assigner alpha, assign a task to beta and, while it is still queued
   for beta, cancel it as alpha with `atm task close <id> cancelled`. PASS
   only if beta's `atm task events <id> --json` or beta's mail (`atm list` /
   `atm read` as beta) shows the cancelled terminal outcome delivered to beta.
6. Make alpha busy with a task, then have beta start and complete another
   alpha-assigned task. Alpha's unread/history CLI must contain both started
   and completed operations written in order.

Close all remaining tasks using public task commands. Write
`/opt/testbed/results/prompt-AT10.json` with exactly this shape, replacing
placeholders with real values. Verdict passes only when every step passes:

```json
{
  "schema": "prompt-report-1",
  "test_id": "AT10-assignment",
  "agent": "claude-code",
  "steps": [
    {"name": "three-queued-then-one-ready", "status": "pass|fail|skip", "detail": "exact CLI JSON excerpt"},
    {"name": "close-releases-next", "status": "pass|fail|skip", "detail": "exact CLI JSON excerpt"},
    {"name": "reassign-notifies-both", "status": "pass|fail|skip", "detail": "exact CLI JSON excerpt"},
    {"name": "move-head-readies-once", "status": "pass|fail|skip", "detail": "exact CLI JSON excerpt"},
    {"name": "cancel-notifies-assignee", "status": "pass|fail|skip", "detail": "exact CLI JSON excerpt"},
    {"name": "busy-assigner-sees-terminal-lines", "status": "pass|fail|skip", "detail": "exact CLI JSON excerpt"},
    {"name": "cleanup", "status": "pass|fail|skip", "detail": "exact CLI result"}
  ],
  "verdict": "pass|fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "RFC3339 timestamp",
  "finished_at": "RFC3339 timestamp"
}
```

Print exactly:

`SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT10.json`
