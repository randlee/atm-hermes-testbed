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
| send | `atm_send(to, body)` | `atm send <to> --stdin <<'EOF' … EOF` |
| list | `atm_list()` | `atm list --unread --json` |
| read by id | `atm_read(message_id=<id>)` | `atm read --message-id <id> --json` |
| peek | `atm_read(message_id=<id>, peek=True)` | `atm peek --message-id <id> --json` |
| ack | `atm_ack(message_id, reply)` | `atm ack <id> "<reply>"` |

## Steps

Partner = the agent named in the request; the partner runs this same skill at the same time, so
each side sends one message and handles the other's. ATM rejects self-addressed sends, so a partner
is required. Run-id = current unix time, used in your one-line body.

1. **Send.** One line `atm-smoke <run-id> from <you>` to the partner, ack required (CLI
   `--requires-ack`; native `requires_ack=True`). Observable: message id A; FAIL with the code on any
   error (`MAY_HAVE_EXECUTED` is a FAIL).
2. **Partner's message arrives.** List unread every 10 s for up to 300 s until a message from the
   partner whose summary starts `atm-smoke` is present; note its id B. Observable: seconds, id B.
3. **Peek does not mutate.** Peek B by id, then list unread: B still present. Observable: yes/no.
4. **Read by id.** Read B by id. Observable: `count` (must be 1) and `mutation_applied` where
   reported (must be true).
5. **Read marked it.** List unread: B gone. Observable: yes/no.
6. **Stale-connection probe.** Do nothing for 5 s, then list. Observable: exit or error code; FAIL on
   `MAY_HAVE_EXECUTED`, `RequestWrite`, or a connection error.
7. **Ack.** Ack B with reply `atm-smoke ack <run-id>`. Observable: exit or error code.
8. **Your message got acked.** Within 300 s the partner's ack reply (from the partner, containing
   `atm-smoke ack <run-id>`) appears in your unread list; read it. Observable: seconds, or timeout.
   (`atm list --pending-ack` shows what *you* still owe, so it is not the observable here.)

## Report

Exactly one message to the requester, template in `REPORT.md` next to this file, skill name
`atm-smoke`, `tools:` set to what you used.
