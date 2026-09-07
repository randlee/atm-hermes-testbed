# Complete smoke-test runbook — atm-hermes-testbed

The single repeatable process for validating an ATM release dispatch against the
hermes-agent fork, end to end, in full isolation. Every step is idempotent and
safe to re-run. Owner: loki. Mandated by Rand 2026-08-31 (green light: run until
everything is green; document the complete process).

## Prerequisites

- colima/Docker up (`docker info`); this host is arm64 → use `TESTBED_PLATFORM=arm64`.
- The release drop's artifacts on disk (team-lead provenance bundle):
  - `ATM_TARBALL` → `atm_<ver>_<triple>.tar.gz`
  - `WHEELS_DIR` → unzipped `hermes-atm-wheels-linux-<triple>` artifact dir
- Verify the tarball sha256 against the bundle BEFORE building:
  `shasum -a 256 $ATM_TARBALL`
- `env/allowlist.env` exists with `ANTHROPIC_API_KEY` (+ `ANTHROPIC_WORKSPACE_ID`
  if the key is workspace-scoped). Values NEVER appear in commits, logs, reports,
  or summaries. The file must be untracked (run.sh hard-fails otherwise).
- Cross-team ATM sends use: `ATM_IDENTITY=loki ATM_TEAM=hermes atm send fenix --team atm-dev "..."`
  (wrong team env bleeds → bogus `loki@atm-dev` sender stamp).

## Step 0 — build the images

```sh
cd ~/Documents/github/atm-hermes-testbed
TESTBED_PLATFORM=arm64 ATM_TARBALL=<bundle tarball> \
  WHEELS_DIR=<unzipped wheels dir> ./build.sh all
```

- Layout-tolerant: 1.4.6+ tarballs nest under a top-level dir; the Dockerfile
  handles both layouts.
- Checksums land in `assets/asset-provenance.txt` (committed with results).

## Step 1 — boot the isolated container

```sh
TESTBED_PLATFORM=arm64 ./run.sh            # standard isolated run
TESTBED_PLATFORM=arm64 ./run.sh --peer rand-m5.local   # cross-host mode (Step 6)

# Citable release evidence fails closed unless provenance is supplied:
ATM_CORE_SHA=<40-hex> CI_RUN_ID=<archive-and-wheel-run-ids> \
  HERMES_FORK_SHA=<40-hex> TESTBED_PLATFORM=arm64 \
  ./run.sh --release-proof
```

- `run.sh` runs `harness/setup-mtls.sh` automatically (ATM ≥1.4.4 daemons refuse
  to start without mTLS: one enabled peer interface + local certificate).
- Walls: own `HERMES_HOME=/opt/data/.hermes`, own `/root/.atm`, env allowlist only.
- Verify daemon up inside: `docker exec hermes-testbed atm doctor` → DAEMON-UP.
- `--release-proof` forwards the three immutable source identifiers and the
  inspected image digest. Tier JSON refuses citable status when any is absent;
  ordinary local runs remain available and mark `evidence.citable=false`.

## Step 2 — infra matrix (Tier A–D + D7)

```sh
docker exec hermes-testbed /opt/testbed/test-graph.sh
```

- Emits `/opt/testbed/results/tier-{a,b,c,d}.json` (schema v1).
- Expected on a green release: A 8/8, B 6/6, C 6/6, D 6/6 + D7 PASS.
- D7 asserts the routing contract entirely through public structured surfaces:
  roster `backend=herdr`, send outcome/message ID, that exact ID in the durable
  receiver mailbox, and post-send Herdr agent reachability. It does not inspect
  SQLite, daemon-log serialization, or pane text.
- D7 pitfall: register members WITHOUT `--session`; the default herdr socket is
  the contract. Per-session sockets require matching `HERDR_SESSION` paths.

## Step 3 — prompt suite (E0 + AT0–AT8, real Anthropic key)

```sh
docker exec hermes-testbed /opt/testbed/harness/run-prompts.sh E0
docker exec hermes-testbed /opt/testbed/harness/run-prompts.sh AT0   # … AT1..AT8
```

- Requires `ANTHROPIC_API_KEY` in the allowlist (harness SKIPs otherwise).
- Each run writes a `prompt-report-1` JSON to `/opt/testbed/results/`;
  the harness echoes PASS/FAIL/SKIP.
- Prompt execution is unattended-safe: frontmatter must select `haiku` and a
  positive wall-clock timeout; the harness adds only a 30-second shutdown
  margin, preserves the agent exit status, and leaves no API key in a
  generated script or command argument.
