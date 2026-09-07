# Runbook — one integration run of ATM `<V>` against the Hermes fork

Every command below is exact. Nothing is decided during a run. Total: ~10 minutes after the image
is built (cold image build: 10–20 minutes, once per input change). Plan and rules: atm-core
`docs/plans/phase-aq/sprint-HERMES-SKILL-TESTS-R1.md`.

## Inputs (set once per run)

```sh
V=1.5.7                                   # ATM version under test; patch-bumped on develop and tagged prerelease/v$V
SHA=$(git -C ~/Documents/github/atm-core rev-parse prerelease/v$V)   # the tagged commit
O=fenix@atm-dev                           # oversight agent (on this host)
F=atm-hermes-testbed.local                # fixture name = the container's peer host name
export TESTBED_PLATFORM=arm64             # Apple Silicon host: native arm64 image
```

Where each component comes from (no local builds, ever):

| component | source | pin |
| --- | --- | --- |
| ATM daemon + CLI | `prerelease-archive.yml` run for tag `prerelease/v$V`, artifact `aarch64-unknown-linux-gnu` | the tag |
| hermes_atm + atm_graft wheels | `ci.yml` run for commit `$SHA`, artifact `hermes-atm-wheels-linux-aarch64` | the tag's commit |
| herdr | GitHub release `herdrdev/herdr` `v0.8.2`, sha256-checked in `build.sh` (same version as the host) | `build.sh` |
| hermes-agent | fork `~/Documents/github/hermes-agent-randlee`, `origin/main`, built into `loki/hermes-testbed:base` | fork main (named-release + canonical patch pinning is the HERMES-PATCH-MODEL-R1 track) |

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

`build.sh base` rebuilds only when the fork changed; `testbed` is the thin layer with ATM, herdr,
the skills (`.claude/skills/atm-*` → `/opt/hermes/skills`), and the test config.

## 4. Start as a cross-host peer, with the Hermes team

```sh
./run.sh --gateway
```

Peer mode is the default: the container trusts this host, this host trusts `$F` on port 43102,
gateways start, graft receivers register. One-time prerequisite it checks: `/etc/hosts` has
`127.0.0.1 atm-hermes-testbed.local`. Verify both daemons:

```sh
atm doctor --json | jq .summary
docker exec hermes-testbed atm doctor --team hermes --json | jq '.summary, [.graft_receivers.receivers[]|{agent,last_seen}]'
```

## 5. The run-book (seven sentences, seven reports)

`T` = the ATM test agent (CLI only; today cipher on this host, addressing the fixture with
`--host $F`), `H` = one Hermes agent inside the container. Send with `atm send <to> --stdin`, one
sentence per message, in this order; the two smoke sentences together, the two roundtrip sentences
together; otherwise wait for the report before the next sentence.

```
to T:            run the atm-setup-environment skill on fixture $F (peer host $F) and send the report to $O
to H --host $F:  run the atm-setup-environment skill on fixture $F and send the report to $O
to T:            run the atm-smoke skill against H@hermes --host $F on fixture $F and send the report to $O
to H --host $F:  run the atm-smoke skill against T@atm-dev on fixture $F and send the report to $O
to T:            run the atm-hermes-ready skill for H@hermes --host $F on fixture $F and send the report to $O
to T:            run the atm-nudge-roundtrip skill as tester against H@hermes --host $F on fixture $F and send the report to $O
to H --host $F:  run the atm-nudge-roundtrip skill as responder on fixture $F and send the report to $O
```

Reports arrive in `$O`'s inbox: `atm list --unread --json`, `atm read --message-id <id>`.

## 6. Post-mortem

One file in atm-core, `docs/plans/phase-aq/reports/hermes-skill-tests-<V>-<fixture>.md`, from the
seven reports (template in the plan). Then `./teardown.sh`.

## When a line says FAIL

The container is not a black box: `docker exec hermes-testbed sqlite3 -readonly /root/.atm/db/mail.db …`
(query in the `atm-troubleshoot` skill), `docker exec hermes-testbed atm log snapshot`, gateway logs
under `/opt/data/logs` (redact every run of 8+ digits). Fix environment, retest the step, record
cause / fix / retest. Never edit ATM, the skills, or this file during a run.
