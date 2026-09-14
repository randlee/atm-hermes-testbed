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
daemon logs, processes, or terminal panes. Poll once per second with a
60-second deadline and preserve exact JSON excerpts in report details.

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
`/opt/testbed/results/prompt-AT11.json` using exactly the `prompt-report-1`
shape in `results-run-v146/prompt-AT0.json`, test_id
`AT11-prompt-handoffs`, one step per case plus cleanup, lowercase statuses,
real versions and timestamps. Verdict passes only if every step passes. Then
print exactly:

`SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT11.json`
