---
id: E0-graft-api-smoke
agent: hermes
model: haiku
requires: [ANTHROPIC_API_KEY]
timeout_s: 300
report: /opt/testbed/results/prompt-E0.json
---

You are the atm-graft API smoke agent inside the hermes-docker-testbed fixture.
Your job: verify EVERY atm-graft python API method works against the real
containerized ATM daemon, then emit a structured report. Do each step in
order. Do not skip a step; if a step fails, record it as failed and continue.

Context already true in this fixture: the ATM daemon is running
(/root/.atm/daemon/local-http.json exists); team `e0-smoke` with members
`fx-e0-alpha` and `fx-e0-beta` is registered by the harness before you start; your
workspace root is /opt/testbed/e0.

Steps:

1. Import check: in the hermes venv python (/opt/hermes/.venv/bin/python),
   `import atm_graft` succeeds and the module exposes PyGraftSession,
   PyGraftSessionOptions, PyAgentAddress.
2. Session: construct PyGraftSession(PyAgentAddress("fx-e0-alpha", "e0-smoke",
   "1001")) — construction succeeds, session state is usable.
3. Receiver activation: build PyGraftSessionOptions("/opt/testbed/e0",
   "fx-e0-alpha", "e0-smoke") and call activate_receiver(options, callback)
   with a callback that appends each nudge to a list. Activation returns
   without error and the graft endpoint record appears at
   /opt/testbed/e0/.atm/graft/e0-smoke/fx-e0-alpha.json within 10s.
4. Send from peer: run `atm send fx-e0-alpha "E0-SMOKE-1" --team e0-smoke` with
   ATM_IDENTITY=fx-e0-beta. Exit code 0.
5. Nudge receipt: within 30s your receiver callback fired; the nudge body
   begins with `<atm from="fx-e0-beta@e0-smoke"` and contains the message-id
   from step 4.
6. Read: run `atm read --team e0-smoke --json` as fx-e0-alpha; the message from
   step 4 is returned and marked read.
7. Close: call session close/deactivate; the graft endpoint record is removed
   or the session reports closed state without error.

REPORT CONTRACT — after step 7, write the file
/opt/testbed/results/prompt-E0.json with exactly this shape (real values):

{
  "schema": "prompt-report-1",
  "test_id": "E0-graft-api-smoke",
  "agent": "hermes",
  "steps": [
    {"name": "import-check", "status": "pass|fail|skip", "detail": ""},
    {"name": "session-construction", "status": "", "detail": ""},
    {"name": "receiver-activation", "status": "", "detail": ""},
    {"name": "peer-send", "status": "", "detail": ""},
    {"name": "nudge-receipt", "status": "", "detail": ""},
    {"name": "read-back", "status": "", "detail": ""},
    {"name": "session-close", "status": "", "detail": ""}
  ],
  "verdict": "pass if no step failed, else fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "", "finished_at": ""
}

Then print the single line: SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-E0.json
