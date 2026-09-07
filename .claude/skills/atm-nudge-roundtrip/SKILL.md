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

1. **Send.** `atm send <hermes agent> --requires-ack --stdin <<'EOF'` with the single line
   `atm-nudge-roundtrip <run-id>: ack this message with reply "roundtrip <run-id>"` where run-id is
   the current unix time. Observable: message id, exit code.
2. **Ack arrives.** Poll `atm list --unread --json` every 10 s for up to 300 s until a row whose `from`
   is the agent's bare name (`hermes`, never `hermes@testbed`) and whose summary contains
   `roundtrip <run-id>` appears; read it. Observable: seconds, or timeout. Never conclude before the
   deadline; a reply missing at 60 s or 150 s is not a result. Timeout is FAIL, cause
   `no ack within 300 s` (on a fixture whose gateway cannot inject nudges, atm-core #1307, the
   responder is started by sentence instead and the ack still arrives; a timeout is then a real FAIL).
3. **State.** `atm list --pending-ack --json`: the id from step 1 is no longer pending.
   Observable: present yes/no.

## Responder steps (Hermes agent)

1. **Nudge received.** You received an `<atm …>` block naming a message id. Observable: the id.
   If you were started by the sentence instead of a nudge (a fixture whose gateway cannot inject,
   atm-core #1307), poll `atm list --pending-ack --json` every 10 s for up to 600 s for a row whose
   `summary` starts `atm-nudge-roundtrip`, take its `message_id`, and write this step as
   `PASS Nudge received — none (polled, #1307), id <id>, <seconds>s`.
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
sent once, after the last step finished or its deadline passed, never earlier.
