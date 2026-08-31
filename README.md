# atm-hermes-testbed — isolated ATM graph testing for the hermes fork

**Owner:** loki · **Status:** PHASE 2 COMPLETE — infra matrix A–D + D7 green AND full prompt suite (E0 + AT0–AT8) validated on prerelease/v1.4.6 native arm64 (2026-08-31)

Isolated container testbed for the hermes-agent fork + ATM, and the backbone for
Phase AR release validation (atm pre-release dispatches). Migrated 2026-08-29
from `hendrix/hendrix/loki/docker-testbed` (full history preserved there).

## Goal

Run the hermes-agent fork (`randlee/hermes-agent`, branch `main`) inside a Docker
container and exercise ATM (Agent Team Mail) graph behavior against it in full
isolation: multiple agent identities, message routing, nudge round-trips, and the
hermes-atm injection seam — **without touching the host's live fleet, profiles,
env vars, or running agents.**

## Hard isolation rules (non-negotiable)

1. **HERMES_HOME wall** — container gets its own `HERMES_HOME=/opt/data/.hermes`
   (inside the image's data volume). The host `~/.hermes` is NEVER mounted.
2. **ATM wall** — containerized `atm` daemon with its own `$HOME/.atm`
   (own mail.db, own socket). Host daemon is unreachable from inside and vice versa.
3. **Env allowlist** — the ONLY secrets entering the container are those in
   `env/allowlist.env` (this repo, git-ignored content). The host
   `~/.hermes/.env` is never passed, whole or in part. Planned entries:
   `ANTHROPIC_API_KEY` (for haiku claude agents). Telegram gateway: use a
   dedicated test bot token or run gateway-less where the test allows.
4. **No host mounts of live state** — the fork source may be COPY'd at build time
   (immutable snapshot), never bind-mounted from a checkout another agent uses.

## Architecture

```
colima VM (arm64) ── docker daemon
   └── container (--platform linux/amd64, Rosetta)
        ├── hermes fork (built from Dockerfile in randlee/hermes-agent main)
        │    └── s6-overlay: gateway + hermes core (one test profile)
        ├── hermes-atm wheel (from wheelhouse / TestPyPI) — injection seam client
        ├── atm 1.4.3 linux-x86_64 (GitHub Release tarball — the installer path)
        │    └── own daemon, own ~/.atm, test team(s)
        ├── herdr 0.8.2 linux-x86_64 (musl static, from herdr releases)
        ├── tmux + rmux (rmux-parity layer)
        └── stub agents + haiku claude agents (graph test actors)
```

### Why amd64
atm-core publishes only `x86_64-unknown-linux-gnu`; colima VM is arm64.
Rosetta emulation verified working. Acceptable for a testbed; revisit if an
aarch64-linux atm archive ever ships.

### Agent surfaces
- **tmux + rmux** — the duplicated-behavior ground truth (hermes fleet today).
- **herdr** — native Rust binary runs on Linux (verified: CI full-suite on
  ubuntu, musl releases). Enables exercising the hmux plan (ap-84f) end-to-end.

### Graph-test actors (no LLM required for protocol tests)
- **Stub agents**: shell scripts in `atm read`/`atm ack` loops. Deterministic,
  free, repeatable. Cover routing/delivery/ack/nudge semantics.
- **Haiku claude agents**: real claude-code processes (haiku model, Anthropic
  key from allowlist) for behavior-level tests of the injected-envelope flow.

## Phases

- **Phase 0** ✅ colima up, docker OK, amd64 emulation OK, installer paths verified
- **Phase 1** ✅ build fork image; extend with testbed layer; seam proven
  (`prove.sh` — real send → daemon → graft → `inject_internal_message` → adapter)
- **Phase 2** graph test matrix — infrastructure verification (deterministic,
  zero-cost, no LLM):
  - **Tier A** ✅ mailbox semantics (8/8): send/read/history, pending-ack
    lifecycle, isolation, ordering, unknown recipient, ack reply, cross-team,
    body fidelity
  - **Tier B** ✅ seam + envelope fidelity (6/6): seam regression, byte-exact
    Delivery/DeliveryAck/DeliveryTaskAck envelopes, `<atm kind="ack">` to a
    second receiver, no-receiver queueing
  - **Tier C** ✅ tmux surface (6/6): headless server, windows/panes/titles,
    send-keys execution, capture fidelity, **daemon→tmux-pane nudge routing**
    (roster pane-id → TmuxSteer channel), lifecycle
  - **Tier D** ✅ herdr surface (6/6 + 1 skip): headless server, workspace
    round-trip, split/rename, pane run, wait-output sentinel, agent list.
    D7 (ATM→herdr nudge routing) skipped: herdr delivery backend is Phase AQ,
    NOT in the container's atm 1.4.3 release — unblock when atm ≥1.4.4 ships.
  - **Tier E** gateway behavior (real haiku agents, opt-in)
  - **Tier F** topology (phase 3)
  Runner: `testbed/test-graph.sh` (in-container), host-side `prove.sh`.
  Exit: reproducible `test-graph.sh` green on a fresh container.
- **Phase 3** compose topology: agent-per-container sharing an atm socket volume;
  multi-host-like graphs; soak.

## Phase AR integration (fenix@atm-dev, 2026-08-28)

The testbed is the backbone for Phase AR release validation of **atm 1.4.6**
(integration target — 1.4.4 is released/out of scope; Rand directive).

PR status (fenix@atm-dev, 2026-08-29):
- **#1095** request-budget / stale-connection-after-daemon-restart fix —
  MERGED to develop (`68c383e5e`). Product under the AT4 restart tier —
  AT4 is the regression probe for #1095 (post-restart send succeeds with
  zero manual steps on 1.4.6; 1.4.3 fails it). NOT AT8: a full SIGSTOP
  before the daemon reads the request is a genuinely lost write on both
  versions (fenix correction 2026-08-29). AT8 tests the retry decision rule
  and must behave the SAME on 1.4.3 and 1.4.6; a difference is a finding.
