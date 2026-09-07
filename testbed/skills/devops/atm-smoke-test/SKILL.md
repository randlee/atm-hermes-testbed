---
name: atm-smoke-test
description: Use when asked to run the ATM smoke test. Exercises the native atm tools (atm_send/atm_read/atm_list/atm_ack) and CLI interop against the local ATM daemon and produces one sanitized PASS/FAIL report.
version: 1.0.0
metadata:
  hermes:
    tags: [atm, smoke-test, integration]
    category: devops
---

# ATM Smoke Test

Run every check below IN ORDER using your native ATM tools (`atm_send`,
`atm_read`, `atm_list`, `atm_ack`) and the `atm` CLI via terminal where the
check says CLI. Record PASS or FAIL for each item with the evidence named in
the check. Do not skip items; do not add items; do not retry a FAIL until it
passes — record the first outcome.

If a tool call errors, record the exact error `code` as the evidence for that
item and continue with the next item (a clean error envelope is itself the
observable outcome for validation checks).

## Identity

Your ATM identity is the `ATM_IDENTITY`/`ATM_TEAM` environment you run under.
"SELF" below means `<your-identity>@<your-team>.localhost` (e.g.
`smoke-alpha@smoke.localhost`). If a check needs a recipient and none was
given in your instructions, use SELF.

## Checks

1. **registration** — the native tools `atm_send`, `atm_read`, `atm_list` are
   available in your toolset. Evidence: PASS if all three can be invoked;
   FAIL naming any missing tool.
2. **atm-version** — terminal: `atm --version`. Evidence: the version string.
   PASS if it prints a version; FAIL on error.
3. **daemon-alive** — terminal: `pgrep -x atm-daemon`. Evidence: the pid.
   PASS if a pid is printed; FAIL if empty.
4. **validation-empty** — call `atm_send` with arguments `{}`. Evidence: PASS
   if the call is rejected with a validation error naming required fields;
   FAIL if it succeeds or errors without field requirements.
5. **validation-wrong-fields** — call `atm_send` with `{"recipient": "x",
   "message": "y"}` (wrong field names). Evidence: PASS if rejected as
   unknown/extra fields; FAIL otherwise.
6. **validation-bad-address** — call `atm_send` with `{"to":
   "no-at-sign-here", "body": "SMOKE"}`. Evidence: PASS if rejected with a
   clean error code (record the code); FAIL if it succeeds or returns a
   non-envelope error.
7. **send-self** — call `atm_send` with `{"to": "SELF", "body": "SMOKE <UTC
   timestamp>"}`. Evidence: PASS if the result contains `message_id` and
   outcome `sent`; record the message_id. FAIL with the error code otherwise.
8. **error-recovery** — immediately after the previous check (whether it
   passed or failed), call `atm_list` with `{"selection": "all", "limit":
   5}`. Evidence: PASS if it returns a row list with `bucket_counts` (a
   prior rejected/failed call did not poison the session); FAIL otherwise.
9. **list-contains-send** — inspect the `atm_list` rows from check 8 (or
   re-list with limit 10 if check 7 succeeded but the row was not in the
   first page). Evidence: PASS if check 7's `message_id` appears as a row;
   FAIL if absent.
10. **read-return-contract** — call `atm_read` with `{}` (no arguments).
    Evidence: PASS if the result is a JSON envelope containing `action`,
    `bucket_counts`, and `mutation_applied` (record `mutation_applied`'s
    value — true or false); FAIL if the call crashes or returns a
    non-envelope.
11. **cli-interop** — terminal: `atm list --json 2>/dev/null | head -c 200`
    (or `atm list` if `--json` is unsupported). Evidence: PASS if the CLI
    lists mail without error while the native tools also work (same daemon,
    same inbox); FAIL on CLI error.
12. **ack-self-message** — if check 7's message_id is present in your queue
    as a readable message, call `atm_ack` on it with reply `"SMOKE ack ok"`.
    Evidence: PASS if the ack succeeds OR fails with a clean error code
    (record which; self-messages may not require ack — a clean
    "not pending acknowledgement" error is PASS-with-note). FAIL only on a
    crash/non-envelope.

## Report

Produce ONE report with exactly this shape (fill every line):

```
ATM SMOKE REPORT
atm_version: <from check 2>
daemon_pid: <from check 3>
identity: <your ATM_IDENTITY>@<your ATM_TEAM>
started_at: <UTC ISO>
finished_at: <UTC ISO>
items:
  1 registration: PASS|FAIL <evidence>
  2 atm-version: PASS|FAIL <evidence>
  3 daemon-alive: PASS|FAIL <evidence>
  4 validation-empty: PASS|FAIL <evidence>
  5 validation-wrong-fields: PASS|FAIL <evidence>
  6 validation-bad-address: PASS|FAIL <code>
  7 send-self: PASS|FAIL <message_id or code>
  8 error-recovery: PASS|FAIL <evidence>
  9 list-contains-send: PASS|FAIL <evidence>
  10 read-return-contract: PASS|FAIL mutation_applied=<value>
  11 cli-interop: PASS|FAIL <evidence>
  12 ack-self-message: PASS|FAIL <evidence or code>
verdict: PASS (12/12) | FAIL (<n>/12)
```

Send the report with `atm_send` to the recipient named in your instructions
(default: SELF). If `atm_send` is unavailable or failing, print the report to
your final output instead and say why.

## Redaction rules (hard)

The report must contain ONLY: item names, PASS/FAIL, error codes, message
ids, version string, pid, identity name, UTC timestamps. NEVER include
message bodies (except the fixed SMOKE literals you generated), addresses or
chat ids other than your own identity, tokens, API keys, capability values,
or raw config. If an evidence value would leak any of these, replace it with
`<redacted>` and note the item.
