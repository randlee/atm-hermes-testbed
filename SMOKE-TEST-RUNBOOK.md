# Runbook — one integration run of ATM `<V>` against the Hermes fork

Every command below is exact. Nothing is decided, edited or babysat during a run. Total: ~30 minutes
including the image build (10–20 minutes, once per input change), ~10 minutes after. Plan and rules:
atm-core `docs/plans/phase-aq/sprint-HERMES-SKILL-TESTS-R1.md`. If a line here is wrong, the run stops,
the line gets fixed in this file (or the script it calls) and committed, and the run restarts. That is
the only "ceremony": the next run must not hit the same thing twice.

## Inputs (set once per run)

```sh
V=1.5.7                                   # ATM version under test; patch-bumped on develop and tagged prerelease/v$V
SHA=$(git -C ~/Documents/github/atm-core rev-parse "prerelease/v$V^{commit}")   # the tagged COMMIT (the tag is an annotated object; without ^{commit} the CI lookup finds nothing)
M=$(hostname -s)                          # this Mac, as the container sees it (peer host name)
O=fenix@atm-dev.$M                        # oversight agent: where every report goes (the .host suffix is what crosses hosts)
F=atm-hermes-testbed.local                # fixture name = the container's peer host name
R="stub-alpha@testbed stub-beta@testbed tester@testbed hermes@testbed"   # the fixture's roster (bringup.sh creates exactly this)
# TESTBED_PLATFORM is not needed: build.sh and run.sh default to the host architecture.
# Per-host secrets: env/allowlist.env (must carry ANTHROPIC_API_KEY) and env/peer-key live only in the
# checkout (gitignored, never committed). A fresh clone or worktree needs them copied from the existing checkout.
```

Where each component comes from (no local builds, ever):