- **#1097** native aarch64-unknown-linux-gnu release target — MERGED
  (`ae03b6a91`), closes #1057. First dispatch ships an arm64 tarball → the
  testbed can drop amd64 emulation for native arm64 (follow-up after drop).
- **#1096** prerelease-archive job + `just prerelease-tag` — MERGED. First
  dispatch landed (team-lead bundle 2026-08-29, message 01M17F59FXBS65H6KC5D7D4P3W):
  - tag `prerelease/v1.4.6`, atm_core_sha `713f17e203addcf7c6c602ad158107fb489407c9`
  - archive workflow run 33241377678 (all 5 targets green, checksums job green);
    `atm_1.4.6_aarch64-unknown-linux-gnu.tar.gz`
    sha256 `42eb708e5d0c94f218f34362b3d5369b02235acc796fcee6d17b3779a07cd389`
    — **verified locally: download matches byte-for-byte**
  - wheels CI run 33241429677 at the tag sha; `hermes-atm-wheels-linux-aarch64`
    job 99071351864 (zip sha256 `37add5e9…`, artifact-zip integrity level);
    inner wheels: `atm_graft-1.4.6-cp311-abi3-manylinux_2_17_aarch64…`
    sha256 `09f45cde…`, `hermes_atm-1.4.6-py3-none-any.whl` sha256 `5559a8bb…`
  - Known CI caveat: 3 "Just lint" jobs failed on that run — pre-existing
    version-literal test defect being fixed by arch-ctm, unrelated to wheel content.
- **Validation target:** A–D + D7 + AT suite on NATIVE arm64 (no qemu timing
  caveats on this host). E0/AT* prompt execution still gated on
  ANTHROPIC_API_KEY in env/allowlist.env.
- **Daemon startup gate — mTLS (introduced 1.4.3→1.4.4, NOT 1.4.6 — corrected
  by fenix@atm-dev 01M17HN742SV1CMN9CSR5VZR1H; verified at source: peer-tls
  crate exists at v1.4.4, absent at v1.4.3):** the daemon refuses to start
  without mTLS config ("mTLS requires one enabled peer interface" /
  "configured local identity"). Fix: `harness/setup-mtls.sh` (recipe from
  atm-core scripts/smoke/benchmark_mtls.py: self-signed cert bundle +
  `atm peer interface set --bind 127.0.0.1:43101 --enabled` +
  `atm peer certificate init`); run.sh runs it automatically after boot.
  Pitfall found: `atm peer certificate show` prints "null" with exit 0 when
  absent — the idempotency check must test the value, not the exit code.
- **D7 status:** IMPLEMENTED and PASSING on prerelease/v1.4.6 (native
  arm64). Assertions target the routing contract (backendType=herdr
  metadata persisted, send dispatched without ATM_HERDR_UNAVAILABLE,
  daemon log outcome=sent, agent snapshot reachable) — NOT pane-text
  rendering, because the hermes TUI input buffer doesn't appear in
  pane capture (verified). Pitfall: `--backend herdr --session <name>`
  makes the daemon probe `sessions/<name>/herdr.sock`; the default server
  uses the default socket, so D7 registers WITHOUT --session.

