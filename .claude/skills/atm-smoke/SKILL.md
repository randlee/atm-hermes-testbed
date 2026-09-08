---
name: atm-smoke
description: The ATM messaging smoke test every agent runs the same way on every fixture: send, list, read by message id, peek, ack, and a stale-connection probe. Uses native ATM tools when the agent has them (Hermes atm_send/atm_read/atm_list/atm_ack), otherwise the atm CLI. Produces the standard ATM test report.
---

# atm-smoke

One sentence triggers it: "run the atm-smoke skill against <partner agent@team> and send the report
to <agent@team>". Run `atm-setup-environment` first on a fresh fixture.

Tool rule: use the native tool when you have it, otherwise the CLI form. Report which you used.

| step | native (Hermes) | CLI |
|---|---|---|
| send, ack required | `atm_send(to, body, requires_ack=True)` | `atm send <to> --requires-ack --stdin <<'EOF' … EOF` |
| list ack-required inbox | `atm_list()` | `atm list --pending-ack --json` (rows carry `read` and `pending_ack`) |
| list plain inbox | `atm_list()` | `atm list --unread --json` |
| read by id | `atm_read(message_id=<id>)` | `atm read --message-id <id> --json` (`count`, `mutation_applied`) |
| peek | `atm_read(message_id=<id>, peek=True)` | `atm peek --message-id <id> --json` (`mutation_applied` false) |
| ack | `atm_ack(message_id, reply)` | `atm ack <id> "<reply>"` |

CLI surfaces are disjoint: an ack-required message is listed by `--pending-ack`, never by
`--unread`; the partner's ack reply is a plain message and is listed by `--unread`.

## Steps

Partner = the agent named in the request; the partner runs this same skill at the same time, so
each side sends one message and handles the other's. ATM rejects self-addressed sends, so a partner
is required. Run-id = current unix time, used in your one-line body.

S. **Start line.** Send ONE line `ATM TEST START skill: atm-smoke fixture: <fixture> agent: <you>` to the
   requester before anything else (see `REPORT.md`); never a second one; not a report step.
0. **Self round trip first.** CLI only, in your terminal tool: `atm send <you> --host localhost --stdin`
   with one line (native `atm_send` cannot address yourself — ATM rejects a self-addressed send; the
   `--host localhost` loop is the one form that works). Then `atm list --unread --json`, `atm read
   --message-id <id>`, list again: gone from unread. Observable: id, `count`, `mutation_applied`. Do not
   open or run any other skill for this. If this fails, the partner steps still run.
1. **Send.** One line `atm-smoke <run-id> from <you>` to the partner, ack required (CLI
   `--requires-ack`; native `requires_ack=True`). Observable: message id A; FAIL with the code on any
   error (`MAY_HAVE_EXECUTED` is a FAIL).
2. **Partner's message arrives.** Every 10 s for up to 300 s run exactly
   `atm list --pending-ack --from <partner bare name> --contains atm-smoke --json` (bare name: `tester`,
   never `tester@testbed`; native: `atm_list()` with the same filters) and read its `count`: 0 means not
   yet, 1 means the single row is B (note its `message_id`; `read` is false). A wait line to the requester
   every 60 s (`REPORT.md`). Never filter `rows[]` yourself and never parse the JSON in a script: the
   command is the filter. It may already be there before your own send: check first.
   Observable: seconds, id B, `read`. Nothing else finds it: `--unread` never lists an ack-required
   row, and a filter of your own invention is a FAIL of this step, not of the partner. The partner is
   a different agent on its own clock and may start minutes after you; poll until the full deadline
   and never conclude "partner not running" before it has elapsed.
3. **Peek does not mutate.** Peek B by id (`mutation_applied` false), then list again: B's row still
   has `read` false. Observable: `mutation_applied`, `read`.
4. **Read by id.** Read B by id. Observable: `count` (must be 1) and `mutation_applied` (must be true).
5. **Read marked it.** List the ack-required inbox again: B's row now has `read` true (allow 2 s for
   the queued handoff). Observable: `read`.
6. **Stale-connection probe.** Do nothing for 5 s, then list. Observable: exit or error code; FAIL on
   `MAY_HAVE_EXECUTED`, `RequestWrite`, or a connection error.
7. **Ack.** Ack B with reply `atm-smoke ack <run-id>`. Observable: exit or error code.
8. **Your message got acked.** Every 10 s for up to 300 s run exactly
   `atm list --unread --from <partner bare name> --contains "atm-smoke ack <run-id>" --json`; `count` 1
   means the partner's ack reply arrived: read it by id. Observable: seconds, or timeout.
   (`atm list --pending-ack` shows what *you* still owe, so it is not the observable here.)

## Report

After the start line and any wait lines, exactly one report to the requester, template in `REPORT.md` next to this file, skill name
`atm-smoke`, `tools:` set to what you used.

Report shape — copy it exactly, plain text, nothing before or after it, one step line per step
(the full rules are in `REPORT.md`):

```
ATM TEST REPORT
skill: atm-smoke
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
