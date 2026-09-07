# ATM test report template

The requester is the report address named in the sentence that started you (`send the report to
<agent@team.host>`), copied verbatim with its `.host` suffix — never the sender of the nudge or of the
sentence. Every ATM test skill sends three kinds of line to that address, all plain text, all with
`atm send <requester> --stdin` (native: `atm_send`):

1. **Start line, first action of the skill, before any step** — nobody should wonder whether the
   agent is running: `ATM TEST START skill: <skill-name> fixture: <fixture> agent: <agent@team>`.
2. **Wait line, once every 60 s while a step is waiting on a deadline** (a partner's message, an
   ack): `ATM TEST WAIT skill: <skill-name> step <n> <elapsed>s/<deadline>s`. Nothing else is sent
   while waiting.
3. **Exactly one report message** in this shape: the block below filled in,
as plain text, nothing before it and nothing after it (no markdown headings, no summary, no
prose). Same shape on every fixture; the `fixture` line is the only fixture-specific content.

```
ATM TEST REPORT
skill: <skill-name>
fixture: <$ATM_TEST_FIXTURE or hostname>
agent: <agent@team>  tools: <cli | native | native+cli>
atm: client <x.y.z> daemon <x.y.z>
result: PASS | FAIL   (<passed>/<total> steps)
steps:
  1 PASS <step name> — <observable: message id / count / exit code / error code / seconds>
  2 FAIL <step name> — <observable>
  ...
elapsed: <seconds>s
```

`result` is PASS only when every step line is PASS; one FAIL makes the result FAIL (<passed>/<total>
counts every step, step 0 included). SKIP is allowed only for a step that cannot run because an
earlier step's output it needs does not exist (no partner message → nothing to peek, read, ack).
A FAIL in one step never stops the run: keep going, finish every remaining step, then report once.
Every step line is PASS, FAIL or SKIP; never PENDING — a step that is waiting on a deadline is not
finished, and the report is sent only after the last deadline has passed or been met.
On any FAIL, before sending the report:
1. run `../atm-troubleshoot/SKILL.md` for that step and get the cause;
2. if the fix is within your reach on the fixture (roster entry, your own gateway or tool session,
   a stale receiver registration, an environment variable, a wrong command form), apply it;
3. re-run the failed step once and record the retest;
4. the step line becomes `FAIL <step> — cause: <component/evidence>; fix: <what you did | none possible>; retest: PASS|FAIL`.
A FAIL without a cause line is not a finished report. Never change ATM code or binaries; a cause
in those goes to the requester as-is.

Rules: an `atm` command runs in your terminal/shell tool where `ATM_IDENTITY`/`ATM_TEAM` are set — never as
a subprocess inside a code-execution tool (no identity there: every call fails and a poll loop runs to its
deadline for nothing). Poll by calling the tool (native `atm_list()` or the CLI) once per iteration and
sleep 10 s in the terminal between calls; never write a loop that shells out to `atm`. The `atm:` line
comes from `atm doctor --json`, never guessed. Never include message bodies, addresses beyond `agent@team`, chat ids, tokens,
capability values or raw config. A FAIL line carries the error code or count, not narrative.
