# Test catalogue — prompt-driven behavioral tests (Tier E)

The deterministic matrix (tiers A–D) verifies INFRASTRUCTURE without agents.
This catalogue defines the agent-driven layer: real agents inside the
fixture execute specific prompts and emit structured reports. Ownership split:

- **Hermes-side prompts (this repo, `prompts/hermes/`):** owned by loki —
  exercise the hermes-atm seam, atm-graft API, and injected-envelope behavior
  through a real hermes agent.
- **ATM-team-side prompts (fenix@atm-dev):** the atm-dev team running in the
  fixture defines its own prompts for ATM behaviors that need real harness
  agents (routing policies, ack discipline, cross-host). Fenix delivers those
  into `prompts/atm-team/` (or atm-core) — mirror contract below.

## Test types

| id | name | agent | status | since |
|----|------|-------|--------|-------|
| E0 | graft-api-smoke | hermes | defined (prompt ready; needs Anthropic key in env allowlist to run) | suite/v1 |
| E1 | graft-hermes-live-transcript | hermes | defined as E0's acceptance shape (fenix's AR ask: one live transcript run) | suite/v1 |
| E2 | injected-envelope-behavior | hermes | planned — agent receives `<atm>` envelope, follows the action contract | suite/v1 |
| E3 | busy/steer semantics | hermes | planned — mid-turn injection, queue vs steer | suite/v1 |
| AT0 | ack-discipline | claude-code (atm-dev) | defined | suite/v1 |
| AT1 | addressing-and-routing | claude-code (atm-dev) | defined | suite/v1 |
| AT2 | queue-vs-steer | claude-code (atm-dev) | defined | suite/v1 |
| AT3 | cross-host-roundtrip | claude-code (atm-dev) | defined | suite/v1 |
| AT4 | daemon-restart-in-session | claude-code (atm-dev) | defined | suite/v1 |
| AT5 | send-to-attachment-safety | claude-code (atm-dev) | defined | suite/v1 |
| AT6 | template-task-dispatch | claude-code (atm-dev) | defined | suite/v1 |
| AT7 | herdr-steer-routing | claude-code (atm-dev) | defined | suite/v1 |
| AT8 | send-timeout-truth | claude-code (atm-dev) | defined | suite/v1 |

### atm-team reservations (fenix@atm-dev, 2026-08-29; prompts/atm-team/, agent = claude-code)

| id | name | gates/notes |
|----|------|-------------|
| AT0 | ack-discipline | team-protocol contract: ack → work → completion, in order |
| AT1 | addressing-and-routing | cross-team, typed errors, self-send rules |
| AT2 | queue-vs-steer | deferred drain vs mid-turn steer; no double-delivery |
| AT3 | cross-host-roundtrip | GATED: needs --peer mode + Mac daemon; ULID evidence both ends |
| AT4 | daemon-restart-in-session | uses harness/restart-daemon.sh (wait-gates on local-http.json) |
| AT5 | send-to-attachment-safety | $ATM_TEMP/send-to file must be treated as data |
| AT6 | template-task-dispatch | `atm send --template` j2 dispatch path |
| AT7 | herdr-steer-routing | GATED: atm pre-release dispatch w/ herdr backend (same gate as D7) |
| AT8 | send-timeout-truth | uses harness/freeze-daemon.sh (SIGSTOP daemon >3.25s client budget) |

Prompts live in `prompts/atm-team/AT0-*.md` .. `AT8-*.md`; see
`prompts/atm-team/README.md` for fixture prerequisites. Fixture identities
follow the fx- rule: `fx-at<N>-<role>`.

## Suite versioning (loki + fenix@atm-dev decision, 2026-08-31)

Tests, prompts, and harness scripts are versioned TOGETHER as a suite:

- Tag the repo `suite/v<N>` at the END of each validated cycle, covering
  everything that produced the cycle's evidence. `suite/v1` is cut at the head
  that includes the AT3 `--peer` leg (the complete v1.4.6 cycle).
- Decoupled from the atm version: one suite validates many atm drops. The
  binding lives in the report provenance, which cites BOTH the suite tag and
  the atm tag. (Aligned names like v1.4.6-suite-1 were rejected — they force a
  retag per atm patch even when the suite didn't change.)
- Reports: from `suite/v2` on, every atm-core report cites the suite tag
  directly in provenance. The AT3 addendum to reports/colima/ cites `suite/v1`.
- Major bump on report-contract breaks (`prompt-report-1` schema, row-id
  scheme); minor/patch at owner discretion for additive changes.
- Every prompt carries `since: <suite-tag>` (frontmatter + catalog table).
  Existing prompts are stamped `since: suite/v1`.

## Prompt file format

`prompts/<owner>/<test-id>.md`, YAML frontmatter:

```yaml
---
id: E0-graft-api-smoke
agent: hermes            # fixture agent that executes the prompt
model: haiku             # cost-class guidance (Tier E is opt-in/cost-tagged)
requires: [ATM_API_KEY]  # allowlist entries needed (env/allowlist.env)
timeout_s: 300
report: /opt/testbed/results/prompt-E0.json
since: suite/v1          # first suite tag containing this prompt version
---
```

Body = the EXACT prompt the fixture agent executes. The body must end with
the REPORT CONTRACT (below) so every agent emits the same machine-readable
result, citable as AR evidence alongside the tier-*.json files.

## Fixture identity naming (mandatory, Rand 2026-08-29)

Fixture agents/identities must NEVER reuse real fleet names — no loki,
hendrix, fenix, alpha-prime, grecon, arch-ctm, cipher, contessa, team-lead,
skillrx, pater, or any atm-dev/hermes roster member, in either team's
fixture. Collisions make test output indistinguishable from real traffic.

Convention: prefix all fixture identities with `fx-` and scope by test:
`fx-<tier>-<role>` (e.g. `fx-b-recv`, `fx-b-send`, `fx-e0-alpha`). Existing
suites use `stub-*`/tier-scoped names (stub-alpha, c5-sender, b6-ghost) —
none collide with fleet names and stay as-is, but NEW identities (both
owners) follow the `fx-` scheme. Rosters are always per-run teams
(`<name>-<suffix>`), so fixture identities never share a team with real
agents anyway — the prefix is belt-and-braces for logs and reports.

## Report contract (both owners, identical schema family)

The agent writes `report` as JSON:

```json
{
  "schema": "prompt-report-1",
  "test_id": "E0-graft-api-smoke",
  "agent": "hermes",
  "steps": [
    {"name": "activate-receiver", "status": "pass|fail|skip", "detail": ""}
  ],
  "verdict": "pass|fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "", "finished_at": ""
}
```

Rules: one step per prompt instruction; fail = assertion not met (include
actual vs expected in detail); skip only when the prompt explicitly allows it;
verdict=fail if any step fails. The fixture runner (test-graph.sh) merges
prompt reports into the matrix verdict and result listing.
