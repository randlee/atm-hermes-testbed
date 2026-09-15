# ATM test report template

The requester is the report address named in the sentence that started you (`send the report to
<agent@team.host>`), copied verbatim with its `.host` suffix — never the sender of the nudge or of the
sentence. Every ATM test skill sends three kinds of line to that address, all plain text, all with
`atm send <requester> --stdin --json` (native: `atm_send`):

1. **Start line, first action of the skill, before any step** — nobody should wonder whether the
   agent is running: `ATM TEST START skill: <skill-name> fixture: <fixture> agent: <agent@team>`.
   CLI: send it with `atm send <requester> --stdin --json` and record the returned JSON
   `message_id`; never infer an id from the human-readable command output.
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
  2 FAIL <step name> — command: <exact command>; exit: <code>; stderr: <first line verbatim | <empty>>; cause: <quoted stderr>; fix: <what you did | none possible>; retest: PASS|FAIL
  ...
elapsed: <seconds>s
```

Before sending the report, derive `result:` and `(<passed>/<total> steps)` from the finished step
lines; never type either independently. `total` is the number of non-SKIP step lines and `passed`
is the number of those lines marked PASS. The result is PASS exactly when every non-SKIP step is
PASS; any FAIL makes it FAIL. SKIP is allowed only for a step that cannot run because an
earlier step's output it needs does not exist (no partner message → nothing to peek, read, ack).
A FAIL in one step never stops the run: keep going, finish every remaining step, then report once.
Every step line is PASS, FAIL or SKIP; never PENDING — a step that is waiting on a deadline is not
finished, and the report is sent only after the last deadline has passed or been met.
On any FAIL, before sending the report:
1. run `../atm-troubleshoot/SKILL.md` for that step and get the cause;
2. if the fix is within your reach on the fixture (roster entry, your own gateway or tool session,
   a stale receiver registration, an environment variable, a wrong command form), apply it;
3. re-run the failed step once and record the retest;
4. retain the failed command, its exit code, and its stderr (the first stderr line is enough), then
   make the step line `FAIL <step> — command: <exact command>; exit: <code>; stderr: <first line verbatim | <empty>>; cause: <that quoted stderr>; fix: <what you did | none possible>; retest: PASS|FAIL`.
   A named canned cause may be added only when that same quoted stderr contains the named error
   text; otherwise the cause is the quoted stderr itself. A FAIL without these command, exit, stderr,
   and cause fields is not a finished report. Never change ATM code or binaries; a cause in those
   goes to the requester as-is.

Rules: an `atm` command runs in your terminal/shell tool where `ATM_IDENTITY`/`ATM_TEAM` are set — never as
a subprocess inside a code-execution tool (no identity there: every call fails and a poll loop runs to its
deadline for nothing). Poll by calling the tool (native `atm_list()` or the CLI) once per iteration and
sleep 10 s in the terminal between calls; never write a loop that shells out to `atm`, never a heredoc
parser (`python3 <<EOF` replaces the piped JSON as stdin: run 4 on 2026-09-08 timed out two steps that
way while the replies sat unread). Every wait step names one fixed `atm list ... --from ... --contains ...`
command; its `count` is the observable, nothing is parsed. For every CLI observable that is an id
or count, use that command's `--json` response and its named `message_id` or `count` field; never
tokenize or parse human CLI text. The `atm:` line
comes from `atm doctor --json`, never guessed. Never include message bodies, addresses beyond `agent@team`, chat ids, tokens,
capability values or raw config.
