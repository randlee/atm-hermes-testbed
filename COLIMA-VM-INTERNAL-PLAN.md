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
  exist on origin. **NO GitHub release assets for either** — Q3 gap is real:
  the linux x86_64/aarch64 tarballs + wheels CI produces none today. Options:
  (a) re-dispatch the prerelease-archive workflow at the tag (team-lead's job,
  PR #1096 machinery exists), (b) build the aarch64 tarball from tag source
  via the repo's release path, (c) host cargo build — needs Rand's Q3 ruling.
- Testbed repo main @ 039f25a: build.sh requires WHEELS_DIR (wheelhouse
  retired — host is hermes-atm 1.4.11, never revert).
- Held host state (mine, awaiting ruling, both from 2026-08-31 ~21:35Z):
  host trust entry `localhost` fp 4E7B3D2B... port 43102; roster row
  fx-at3/fx-at3-beta. fenix confirmed both untouched on his side.

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

- [ ] `atm peer trust revoke localhost` (the 4E7B... pin at 43102).
- [ ] Delete roster row fx-at3/fx-at3-beta.
- [ ] Verify host `.localhost` self-sends no longer shadow (send
  loki@hermes.localhost test).
- Owner: loki executes (my state), gated on Rand's ruling via team-lead.
  fenix holds until then. NOTE: rand-m5 daemon restart may be required
  (trust pins bake at daemon bootstrap — MtlsPeerStreamAdapter::from_peer_config,
  no reload path; restart = fenix via /daemon-switch per Rand's delegation).

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
