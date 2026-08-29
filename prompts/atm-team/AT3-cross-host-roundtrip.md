---
id: AT3-cross-host-roundtrip
agent: claude-code
model: haiku
requires: [ANTHROPIC_API_KEY]
timeout_s: 180
report: /opt/testbed/results/prompt-AT3.json
---

You are the atm-team cross-host agent inside the hermes-docker-testbed
fixture. Your job: prove a real cross-host round trip and receiver-side
receipt evidence, never treating a local "sent" outcome as proof of receipt
(atm-core docs/plans/phase-ai/plan-phase-ai-crosshost-smoke-gaps.md, rule
AI.29: "Raw TCP success, local persistence, and a sender-side `sent` event
are insufficient evidence"). This test requires the fixture to be running in
`--peer` mode with a trusted Mac peer already configured. Do each step in
order; if a step fails, record it as failed and continue.

Context already true in this fixture, IF `--peer` mode is active: the ATM
daemon is running; team `fx-at3` with member `fx-at3-alpha` is registered
locally, and a mirrored roster on the trusted peer registers `fx-at3-beta` in
team `fx-at3`. Your default identity is `fx-at3-alpha`.

Steps:

1. Peer precondition: run `ATM_IDENTITY=fx-at3-alpha atm peer trust list
   --json`. If the command errors or returns an empty trusted-peer list,
   record status "skip" with reason "no trusted peer configured in this
   fixture run (--peer mode not active)" for every remaining step and stop
   (still write the full report). Otherwise capture the canonical trusted
   hostname as `<mac-host>`.
2. Cross-host send with ack: `ATM_IDENTITY=fx-at3-alpha atm send
   fx-at3-beta@fx-at3.<mac-host> "AT3-XHOST-1" --team fx-at3
   --requires-ack`. Exit code 0. Capture the resulting message ULID.
3. Sender-side wait-gate: poll (not pass/fail, up to 60s) `ATM_IDENTITY=fx-at3-alpha
   atm read --team fx-at3 --history --json` for an ack-class entry
   correlated with the step-2 ULID.
4. Receiver-side ULID evidence (AI.29 rule — this is the actual assertion,
   not step 3's local view): determine whether this container can reach the
   peer host's own log or mailbox state to confirm durable receipt (e.g. a
   harness-provided peer evidence path). If no such access exists from
   inside this container, record status "skip" with reason "container has
   no access to peer-host evidence; local send success is not proof of
   receipt (AI.29)". If access exists, confirm the message and its ULID are
   durably persisted on the peer side.
5. Ack correlation: if step 3 found an ack entry, verify its
   `acknowledges_message_id` (or equivalent correlation field) matches the
   step-2 ULID exactly — acknowledgement correlation is by immutable ULID,
   not delivery order (AI.32).

REPORT CONTRACT — after step 5 (or immediately after step 1 if skipped),
write the file /opt/testbed/results/prompt-AT3.json with exactly this shape
(real values):

{
  "schema": "prompt-report-1",
  "test_id": "AT3-cross-host-roundtrip",
  "agent": "claude-code",
  "steps": [
    {"name": "peer-trust-precondition", "status": "pass|fail|skip", "detail": ""},
    {"name": "cross-host-send", "status": "", "detail": ""},
    {"name": "sender-side-ack-wait", "status": "", "detail": ""},
    {"name": "receiver-side-ulid-evidence", "status": "", "detail": ""},
    {"name": "ack-ulid-correlation", "status": "", "detail": ""}
  ],
  "verdict": "pass if no step failed, else fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "", "finished_at": ""
}

Then print the single line: SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT3.json
