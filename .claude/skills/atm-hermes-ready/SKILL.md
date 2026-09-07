---
name: atm-hermes-ready
description: Verify the Hermes agents on a fixture are running and reachable over ATM before hermes-atm tests start: gateway processes alive, graft receivers registered with the daemon, and each agent answers a ping. Produces the standard ATM test report.
---

# atm-hermes-ready

One sentence triggers it: "run the atm-hermes-ready skill for <agent1@hermes agent2@hermes …>
and send the report to <agent@team.host>". The expected agent list comes from the request; `<team>`
below is the team of those agents (on the testbed fixture it is `testbed`, not `hermes`).

## Steps

1. **Roster.** `atm members --team <team> --json` lists every expected agent. Observable: missing
   names.
2. **Receivers registered.** `atm doctor --team <team> --json`, field `.graft_receivers.receivers[]`:
   one entry per expected agent with a `last_seen` newer than 10 minutes. Print only the `agent`
   and `last_seen` fields; never print or copy `endpoint` or `capability`. Observable: agents
   without a receiver entry, stale entries.
3. **Ping.** Send each expected agent one line, `--requires-ack`, asking for an ack with the reply
   "ready". Observable: message id per agent.
4. **Pong.** Within 300 s every agent's ack reply is in your inbox (`atm list --unread --json`, then
   read each). Observable: seconds per agent, or timeout. Any timeout is FAIL for that agent, cause
   `no ack within 300 s`; on a fixture whose gateway has no nudge adapter (atm-core #1307) that is
   the expected product finding, still reported as FAIL with that cause.

Never restart gateways or the daemon from this skill; report and stop.

## Report

Exactly one message to the requester, template `../atm-smoke/REPORT.md` (sibling skill directory), skill name
`atm-hermes-ready`, one step line per agent for steps 2–4.