| component | source | pin |
| --- | --- | --- |
| ATM daemon + CLI | `prerelease-archive.yml` run for tag `prerelease/v$V`, artifact `aarch64-unknown-linux-gnu` | the tag |
| hermes_atm + atm_graft wheels | `ci.yml` run for commit `$SHA`, artifact `hermes-atm-wheels-linux-aarch64` | the tag's commit |
| herdr | GitHub release `herdrdev/herdr` `v0.8.2`, sha256-checked in `build.sh` (same version as the host) | `build.sh` |
| hermes-agent | fork `randlee/hermes-agent` `origin/main` head at build time (loki): `build.sh base` fetches origin/main, resets the detached worktree `hermes-agent-randlee-worktrees/testbed-build` to that SHA, fails closed if `inject_internal_message` is missing from `gateway/run.py`, builds `loki/hermes-testbed:base`. The citable pin is the SHA the build prints as `base context: <sha> <subject>` (in-image stamp `/opt/hermes/.hermes_build_sha` pending loki's HERMES_GIT_SHA PR) | `./build.sh base` |

## 0. One-time on a new Mac (needs sudo; Rand)

```sh
echo "127.0.0.1 atm-hermes-testbed.local" | sudo tee -a /etc/hosts
```

`run.sh` checks for this line and refuses to continue without it. Everything else is scripted.

## 1. Clean

```sh
cd ~/Documents/github/atm-hermes-testbed
./teardown.sh
git fetch origin && git reset --hard origin/main && git clean -fdx -e env/
```

## 2. Fetch the ATM artifacts

```sh
PRE=$(gh run list -R randlee/atm-core --workflow prerelease-archive.yml --branch prerelease/v$V --json databaseId --jq '.[0].databaseId')
gh run download $PRE -R randlee/atm-core -n aarch64-unknown-linux-gnu -D /tmp/atm-$V
CI=$(gh run list -R randlee/atm-core --workflow ci.yml --json databaseId,headSha --jq ".[]|select(.headSha==\"$SHA\")|.databaseId" | head -1)
gh run download $CI -R randlee/atm-core -n hermes-atm-wheels-linux-aarch64 -D /tmp/wheels-$V
```

## 3. Build the image

```sh
ATM_TARBALL=/tmp/atm-$V/atm_${V}_aarch64-unknown-linux-gnu.tar.gz WHEELS_DIR=/tmp/wheels-$V ./build.sh all
```

`build.sh base` rebuilds only when the fork changed; `testbed` is the thin layer with ATM, herdr, hmux,
the harness scripts, the test config (`testbed/atm.toml` → `/opt/testbed/.atm.toml`) and the five skills,
placed three times so every kind of agent finds them without copying anything at run time:

| agent | reads skills from | put there by |
| --- | --- | --- |
| Hermes (profile `default`, `HERMES_HOME=/opt/data`) | `/opt/data/skills/atm-*` | boot hook syncs `/opt/hermes/skills` |
| Claude Code tester (cwd `/opt/testbed`) | `/opt/testbed/.claude/skills/atm-*` | Dockerfile COPY |
| Codex tester (cwd `/opt/testbed`) | `/opt/testbed/.codex/skills/atm-*` + `AGENTS.md` | Dockerfile symlinks |

## 4. Start: one command brings up both teams as cross-host peers

```sh
./run.sh --gateway
```

What it does, in order (all rerunnable; `run.sh` prints one line per step):

1. `docker run` in peer mode: host port 43102 → container 43101, sshd on 2222, `--add-host $M:host-gateway`.
2. `setup-mtls.sh`: the container's peer identity (baked at image build; its fingerprint changes per build).
3. `setup-peer.sh`: the container trusts `$M` (add, or replace if present).
4. The host trusts `$F:43102` (add or replace), then **restarts the host daemon** via `launchctl kickstart -k`.
   The trust store is snapshotted at daemon start (`crates/peer-tls`): without the restart every cross-host
   send fails with "peer is not an enabled exact mTLS authority" or a bare "connection error".
5. `bringup.sh` inside the container: ATM daemon (started *after* trust, same snapshot rule) → perms and the
   `/opt/data/.atm` symlink so the hermes user reaches the root-run daemon → `herdr server` with a
   world-writable socket → roster `$R` (`tester` on the herdr backend) → `hermes_atm install` for profile
   `default` as user hermes from `/opt/data` + `hermes plugins enable hermes-atm-native-tools` + receiver dir
   `/opt/testbed/.atm` owned by hermes → gateway restart (s6) → `herdr integration install claude` for the
   hermes user → `hmux` from `/opt/testbed` (stub-alpha, stub-beta, tester panes; leftover panes are closed
   first because hmux is not idempotent) → `herdr agent rename <pane> tester` (Claude Code registers nameless;
   ATM's herdr backend matches the roster name).

Hermes agents launch from their profile: user `hermes`, `HERMES_HOME=HOME=/opt/data`, cwd `/opt/data`.
The gateway does; the headless CLI line in §5 does the same. Verify (30 seconds):

```sh
atm doctor --json | jq .summary
docker exec hermes-testbed atm doctor --json | jq .summary
docker exec hermes-testbed herdr agent list | jq '[.result.agents[]|{name,agent_status}]'     # tester idle
docker exec hermes-testbed pgrep -af "[h]ermes gateway run"                                  # gateway up as hermes
ATM_IDENTITY=fenix ATM_TEAM=atm-dev atm send tester@testbed.$F --requires-ack --stdin <<<"ack this message"
```

The last line proves host → container; the tester's ack in `atm list --pending-ack` proves container → host.

## 5. The run-book (seven sentences, seven reports)

`T` = the Claude Code tester inside the fixture (`tester@testbed`, driven by ATM nudges through herdr).
`H` = the Hermes agent inside the fixture (`hermes@testbed`). Until atm-core #1307 lands (the hermes-atm
receiver injects only into a Telegram adapter, and the fixture gateway has none), `H` is driven with the
headless CLI, as the hermes user from the profile dir (loki's proof recipe, rehearsed 2026-09-07: the
`/opt/hermes/bin/hermes` shim drops root → hermes; the model must be the full id):

```sh
h() { docker exec hermes-testbed sh -c "printf '%s\n' \"$1\" > /tmp/smoke-prompt.md; chmod 644 /tmp/smoke-prompt.md"
      docker exec -e ATM_IDENTITY=hermes -e ATM_TEAM=testbed hermes-testbed hermes chat --query-file /tmp/smoke-prompt.md \
        -m claude-haiku-4-5-20251001 --provider anthropic --yolo --max-turns 60 --in /opt/data; }
t() { ATM_IDENTITY=stub-alpha ATM_TEAM=testbed atm send tester@testbed.$F --requires-ack --stdin <<<"$1"; }
```

Send in this order; the two smoke sentences together, the two roundtrip sentences together; otherwise wait
for the report before the next sentence. Every sentence carries the fixture, the expected roster where the
skill needs one, and the report address with its `.host` suffix.

```
t "run the atm-setup-environment skill on fixture $F (expected roster: $R; peer host $M) and send the report to $O"
h "run the atm-setup-environment skill on fixture $F (expected roster: $R; peer host $M) and send the report to $O"
t "run the atm-smoke skill against hermes@testbed on fixture $F and send the report to $O"
h "run the atm-smoke skill against tester@testbed on fixture $F and send the report to $O"
t "run the atm-hermes-ready skill for hermes@testbed on fixture $F and send the report to $O"
t "run the atm-nudge-roundtrip skill as tester against hermes@testbed on fixture $F and send the report to $O"
h "run the atm-nudge-roundtrip skill as responder on fixture $F and send the report to $O"
```

The same seven sentences, same skills, run on this host against the local team (fixture `$M`, no peer)
by sending them to a local agent with `atm send <agent> --stdin`; the reports differ only in the `fixture`
line. Reports arrive in `$O`'s inbox: `atm list --unread --json`, `atm read --message-id <id>`.
Budget: one skill is 1–3 minutes; if a report has not arrived in 10 minutes, read the agent
(`docker exec hermes-testbed herdr pane read <pane> --source recent --lines 60`, or the `hermes chat`
output) — that is a finding for the post-mortem, not a reason to stop the other sentences.

## 6. Post-mortem

One file in atm-core, `docs/plans/phase-aq/reports/hermes-skill-tests-<V>-<fixture>.md`, from the seven
reports (template in the plan) plus every line of this runbook that had to change. Then `./teardown.sh`.

## When a line says FAIL

The container is not a black box: `docker exec hermes-testbed atm list --json` as any roster identity,
`docker exec hermes-testbed atm log snapshot`, `/tmp/atm-daemon.log`, `/tmp/herdr-server.log`,
`/tmp/hmux.log`, `/tmp/hermes-atm-install.log`, gateway logs under `/opt/data/logs` (redact every run of
8+ digits and every 32+ hex run before quoting). Root-cause with the `atm-troubleshoot` skill, fix the
environment, retest the step, record cause / fix / retest in the report. A FAIL inside a report is a
result, not an emergency; the run continues. Never edit ATM or the skills during a run; edit this file and
the scripts only between runs.