- Harness invariants (do not regress):
  - **NO-SUDO model (solar P0 ruling 2026-09-07, implemented at main 41fc546):**
    the image contains no `sudo` package and no sudoers entries; the daemon
    lifecycle hooks refuse to run as non-root. The outer coordinator invokes
    them OUT OF BAND via root-default
    `docker exec hermes-testbed /opt/testbed/harness/<hook>`; the unprivileged
    fixture agent never execs a hook — it coordinates through marker files
    under `/opt/testbed/results/markers/` (chowned to the agent).
    Expected-marker table (writer → reader → content → lifecycle):

    | marker | writer | reader | content | lifecycle |
    |--------|--------|--------|---------|-----------|
    | `at4-ready` | fixture agent | coordinator (`restart-daemon.sh`) | touch only | cleared at suite start + hook arm |
    | `at4-done` | coordinator hook | fixture agent (poll) | UTC ISO ts | written post-restart |
    | `at8-rtt` | fixture agent (AT8 step 2) | coordinator (`at8-calibrate.sh`) | ASCII integer RTT ms + newline ONLY | cleared at suite start; HGC-023 |
    | `at8-armed` | coordinator hook | fixture agent (poll) | UTC ts + `after_ms=<n>` + `source_rtt_ms=<n>` | cleared at hook arm |
    | `at8-trigger` | fixture agent (step 10, &&-chained before send) | coordinator hook | touch only | cleared at suite start + hook arm |
    | `at8-done` | coordinator hook | fixture agent (poll) | UTC ISO ts | written post-SIGCONT |

    - AT4: agent `touch markers/at4-ready` → hook restarts daemon →
      `markers/at4-done` (UTC ISO content); agent polls, then post-restart sends.
    - AT8 branch (b), HGC-023 calibrated flow (fenix 01M1WXW9R9Z7KH69CDVR4F6122):
      agent measures warmup RTT (step 2) and writes the sanitized integer to
      `markers/at8-rtt`; coordinator runs `harness/at8-calibrate.sh` (bounded
      wait ≤120s, validates `^[0-9]+$` range 1..60000, computes
      `after_ms=clamp((rtt+1)/2, 300, 1500)`; missing/invalid = FAIL
      "calibration marker missing/invalid", never default/tune/retry), then
      Phase A `freeze-daemon.sh 4`, then Phase B `freeze-daemon.sh 4
      --after <after_ms> --source-rtt <rtt> --trigger markers/at8-trigger`.
      The hook fail-closes on invalid args (after requires source-rtt;
      after ∈ 300..1500; rtt ∈ 1..60000) BEFORE any signal. Agent touches
      the trigger &&-chained immediately before its send, so the calibrated
      delay starts at agent-owned trigger time (persist-then-freeze, reply
      past the 3.25s budget). Deterministic helper tests:
      `harness/test-at8-calibrate.sh` (host-runnable; 19 cases).
    - Coordinator clears stale markers (`at4-ready`, `at8-rtt`,
      `at8-trigger`) before a run (run-prompts.sh AT8 case does this);
      hooks also clear their own at arm time.
    - AT4/AT8 prompt text is UPDATED to this protocol (fenix sign-off +
      HGC-023 draft 01M1WXZXVH1A178ARNNQE3NX72 applied 2026-09-07).
  - daemon kills use exact `pkill -x atm-daemon` (never `-f` — the agent's own
    argv contains the prompt text and `-f` self-killed AT4);
  - `restart-daemon.sh` deletes stale `local-http.json` BEFORE relaunch and
    re-opens the republished record to readable perms AFTER (daemon writes 0600).
- AT4 is the regression probe for randlee/atm-core#1095; AT8 proves the retry
  decision rule (must behave identically across versions — a difference is a
  finding, not a pass).

## Step 4 — collect evidence

```sh
mkdir -p results-run-v<ver>
docker cp hermes-testbed:/opt/testbed/results/. results-run-v<ver>/
git add results-run-v<ver> assets/asset-provenance.txt && git commit && git push
```

## Step 5 — final report (Rand directive 2026-08-31)

