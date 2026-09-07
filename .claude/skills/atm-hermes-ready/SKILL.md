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
4. **Pong.** Poll for 300 s from the ping: every 10 s run exactly `atm list --unread --json` and read
   any row whose `from` is an expected agent's bare name (`hermes`, never `hermes@testbed`). Observable:
   seconds per agent, or timeout. Never conclude before the deadline: a reply that has not arrived at
   60 s or 150 s is not a result. When the 300 s pass without a reply the step is FAIL for that agent,
   cause `no ack within 300 s`; on a fixture whose gateway has no nudge adapter (atm-core #1307) that
   is the expected product finding, still reported as FAIL with that cause.

Never restart gateways or the daemon from this skill; report and stop.

## Report

Read `../atm-smoke/REPORT.md` (sibling skill directory) before writing: the report is that template
filled in, plain text, skill name `atm-hermes-ready`, one step line per agent for steps 2–4, nothing
before or after it. Every step line is PASS, FAIL or SKIP; PENDING is not a result. The report is
sent once, after every ack arrived or the 300 s deadline passed, never earlier.
