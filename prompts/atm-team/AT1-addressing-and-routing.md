---
id: AT1-addressing-and-routing
agent: claude-code
model: haiku
requires: [ANTHROPIC_API_KEY]
timeout_s: 90
report: /opt/testbed/results/prompt-AT1.json
since: suite/v1
---

You are the atm-team addressing/routing agent inside the hermes-docker-testbed
fixture. Your job: exercise atm-core's addressing and routing rules (identity
resolution, cross-team send, unknown recipient, and the host-qualified
self-send exemption from docs/atm/commands/send.md and docs/requirements.md
§6.3), then emit a structured report. Do each step in order. Do not skip a
step; if a step fails, record it as failed and continue.

Context already true in this fixture: the ATM daemon is running; team `fx-at1`
with members `fx-at1-alpha` and `fx-at1-beta` is registered by the harness
before you start, and a second team `fx-at1b` with member `fx-at1b-gamma` is
also registered. Your default identity is `fx-at1-alpha`.

Steps:

1. Same-team send: `ATM_IDENTITY=fx-at1-alpha ATM_TEAM=fx-at1 atm send
   fx-at1-beta "AT1-SAME-1" --team fx-at1`. Exit code 0.
2. Cross-team send: still as `fx-at1-alpha`, run `atm send
   fx-at1b-gamma@fx-at1b "AT1-XTEAM-1" --team fx-at1` (explicit `@team`
   suffix takes precedence over `--team` per docs/requirements.md). Exit
   code 0. Verify delivery: `ATM_IDENTITY=fx-at1b-gamma atm read --team
   fx-at1b --json` returns the AT1-XTEAM-1 message.
3. Unknown recipient: `ATM_IDENTITY=fx-at1-alpha atm send
   at1-does-not-exist@fx-at1 "AT1-UNKNOWN-1" --team fx-at1 --json`. Expect a
   non-zero exit code. The docs do not pin one exact JSON error field/enum
   spelling for this case — inspect the actual `--json` error output and
   record in `detail` the exit code plus whatever error/code field and value
   you observe (do not assume a specific field name).
4. Identity-only self-send rejected: per docs/requirements.md §6.3 ("reject
   canonical same-team self-addressed sends ... only when the resolved
   destination has no host"), run `ATM_IDENTITY=fx-at1-alpha atm send
   fx-at1-alpha "AT1-SELF-1" --team fx-at1 --dry-run`. Expect a non-zero
   exit code / rejection before any dry-run success reporting.
5. Host-qualified self-send exempted: run `ATM_IDENTITY=fx-at1-alpha atm
   send fx-at1-alpha "AT1-SELF-HOST-1" --team fx-at1 --host localhost
   --dry-run`. Per docs/atm/commands/send.md, "any syntactically valid
   host-qualified destination, including localhost ... proceeds to the
   ordinary host-routing contract" — the self-send guard must NOT be the
   rejection reason here. Expect this to succeed (dry-run success) or, if it
   fails, expect the failure to be a host/peer-routing error distinct from
   the step-4 self-send rejection; record which occurred in `detail`.
6. Unqualified `--host` semantics not covered by steps 1-5: run `atm send
   --help` and record in `detail` whether its `--host` description matches
   docs/atm/commands/send.md's "qualifies the resolved recipient as
   agent@team.host" wording, since this is the only place the CLI's own
   help text is authoritative for this flag.

REPORT CONTRACT — after step 6, write the file
/opt/testbed/results/prompt-AT1.json with exactly this shape (real values):

{
  "schema": "prompt-report-1",
  "test_id": "AT1-addressing-and-routing",
  "agent": "claude-code",
  "steps": [
    {"name": "same-team-send", "status": "pass|fail|skip", "detail": ""},
    {"name": "cross-team-send", "status": "", "detail": ""},
    {"name": "unknown-recipient-typed-error", "status": "", "detail": ""},
    {"name": "identity-only-self-send-rejected", "status": "", "detail": ""},
    {"name": "host-qualified-self-send-exempted", "status": "", "detail": ""},
    {"name": "help-text-matches-docs", "status": "", "detail": ""}
  ],
  "verdict": "pass if no step failed, else fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "", "finished_at": ""
}

Then print the single line: SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT1.json
