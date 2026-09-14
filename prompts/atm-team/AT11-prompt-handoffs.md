---
id: AT11-prompt-handoffs
agent: claude-code
model: sonnet
timeout_s: 900
report: /opt/testbed/results/prompt-AT11.json
since: suite/v3
---

# AT11 — prompt handoffs

Exercise prompt-handoff behavior as `fx-at11-alpha` and `fx-at11-beta` in
team `fx-at11`. Observe only with public ATM CLI JSON (`atm task events`,
`atm task list`, `atm list/read`, and `atm doctor`). Never inspect SQLite,
daemon logs, processes, or terminal panes. The documented reminder default is
60 seconds. Poll every five seconds for at most 150 seconds to observe the
first reminder, derive the observed interval from ready/reminder timestamps,
then make case 2 wait `observed interval × 2`. Do not tune or retry these
bounds. Preserve exact JSON excerpts in report details.

Run these cases with unique timestamped ids:

1. Assign three tasks to beta. Poll each task with `atm task events <id>
   --json`. Wait until task 1 has queued, ready, and reminder evidence, then
   start it as beta and observe started. PASS only if task 1 shows queued,
   ready, reminder, started in order while tasks 2 and 3 show queued only.
2. Run `atm teams disable-nudge-template --team fx-at11 --kind
   task_reminder --json`, assign a new task, and wait longer than the reminder
   interval established in case 1. PASS only if public task events show
   queued and ready but no reminder and `atm doctor --json --team fx-at11`
   reports `disabled_task_nudge_template_override`.

Close all created tasks with public task commands. Write
`/opt/testbed/results/prompt-AT11.json` with exactly this shape, replacing
placeholders with real values. Verdict passes only if every step passes:

```json
{
  "schema": "prompt-report-1",
  "test_id": "AT11-prompt-handoffs",
  "agent": "claude-code",
  "steps": [
    {"name": "prompted-task-events-only", "status": "pass|fail|skip", "detail": "exact CLI JSON excerpts and observed interval"},
    {"name": "disabled-reminder-doctor-finding", "status": "pass|fail|skip", "detail": "exact CLI JSON excerpts"},
    {"name": "cleanup", "status": "pass|fail|skip", "detail": "exact CLI result"}
  ],
  "verdict": "pass|fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "RFC3339 timestamp",
  "finished_at": "RFC3339 timestamp"
}
```

Then print exactly:

`SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT11.json`
