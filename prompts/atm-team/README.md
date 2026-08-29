# atm-team behavioral prompts (AT0–AT8)

Nine `prompts/atm-team/*.md` prompts, one per atm-core behavior contract,
under the same `prompt-report-1` schema family as `prompts/hermes/`. Each
prompt is executed by a real `claude-code` agent inside the fixture and
writes `/opt/testbed/results/prompt-AT<N>.json`. See `../CATALOG.md` for the
test-type table and report contract, and each prompt's own frontmatter for
its `requires`/`timeout_s` values.

## Fixture prerequisites

- **claude-code binary in the image.** Run
  `/opt/testbed/harness/install-claude-code.sh` inside the container (or
  build it into the image) before any AT0–AT8 prompt runs; it is idempotent
  and no-ops if `claude` is already on PATH.
- **`ANTHROPIC_API_KEY` in `env/allowlist.env`.** All nine prompts declare
  `requires: [ANTHROPIC_API_KEY]`; `run.sh`'s `--env-file` must carry it
  through to the container process env.
- **AT4/AT8 harness handshake scripts**, both under
  `/opt/testbed/harness/` (`testbed/harness/` in this repo):
  - `restart-daemon.sh` — used by AT4. Kills and relaunches `atm-daemon`
    detached, clears the stale owner lock, and internally wait-gates (up to
    60s) on `/root/.atm/daemon/local-http.json` reappearing before exiting.
  - `freeze-daemon.sh <seconds>` — used by AT8. SIGSTOPs the running
    `atm-daemon` process for the given duration (default 4s; AT8's assumed
    client request budget is 3.25s) then SIGCONTs it, to induce a
    deterministic client-side send timeout without losing the write.
  Both scripts already exist in this tree. If either is absent at run time
  (e.g. an older fixture image), the corresponding prompt records status
  "skip" with reason "harness script missing" rather than improvising a
  manual restart/freeze.
- **`--peer` mode for AT3.** AT3 requires the fixture to be launched with a
  trusted Mac peer already configured (`atm peer trust list --json`
  non-empty). Without it, AT3 records status "skip" with reason "no trusted
  peer configured in this fixture run (--peer mode not active)".
- **`atm >= 1.4.5` and `herdr` on PATH for AT7.** AT7 gates on both; missing
  either produces a "skip" with the corresponding reason ("atm < 1.4.5:
  herdr delivery backend absent" / "herdr not on PATH").

## Fixture identity naming (mandatory)

Per `../CATALOG.md`'s fixture identity naming rule, every identity/team used
by these nine prompts is prefixed `fx-` and scoped by test: team `fx-at<N>`,
members `fx-at<N>-<role>` (e.g. `fx-at0-alpha`, `fx-at0-beta`). This is
mandatory for all AT0–AT8 identities/teams and any future addition to this
suite — never reuse a real atm-dev/hermes roster name inside the fixture.
