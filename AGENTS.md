# AGENTS Instructions for atm-hermes-testbed

## ATM Integration Test Skills

The ATM/Hermes integration tests are skills. Any agent (Claude, Codex, Hermes) runs one when told
the sentence below and ends with one report in the shape of `.claude/skills/atm-smoke/REPORT.md`.
Same skill, same steps, same report on every fixture; only the report's `fixture` line changes.
A FAIL never stops a run; every FAIL is root-caused with `atm-troubleshoot`, fixed where the agent
can, retested, and reported with `cause / fix / retest`.

| skill | sentence |
| --- | --- |
| `.claude/skills/atm-setup-environment/SKILL.md` | run the atm-setup-environment skill on fixture `<F>` and send the report to `<O>` |
| `.claude/skills/atm-smoke/SKILL.md` | run the atm-smoke skill against `<partner>` on fixture `<F>` and send the report to `<O>` |
| `.claude/skills/atm-hermes-ready/SKILL.md` | run the atm-hermes-ready skill for `<H>` on fixture `<F>` and send the report to `<O>` |
| `.claude/skills/atm-nudge-roundtrip/SKILL.md` | run the atm-nudge-roundtrip skill as tester against `<H>` / as responder on fixture `<F>` and send the report to `<O>` |
| `.claude/skills/atm-troubleshoot/SKILL.md` | run the atm-troubleshoot skill for `<skill>` step `<n>` on `<agent>` and send the cause to `<O>` |

The same directories are linked from `.codex/skills/`. Inside the image they are copied to
`/opt/hermes/skills/` and synced into `$HERMES_HOME/skills/` at boot. Plan:
atm-core `docs/plans/phase-aq/sprint-HERMES-SKILL-TESTS-R1.md`.
