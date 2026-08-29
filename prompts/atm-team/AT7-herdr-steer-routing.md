---
id: AT7-herdr-steer-routing
agent: claude-code
model: haiku
requires: [ANTHROPIC_API_KEY]
timeout_s: 90
report: /opt/testbed/results/prompt-AT7.json
---

You are the atm-team Herdr-routing agent inside the hermes-docker-testbed
fixture. Your job: prove a steer nudge is routed to a Herdr-backed receiver
(atm-core docs/atm-herdr/architecture.md, ADR-058,
docs/plans/phase-aq/sprint-AQ2-6-herdr-steer-backend.md), gated on `atm >=
1.4.5` and `herdr` on PATH, then emit a structured report. Do each step in
order; if a step fails, record it as failed and continue.

Context already true in this fixture, IF the gate is met: the ATM daemon is
running; team `fx-at7` with members `fx-at7-alpha` and `fx-at7-beta` is
registered by the harness before you start, with `fx-at7-beta` registered
`--backend herdr`. Your default identity is `fx-at7-alpha`.

Steps:

1. Version gate: capture the ATM version (via `atm doctor --json`'s version
   field if present, otherwise `atm --version` — the docs do not pin one
   exact surface for this, so verify with `atm --help` / `atm doctor --help`
   which one this build supports). If the version is below 1.4.5, record
   status "skip" with reason "atm < 1.4.5: herdr delivery backend absent"
   for every remaining step and stop (still write the full report).
2. Herdr-on-PATH gate: run `command -v herdr`. If it is not found, record
   status "skip" with reason "herdr not on PATH" for every remaining step
   and stop.
3. Backend registration check: inspect the roster for `fx-at7-beta`'s
   registered backend, e.g. `atm teams --members --json` (per
   docs/atm/cli-reference, the picker member projection includes per-member
   fields). If `fx-at7-beta` is not registered with the herdr backend,
   record status "skip" with reason "harness did not register herdr backend
   member" for the remaining steps and stop.
4. Steer send: `ATM_IDENTITY=fx-at7-alpha ATM_TEAM=fx-at7 atm send
   fx-at7-beta "AT7-HERDR-1" --team fx-at7`. Exit code 0.
5. Herdr routing evidence: within a 15s wait-gate (not pass/fail), check
   whether the dispatch used the herdr backend rather than tmux — via `atm
   log filter --match command=send` or `atm doctor --json`, whichever
   exposes a backend/channel field. Record the exact field/value you
   observe. If no documented log/doctor field distinguishes herdr routing
   from tmux routing, record status "skip" with reason "no documented field
   to assert herdr routing on".
6. Delivery confirmed regardless of routing evidence: `ATM_IDENTITY=fx-at7-beta
   atm read --team fx-at7 --json` shows the AT7-HERDR-1 message durably
   delivered.

REPORT CONTRACT — after step 6 (or immediately after any earlier skip gate),
write the file /opt/testbed/results/prompt-AT7.json with exactly this shape
(real values):

{
  "schema": "prompt-report-1",
  "test_id": "AT7-herdr-steer-routing",
  "agent": "claude-code",
  "steps": [
    {"name": "version-gate", "status": "pass|fail|skip", "detail": ""},
    {"name": "herdr-on-path-gate", "status": "", "detail": ""},
    {"name": "backend-registration-check", "status": "", "detail": ""},
    {"name": "steer-send", "status": "", "detail": ""},
    {"name": "herdr-routing-evidence", "status": "", "detail": ""},
    {"name": "delivery-confirmed", "status": "", "detail": ""}
  ],
  "verdict": "pass if no step failed, else fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "", "finished_at": ""
}

Then print the single line: SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT7.json
