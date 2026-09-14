---
id: AT10-assignment
agent: claude-code
model: sonnet
timeout_s: 900
report: /opt/testbed/results/prompt-AT10.json
since: suite/v3
---

# AT10 — assignment and task pass

Exercise task assignment as `fx-at10-alpha` and `fx-at10-beta` in team
`fx-at10`. Use only public ATM CLI and JSON output. Never inspect a database,
daemon log, process, or terminal pane. Poll only public CLI observations at
one-second intervals with a 30-second deadline. Record exact command output
or JSON excerpts in each report detail.

Use unique timestamped task ids and run these cases:

1. Assign three tasks to idle beta. Through `atm task events --json`, verify
   queued positions 1, 2, 3 and exactly one ready task. After each assignment,
   `atm list --pending-ack --json` for beta must report zero.
2. Start and complete the ready task. Verify through task events/list that
   the next task becomes ready within one bounded poll pass.
3. Reassign a queued task to alpha. Public mail/events must show closed with
   reassigned outcome to beta and queued to alpha.
4. While beta is idle, move a queued task to head with `atm task move`; the
   next observation must show one ready event and no duplicate ready event.
5. Cancel a queued task with `atm task close`; beta's public mail/events must
   show the cancelled terminal outcome.
6. Make alpha busy with a task, then have beta start and complete another
   alpha-assigned task. Alpha's unread/history CLI must contain both started
   and completed operations written in order.

Close all remaining tasks using public task commands. Write
`/opt/testbed/results/prompt-AT10.json` in the exact `prompt-report-1` shape
shown by `results-run-v146/prompt-AT0.json`, with test_id `AT10-assignment`,
one step per case plus cleanup, real versions/timestamps, and lowercase
statuses. Verdict passes only when every step passes. Print exactly:

`SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT10.json`
