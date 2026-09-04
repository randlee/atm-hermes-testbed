# Colima VM-internal plan — container-side checklist (C1–C5)

Pre-staged by loki 2026-09-04 per fenix@atm-dev; executes only after Rand's
Q1–Q3 rulings + the localhost-trust-entry ruling (team-lead asked Rand).
Replaces the retired localhost-pin AT3 wiring. Scope: re-run infra matrix
A–D+D7 + AT0–AT8 against the current candidate (1.4.13 content).

## Verified preconditions (2026-09-04)

- colima: STOPPED (`colima status` → not running). First step is `colima start`.
- Current resources 2 CPU / 2 GiB — Q2 asks for 4/4 (needs `colima stop` →
  `colima start --cpu 4 --memory 4` or config edit; VM-internal tiers incl.
  the prompt suite are CPU-bound, 4/4 recommended).
- Tags `prerelease/v1.4.12` (4f1202bf2) and `prerelease/v1.4.13` (7e4302d98)
  exist on origin. Tarballs: NOT GitHub Releases by design — prerelease-archive
  stores Actions artifacts (fenix correction 2026-09-04).
- **Q3 CLOSED (fenix ruling 2026-09-04, verified by loki against git):**
  - TARBALL = tag run: `gh run download 33844823008 -n aarch64-unknown-linux-gnu`
    (+ checksums artifact), prerelease-archive at prerelease/v1.4.13.
  - WHEELS = develop-head run: `gh run download 33861954676 -n
    hermes-atm-wheels-linux-aarch64` (CI on develop, headSha f39c2236477a...,
    conclusion success).
  - Provenance: 7e4302d98 IS an ancestor of develop, and
    `git diff 7e4302d98 origin/develop -- crates Cargo.lock Cargo.toml` is
    EMPTY — every post-tag merge is docs/triage/evidence/scripts only, so the
    develop-head wheels are byte-identical in crate content to the tag.
    (loki verified both checks 2026-09-04; the earlier ceda87608 wheels were
    correctly rejected — not a tag descendant, 16-file crates diff incl.
    atm-storage* and hermes-atm pyproject version.)
  - The Dockerfile consumes prebuilt wheels (COPY + uv pip install --no-index,
    no in-container build) — WHEELS_DIR from the run above satisfies it.
- Testbed repo main @ 039f25a: build.sh requires WHEELS_DIR (wheelhouse
  retired — host is hermes-atm 1.4.11, never revert).
- Held host state (mine): the localhost:43102 fixture pin was CLOSED BY
  REPLACEMENT (fenix 2026-09-04 — replaced with host's own cert on 43101 per
  Rand's ruling; see C4). Still held, awaits Rand: roster row fx-at3/fx-at3-beta
  (added 2026-08-31 ~21:35Z, untouched since).

## C1 — no host hermes agent talks to the container

- [ ] Verify no host roster row points at a container pane (grep
  recipient_pane_id/metadata for testbed refs) — expected already true.
- [ ] Verify host `~/.hermes` is NOT mounted by run.sh (grep mounts) — true
  by construction; re-verify as the gate.
- Owner: loki. Dependency: none.

## C2 — container hermes self-contained (own .hermes root + VM daemon)

- [ ] Container keeps HERMES_HOME=/opt/data/.hermes, own /root/.atm daemon —
  existing wall (run.sh); re-verify post-rebuild.
- [ ] Install the candidate hermes-atm wheel INSIDE the VM (from WHEELS_DIR
  artifact), never the wheelhouse.
- [ ] Env allowlist only (ANTHROPIC_API_KEY [+ workspace id] for the prompt
  suite); never host .env.
- Owner: loki. Dependency: Q3 artifacts.

## C3 — peer entry properly named, never localhost

- [ ] Container cert SAN includes DNS:hermes-testbed.local (setup-mtls.sh
  already generates it) — container advertises `hermes-testbed.local`.
- [ ] Host trust entry: `hermes-testbed.local` + container fp + port 43102
  (published), dial via hosts-file mapping, NOT localhost (Q1 may rename the
  authority — fenix recommended rand-m5.local:43102; adjust to ruling).
- [ ] update-member/run.sh --peer uses the named entry everywhere; grep for
  `localhost` pins before the AT3 leg as a hard gate.
- Owner: loki (container side) + fenix (host entry, his daemon). Dependency:
  Q1 ruling.

## C4 — remove host localhost trust entry + fx-at3 cleanup

STATUS CHANGED (fenix 2026-09-04): my item (1) — the localhost:43102 fixture
pin — is CLOSED BY REPLACEMENT. Rand ruled localhost on rand-m5 should carry
a trust key; fenix replaced my container pin with the host daemon's OWN
certificate on 43101 (fp BFCA33B6..., = the rand-m5.local pin) and did a
managed daemon restart (host daemon now 1.4.13 from develop, pid 13296).
- [x] localhost fixture pin gone (replaced — verified read-only 2026-09-04)
- [ ] Delete roster row fx-at3/fx-at3-beta — STILL HELD, awaits Rand's ruling
- [ ] Verify host `.localhost` self-sends behave under the new localhost key
      (loki's self-send nudge test) — do NOT dial container through localhost:
      with the host's own cert pinned there, container-bound sends must use
      the named hermes-testbed.local entry (C3), never localhost.
- Owner: loki executes the roster deletion on ruling; fenix owns host daemon.
  NOTE: trust pins bake at daemon bootstrap (MtlsPeerStreamAdapter::
  from_peer_config, no reload path) — fenix's managed restart already covered
  it for his replacement; any future pin change needs the same.

## C5 — fenix sequences machine time

- [ ] fenix owns the rand-m5 time window (~half day: colima up, tiers
  sequential, nothing overlapping arch-ctm); I report start/finish per the
  benchmark-window rule.
- Owner: fenix.

## Execution order once ruled

1. Q3 artifacts land (tarball + wheels for the candidate)
2. `colima stop` → `colima start --cpu 4 --memory 4` (Q2) → rebuild image:
   `TESTBED_PLATFORM=arm64 ATM_TARBALL=<...> WHEELS_DIR=<...> ./build.sh all`
3. C1/C2 verify → infra matrix A–D+D7 fresh container
4. Prompt suite AT0–AT2/AT4–AT8 (VM-internal, no host dependency)
5. C4 (on ruling) + C3 wiring → AT3 cross-host both directions → suite/v1 cut
6. Evidence → results-run-v<ver> + atm-core reports/colima/ addendum
   (AS-COLIMA-* rows, cites suite/v1)
