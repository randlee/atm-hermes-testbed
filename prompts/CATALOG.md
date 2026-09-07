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

## Suite changelog

### suite/v2 (2026-09-07) — contract-driven expectation repair (v1.5.3 run)

Cut for the hermes-graft colima v1.5.3 readiness run (solar@atm-dev coord.,
task HERMES-GRAFT-COLIMA-R1-1788742538). Authorized by fenix (relay
01M1WXB6J117BP8HAH2HSXRZ17). This is **contract-driven expectation repair,
never rerun-until-green** — the first-run FAIL JSON is preserved at
`results-run-v153/tier-{a,b,d}.json` and the original evidence commit
(a13c3a1) is the durable record.

Root cause for all expectation changes: atm-core commit
`b84a9d2ef0cb7a3911ffe84642cb3e6f05b033e9` (`feat(ax1): add queue template
class`), in the v1.5.3 tag. It changed the built-in nudge templates in
`crates/atm-core/src/send/nudge_template.rs`:

- **B2a/B2b/B2c (envelope shape):** every built-in template now renders the
  action line as `atm read --message-id {{message_id}}` (was
  `read atm --team {{team}}`), and the **Task/Queue/QueueAck** classes
  intentionally **omit** the `<when idle=... busy=.../>` line while
  **Delivery/DeliveryAck retain** it. The testbed `expected_envelope()` was
  rewritten to render the product's own template strings verbatim (transcribed
  from `nudge_template.rs` at the tag) instead of a hand-maintained parallel
  copy, so the want-side cannot silently drift again. Verified byte-exact
  against the product on the pinned image.
- **D7 (herdr nudge routing):** private SQLite and daemon-log assertions were
  **dropped**. D7 now binds one message ID across public structured surfaces:
  roster `backend=herdr`, `send --json` outcome, and the receiver's durable
  `list --all --json` mailbox. It also checks that the Herdr agent remains
  reachable and that the send never reports `ATM_HERDR_UNAVAILABLE`.

**A1 — HOLD RELEASED, expectation repaired per ruling (arch-ctm via fenix,
solar relay 01M1WXG7TYNN09NWDJEVEKZPGS):** bare-`atm read` returning
`mutation_applied=true` without an immediately visible read mark is INTENDED
— `mutation_applied` means the read/seen transition was ACCEPTED by the
supervised non-blocking handoff, not yet durable. Bare read and
`--message-id` share `prepare_async_read`/`complete_async_read`; the observed
difference was scheduling, not semantics. Attribution: **atm-core PR #1278 /
ADR-059 / requirements 7.13**. A1 now asserts acceptance synchronously
(`mutation_applied=true`, `selection_mode=actionable`, matching
`message_id`) and durability by bounded poll of `atm list --json` until
`unread==0 && history==1` (15s deadline); it never requires
`message.read==true` in the immediate response. **General rule adopted for
ALL suite read-state assertions: assert accepted-vs-durable separately.**

**HGC-023 (AT8 RTT calibration marker, fenix-authorized
01M1WXW9R9Z7KH69CDVR4F6122):** AT8 step 2's `warmup_rtt_ms` had no path to
the outer coordinator before step 9 needs the calibrated `--after`. Repair:
agent writes sanitized integer marker `markers/at8-rtt` (ASCII digits +
newline only) after warm-up; coordinator waits ≤120s, validates
`^[0-9]+$`/1..60000 (missing/invalid = FAIL, never default/tune/retry),
computes `after_ms=clamp((rtt+1)/2, 300, 1500)`, runs
`freeze-daemon.sh 4 --after <after_ms> --source-rtt <rtt> --trigger ...`;
`at8-armed` records UTC + `after_ms` + `source_rtt_ms`; `at8-rtt` joins the
suite-start stale-marker cleanup. Attribution: testbed/prompts only, never
atm-core.

Prompt-side note: no `prompts/` content changed in suite/v2 (the AT4/AT8
no-sudo marker rewrite landed earlier at fb9d63c under suite/v1 with a
planned v2 bump at the v1.5.3 re-run). Prompts remain `since: suite/v1`; this
changelog records the deterministic-matrix (tiers A–D) contract repair. The
`suite/v2` tag is cut at the head of this validated cycle per the versioning
rule.

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
