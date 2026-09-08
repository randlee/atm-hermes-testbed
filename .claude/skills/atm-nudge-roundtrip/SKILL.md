---
name: atm-nudge-roundtrip
description: The hermes-atm integration test: a tester agent sends an ack-required message to a Hermes agent, the Hermes agent is nudged, reads that exact message id with its native atm_read, acks natively, and the tester sees the ack. Both sides run the same skill. Produces the standard ATM test report.
---

# atm-nudge-roundtrip

Two roles, one skill. The request says which role you are.

- Tester: "run the atm-nudge-roundtrip skill as tester against <agent@hermes>, report to <agent@team>".
- Hermes side: "run the atm-nudge-roundtrip skill as responder, report to <agent@team>". The Hermes
  side normally needs no instruction: the nudge itself starts the responder steps.

## Tester steps

0. **Start line.** Send the start line from `../atm-smoke/REPORT.md` (`ATM TEST START …`) to the requester
   before anything else. Observable: message id.
1. **Send.** `atm send <hermes agent> --requires-ack --stdin <<'EOF'` with the single line
   `atm-nudge-roundtrip <run-id>: ack this message with reply "roundtrip <run-id>"` where run-id is
   the current unix time. Observable: message id, exit code.
2. **Ack arrives.** Every 10 s for up to 300 s run exactly
   `atm list --unread --from <agent bare name> --contains "roundtrip <run-id>" --json` (bare name:
   `hermes`, never `hermes@testbed`; the partner is an agent that must read and ack; a wait line to the
   requester every 60 s) until its `count` is 1; read that row by id. Never filter `rows[]` yourself and
   never parse the JSON in a script: the command is the filter. Observable: seconds, or timeout. Never conclude before the deadline. Timeout is
   FAIL, cause `no ack within 300 s`. (There is no step for "my message is no longer pending":
   `atm list --pending-ack` shows only messages *you* must ack, never the state of a message you sent.)

## Responder steps (Hermes agent)

0. **Start line.** Send the start line from `../atm-smoke/REPORT.md` (`ATM TEST START …`) to the requester
   before anything else. Observable: message id.
1. **Nudge received.** You received an `<atm …>` block naming a message id. Observable: the id.
   If you were started by the sentence instead of a nudge (a fixture whose gateway cannot inject,
   atm-core #1307): call native `atm_list()` (or `atm list --pending-ack --json` in your terminal tool —
   never `atm` inside a code-execution tool, it has no identity there and matches nothing), look for a
   row whose `summary` starts `atm-nudge-roundtrip`; if absent, `sleep 10` in the terminal and call
   again, up to 300 s, with a wait line to the requester every 60 s. The row is normally there on the
   first call. Write this step as `PASS Nudge received — none (polled, #1307), id <id>, <seconds>s`.
2. **Read by id.** `atm_read(message_id=<id>)`. Observable: `count` (must be 1); FAIL with the code
   if 0 or error.
3. **Ack natively.** `atm_ack(message_id=<id>, reply="roundtrip <run-id>")`. Observable: exit/ error
   code.
4. **List after idle.** Wait 5 s doing nothing, then `atm_list()`. Observable: exit or error
   code (FAIL on `MAY_HAVE_EXECUTED` or a connection error).

## Report

Read `../atm-smoke/REPORT.md` (sibling skill directory) before writing: the report is that template
filled in, plain text, skill name `atm-nudge-roundtrip`, first step line states the role, nothing
before or after it. Every step line is PASS, FAIL or SKIP; PENDING is not a result. The report is
sent once, after the last step finished or its deadline passed, never earlier; start and wait lines
precede it (see the template).

Report shape — copy it exactly, plain text, nothing before or after it, one step line per step
(the full rules are in `../atm-smoke/REPORT.md`):

```
ATM TEST REPORT
skill: atm-nudge-roundtrip
fixture: <fixture named in the sentence>
agent: <you>@<team>  tools: <cli | native | native+cli>
atm: client <x.y.z> daemon <x.y.z>
result: PASS | FAIL   (<passed>/<total> steps)
steps:
  0 PASS Start line — <message id>
  1 PASS <step name> — <observable: message id / count / exit code / error code / seconds>
  2 FAIL <step name> — cause: <component/evidence>; fix: <what you did | none possible>; retest: PASS|FAIL
  ...
elapsed: <seconds>s
```

The `atm:` line comes from `atm doctor --json` (`.client_context.version`, `.daemon_context.version`)
run in your terminal tool with your ATM identity in the environment — never guessed, never `0.0.0`.
`agent:` is your own name and team (`hermes@testbed`, `tester@testbed`), the same value as in your
start line. `result` is PASS only when every step line is PASS.