Durable readiness record (atm-core side, solar@atm-dev):
`docs/runbooks/hermes-graft-colima-integration.md` — atm-core draft PR
[#1276](https://github.com/randlee/atm-core/pull/1276) (commit 0db13f3b0).
It cites THIS runbook + testbed main as the authoritative implementation and
leaves mutable operating commands here; cite the PR/doc path back in cycle
reports from the v1.5.3 run on (one source of truth each side).

Assemble the full cycle report into **atm-core `reports/colima/`** (fenix
correction 2026-08-31: there is no `sites/reports/` — repo-root
`reports/<family>/` is the convention, `site/reports/` is published-HTML only),
following the smoke pattern:
- paired `<timestamp>-colima-v<ver>.md` + `.json`;
- md header: `status`, `timestamp`, binary/tag SHA, `duration`, summary
  (`pass=N fail=N skip=N`) + the row-semantics note;
- verdict table: `| Row | Flow | Verdict | Notes |` with stable row ids
  `AS-COLIMA-<TIER|PROMPT>-nnn` (e.g. `AS-COLIMA-AT4-001`);
- provenance block: tag + atm_core_sha, CI run ids, image digest, per-file sha256;
- copied tier/prompt JSONs must be byte-identical to `results-run-v<ver>/`
  (`cmp` before commit); the `.md` is authored narrative over them;
- sign-off line: `Validated-by: loki@hermes; Co-signed: fenix@atm-dev (Phase AS owner)`
  — fenix co-signs after review; send the branch to fenix BEFORE the PR
  (target `develop`, doc-lint path).
- **suite citation:** from `suite/v2` on, the provenance block cites the suite
  tag directly alongside the atm tag (binding: suite tag ↔ atm tag). The
  suite/v1 cycle is the exception — its report merged sha-pinned before the
  scheme existed; the AT3 addendum cites `suite/v1`.

## Step 5b — cut the suite tag (loki + fenix@atm-dev, 2026-08-31)

Tests, prompts, and harness scripts are versioned TOGETHER:

```sh
# at the END of a validated cycle, once all cycle evidence is committed:
git tag -a suite/v<N> -m "suite v<N>: <cycle summary, atm tags validated>"
git push origin suite/v<N>
```

Rules:
- `suite/v<N>` is decoupled from the atm version — one suite validates many
  atm drops; the report provenance cites BOTH tags.
- Tag at cycle END so it covers everything that produced the cycle's evidence.
- Major bump on report-contract breaks (`prompt-report-1` schema, row-id
  scheme); minor/patch at owner discretion for additive changes.
- Every prompt carries `since: <suite-tag>` (frontmatter + CATALOG.md table).
- `suite/v1` is cut at the head including the AT3 `--peer` leg (the complete
  v1.4.6 cycle) — NOT retroactively before AT3 lands.

## Step 6 — cross-host peer leg (AT3) — optional, needs host coordination

The ONE documented wall exception (AR item 7, accepted by fenix@atm-dev):
published ports + sshd. Tight scope. **VM-internal architecture per
COLIMA-VM-INTERNAL-PLAN.md (C1–C5) and Rand's Q1 ruling
(2026-09-06): the peer authority name is `atm-hermes-testbed.local` —
NEVER `localhost`** (the host's localhost trust entry pins the host daemon's
own cert, so a localhost-addressed dial pin-mismatches):

1. Host side (reversible, fenix's daemon): add the container's cert
   fingerprint to host trust under the NAMED authority:
   container cert fp = sha256 of `docker exec hermes-testbed cat /root/.atm/peer/local.crt`
   `atm peer trust add atm-hermes-testbed.local --fingerprint <fp> --https-port 43102`
   + host `/etc/hosts` maps `atm-hermes-testbed.local` → the colima VM IP.
2. Start the container with `--peer rand-m5.local`, then inside run
   `harness/setup-peer.sh` (rebind interface 0.0.0.0:43101, advertise
   `atm-hermes-testbed.local` — cert CN/SAN regenerated by setup-mtls.sh —
   trust-add host fp) — or do it by hand; the script is the source of truth.
3. Register mirrored fixture rosters on BOTH sides (team `fx-at3`, members
   `fx-at3-alpha` container-side / `fx-at3-beta` host-side; `fx-` prefix
   mandatory, never reuse real fleet names).
4. Send both directions; collect + report.
5. Teardown: **roster removal is identity-scoped** — `atm teams
   remove-member <team> <member>` rejects cross-team callers ("caller team
   X does not match remove-member target team Y"). Remove each fixture under
   ITS OWN identity (`ATM_IDENTITY=fx-at3-beta ATM_TEAM=fx-at3 atm teams
   remove-member fx-at3 fx-at3-beta`). Verified live on host atm 1.4.13
   (fx-at3-beta removal, 2026-09-07).

**CRITICAL PITFALL — trust pins are bootstrap-cached.**
`MtlsPeerStreamAdapter::from_peer_config` builds the pinned verifier ONCE at
daemon startup (verified at source, no reload path). If you add a trust entry
to an already-running daemon, it does NOT take effect until that daemon
restarts. Symptom: TLS handshake completes, connection reset immediately
after, "could not connect to direct peer". Fix: restart the daemon — the host
daemon restart belongs to fenix@atm-dev via the `/daemon-switch` skill (Rand
2026-08-31); fenix must restore afterwards if ATM issues arise.

## Teardown / restore

```sh
docker stop hermes-testbed && docker rm hermes-testbed
# host side after a peer run:
atm peer trust remove localhost
atm teams delete fx-at3   # fixture roster cleanup (members first if needed)
```

Images and results stay; only container state is disposable.

## Known-flake workarounds

- `atm read` selector/filter is unreliable → use `atm list`/`atm peek`/`atm search`
  or direct sqlite on `~/.atm/db/mail.db` (table `mail_messages`, cols:
  `team, agent, message_id, from_agent, message_at, message_text`).
- `atm peer certificate show` prints `null` with exit 0 when absent —
  idempotency checks must test the VALUE, not the exit code.
