---
name: atm-hermes-ready
description: Verify the Hermes agents on a fixture are running and reachable over ATM before hermes-atm tests start: gateway processes alive, graft receivers registered with the daemon, and each agent answers a ping. Produces the standard ATM test report.
---

# atm-hermes-ready

One sentence triggers it: "run the atm-hermes-ready skill for <agent1@hermes agent2@hermes …>
and send the report to <agent@team.host>". The expected agent list comes from the request; `<team>`
below is the team of those agents (on the testbed fixture it is `testbed`, not `hermes`).

## Steps

0. **Start line.** Send the start line from `../atm-smoke/REPORT.md` (`ATM TEST START …`) to the requester
   before anything else. Observable: message id.
1. **Roster.** `atm members --team <team> --json` lists every expected agent. Observable: missing
   names.
2. **Receivers registered.** `atm doctor --team <team> --json`, field `.graft_receivers.receivers[]`:
   one entry per expected agent with a `last_seen` newer than 10 minutes. Print only the `agent`
   and `last_seen` fields; never print or copy `endpoint` or `capability`. Observable: agents
   without a receiver entry, stale entries.
3. **Ping.** Send each expected agent one line, `--requires-ack`, asking for an ack with the reply
   "ready". Observable: message id per agent.
4. **Pong.** Poll for 120 s from the ping (a real ack arrives in under 60 s; a wait line to the requester at
   60 s): every 10 s run exactly `atm list --unread --from <agent bare name> --contains ready --json`
   (bare name: `hermes`, never `hermes@testbed`) and read its `count`; 1 is the pong. Never filter
   `rows[]` yourself and never parse the JSON in a script: the command is the filter. Observable:
   seconds per agent, or timeout. Never conclude before the deadline: a reply that has not arrived at
   30 s or 90 s is not a result. When the 120 s pass without a reply the step is FAIL for that agent,
   cause `no ack within 120 s`; on a fixture whose gateway has no nudge adapter (atm-core #1307) that
   is the expected product finding, still reported as FAIL with that cause.

Never restart gateways or the daemon from this skill; report and stop.

## Report

Read `../atm-smoke/REPORT.md` (sibling skill directory) before writing: the report is that template
filled in, plain text, skill name `atm-hermes-ready`, one step line per agent for steps 2–4, nothing
before or after it. Every step line is PASS, FAIL or SKIP; PENDING is not a result. The report is
sent once, after every ack arrived or the 120 s deadline passed, never earlier; start and wait lines
precede it (see the template).

Report shape — copy it exactly, plain text, nothing before or after it, one step line per step
(the full rules are in `../atm-smoke/REPORT.md`):

```
ATM TEST REPORT
skill: atm-hermes-ready
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
