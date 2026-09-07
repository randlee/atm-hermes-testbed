---
sprint: TESTBED-SMOKE-SKILL-R1
id: TESTBED-SMOKE-SKILL-R1-1788803463
status: complete
branch: feature/smoke-skill
worktree: /Users/randlee/Documents/github/atm-hermes-testbed-worktrees/smoke-skill
repo: randlee/atm-hermes-testbed
assignee: loki (executing; envelope named arch-ctm — mismatch reported to fenix in ACK)
pr-target: main
---

# TESTBED-SMOKE-SKILL-R1 — hermes atm-smoke-test skill

Authoritative sprint doc (quoted verbatim from the assignment):

Rand, 2026-09-07: 'The tests should be very simple. For hermes tests the
hermes atm-smoketest skill should be used (or a derivative of it). You simply
tell the hermes agent to use the smoke-test skill and generate a report.'
Starting point: skillrx's checklist at
~/.hermes/profiles/skillrx/skills/hermes-atm-smoke-test.md on rand-m5 (48
lines: registration, validation, send, daemon resilience, atm_read,
atm_list, return contract, interop). The skill must live in the
atm-hermes-testbed repo so the containerized hermes-agent (fork) carries it.

## Deliverables (as landed)

- `testbed/skills/devops/atm-smoke-test/SKILL.md` — 12 observable checks
  derived from the skillrx checklist; fixed report shape; hard redaction
  rules. v1.1.0 correction: recipient is a PEER fixture member, never SELF
  (ATM rejects self-addressed sends — `SelfAddressedSendInvalid`); peer-side
  observation runs via terminal under the peer identity. v1.2.0 correction:
  check 12's peer substep is explicitly terminal-only, and PASS-with-note is
  scoped to genuine ack-state codes (`AckNotPending`) — any other error,
  including a misexecuted peer substep, is FAIL (a release gate must not
  mask misexecution as a pass).
- `Dockerfile` — one COPY baking the skill into `/opt/hermes/skills/devops/`;
  boot-time `tools/skills_sync.py` lands it in `$HERMES_HOME/skills`
  (fresh or existing volume). No other image change.
- `README.md` — one paragraph, three steps (build for tag, boot, tell the
  agent to run the skill and post the report).
- Proof run (see PR body): fresh container from the PR branch, agent told
  "run the atm smoke-test skill and send the report" → 12/12 PASS report
  sent by the agent via atm_send to the peer fixture.

## Scope guards honored

No changes to tiers, prompts, run.sh options, harness scripts, or the fork.
No options added. No redesign. env/allowlist.env never committed.