- **Install target:** the first pre-release dispatch carrying the Phase AQ
  herdr backend (planned as **1.4.6** per Rand's mandatory patch++ bump rule;
  tag `prerelease/vX.Y.Z`). The linux tarball comes from the
  `prerelease-archive` CI job (PR #1096, owned by team-lead@atm-dev). Wheels
  from the `hermes-atm-wheels-linux-x86_64` CI artifact of the same run. D7
  unblocks with that tarball (herdr backend verified absent from both v1.4.3
  and v1.4.4 tags).
- **Override contract (build.sh):** `ATM_TARBALL=<path>`, `WHEELS_DIR=<path>`;
  checksums recorded to `assets/asset-provenance.txt`. Dockerfile takes
  ATM_TARBALL / HERMES_ATM_WHEEL / ATM_GRAFT_WHEEL build args — identical
  installer path for pinned releases and pre-release drops.
- **Machine-readable results:** each suite emits `/opt/testbed/results/tier-<x>.json`
  (schema v1: tier/suite/verdict/counts/tests/versions/image digest/host/durations)
  — citable as AR evidence without post-processing.
- **Item 7 (accepted):** container daemon as a cross-host PEER of the Mac daemon.
  `run.sh --peer` publishes 43101 (atm peer https) + 2222 (sshd) and maps the
  Mac hostname for hostname-based peer trust; peer mode OFF by default.
  **Wall-exception record (accepted by fenix@atm-dev, 2026-08-29):** sshd runs
  key-only (`PasswordAuthentication no`, no passwords anywhere) with a
  throwaway build-time ed25519 keypair; root login is PERMITTED but key-only
  (`PermitRootLogin prohibit-password`) because the container's ATM daemon
  context lives at `/root/.atm` and the smoke harness's `ssh <peer> atm ...`
  must land in that same context. Config: `/etc/ssh/sshd_config.d/testbed.conf`.
- **Constraints:** qemu x86_64 = diagnostics only, no wall-clock assertions
  (benchmarks stay on m5-atmbench); zero colima-specific code (GH-runner portable).

## Ownership & contacts (Phase AR)

- aarch64-linux archive PR + AR1.1 prerelease-archive job (`feature/ar1-prerelease-archive`,
  PR #1096): owned end-to-end by **team-lead@atm-dev** (QA/merge/post-merge
  dispatch). The provenance bundle {atm_core_sha, prerelease run id, ci run id}
  comes from team-lead after the first dispatch on the develop head.
  fenix@atm-dev stays reachable for Phase-AR-level questions.
- Rand's drift rule (mandated for every test publish): plain patch++ workspace
  version bump + mandatory tag `prerelease/vX.Y.Z` as the only dispatchable ref
  (`just prerelease-tag`). First dispatch is planned as **1.4.6**
  (`atm_1.4.6_<triple>.tar.gz`) — so the integration target is "the first
  pre-release dispatch carrying the Phase AQ herdr backend", NOT a hardcoded
  version; the result JSON's versions/provenance fields are the drift detector.

## Skills produced
- `docker-hermes-testbed` — build/run/teardown + env-allowlist policy (phase 1)
- `atm-graph-tests` — test matrix + harness (phase 2)

## Repeatable process
**`SMOKE-TEST-RUNBOOK.md`** — the complete, documented smoke-test process
(build → boot → matrix → prompt suite → evidence → final report to
atm-core `reports/colima/` → optional cross-host peer leg → suite tag).
Mandated by Rand 2026-08-31.

## Suite versioning (loki + fenix@atm-dev, 2026-08-31)
Tests, prompts, and harness scripts are versioned together: repo tag
`suite/v<N>` cut at the END of each validated cycle, decoupled from the atm
version (one suite validates many drops; report provenance cites both tags).
Every prompt carries `since: <suite-tag>`. `suite/v1` covers the complete
v1.4.6 cycle (cut once the AT3 `--peer` leg lands). Details in
`prompts/CATALOG.md` + runbook step 5b.

## Key paths
- Project: `~/Documents/github/atm-hermes-testbed/`
- Fork source (build context, read-only): `~/Documents/github/hermes-agent-randlee`
- Wheelhouse: `~/.hermes/wheelhouse/` (hermes_atm-1.4.2 py3-none-any)
- atm release: github.com/randlee/atm-core/releases (v1.4.3, linux x86_64)
- herdr release: github.com/herdrdev/herdr/releases (v0.8.2, linux x86_64/aarch64)
