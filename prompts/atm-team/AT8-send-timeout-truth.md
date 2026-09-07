---
id: AT8-send-timeout-truth
agent: claude-code
model: haiku
requires: [ANTHROPIC_API_KEY]
timeout_s: 180
report: /opt/testbed/results/prompt-AT8.json
since: suite/v1
---

You are the atm-team send-timeout-truth agent inside the hermes-docker-testbed
fixture. Your job is to prove the RETRY DECISION RULE for a client-side send
timeout, not any single fixed outcome. The rule (the real 2026-08-29 incident
contract): after a send returns a client timeout, consult
`~/.atm/logs/atm.log.jsonl` for a send entry with the same request_id —
`"action":"send" ... "outcome":"sent"` — and let that decide:
  (a) entry ABSENT  -> the write never landed, so retry ONCE; expect the
      receiver to end up with exactly one copy;
  (b) entry PRESENT -> the write landed despite the timeout, so do NOT retry;
      expect the receiver to end up with exactly one copy.
Either branch PASSES if the receiver ends up with exactly one copy AND your
retry choice matches what the log shows. Never retry blindly (a blind retry
on branch (b) duplicates the message). Then emit a structured report. Do each
step in order; if a step fails, record it as failed and continue.

Timing facts about this fixture (fenix@atm-dev): a full SIGSTOP BEFORE the
daemon reads the request cannot persist anything — the write is genuinely
lost and the client timeout is truthful. That outcome is CORRECT on both
atm 1.4.3 and 1.4.6; #1095 does not change it (#1095 fixes the
stale-connection-to-restarted-daemon case, which is AT4's territory, not
AT8's). So AT8's result should be the SAME across 1.4.3 and 1.4.6; a
difference would be a finding, not an expected regression signal. The two
freeze timings below deliberately select the branch you get:
  - freeze before the send (no --after)  -> mostly branch (a)
  - freeze --after <calibrated ms> AFTER the send starts, so the daemon has
    accepted+persisted but its reply is delayed past the 3.25s client budget
    -> deterministically branch (b). The delay is CALIBRATED per run from
    your warm-up RTT (≈ half the measured accept latency, floor 300ms,
    ceiling 1500ms) because a fixed 300ms is a timing assumption that a slow
    (e.g. qemu-emulated) guest can violate — see the step-12 guard.

Empirical error shape (arch-ctm@atm-dev, observed on atm 1.4.3 with a full
4s SIGSTOP freeze; forward-ported from closed PR #2, additive note): the
client's budget abort surfaces as exit code 9 with EMPTY stdout and stderr
`HTTP client request exceeded its absolute request budget`. This is the
transport-level budget abort shape — it is NOT a WaitTimeout JSON error body
(`AtmErrorCode::WaitTimeout` / ATM_WAIT_TIMEOUT is the read-wait path, a
different surface). Record whatever shape you actually observe; do not
assume either one.

Context already true in this fixture: the ATM daemon is running; team
`fx-at8` with members `fx-at8-alpha` and `fx-at8-beta` is registered by the
harness before you start. The freeze is executed OUT OF BAND by the
coordinator (root `docker exec` of /opt/testbed/harness/freeze-daemon.sh —
you never invoke it and never use sudo; the client's absolute request budget
in this fixture is 3.25s). You coordinate via marker files under
/opt/testbed/results/markers/ (writable by you): `at8-armed` appears when the
hook is watching (contents: UTC ISO timestamp + `after_ms=<computed>` +
`source_rtt_ms=<validated>` when calibrated), `at8-done` appears after the
daemon is resumed, and `at8-rtt` is YOURS to write (step 2, HGC-023
calibration export). For Phase B the hook also
watches a TRIGGER file: touching it starts the `--after` delay on YOUR
timing. Your default identity is `fx-at8-alpha`.

Steps:

1. Marker-dir precondition: run `test -w /opt/testbed/results/markers`. If
   not present/writable, record status "skip" with reason "marker dir
   missing" for every remaining step and stop (still write the full report).
   Also record no-sudo acceptance evidence in `detail`: your uid (`id -u`,
   must be != 0) and that sudo is absent (`command -v sudo`, must be empty).
2. Warm-up + calibration: `ATM_IDENTITY=fx-at8-alpha ATM_TEAM=fx-at8 atm send
   fx-at8-beta "AT8-WARMUP" --team fx-at8`. Exit code 0 — confirms the daemon
   is healthy before inducing any freeze. ALSO measure this send's wall-clock
   RTT in milliseconds (e.g. wrap with date +%s%3N before/after, or
   `time`) and record it in `detail` as `warmup_rtt_ms`. Then EXPORT the
   calibration to the coordinator (HGC-023): the measured value must be a
   plain integer (milliseconds, 1..60000 — if your timing tool produced a
   non-integer, round it; if the send failed or the value is out of range,
   record step status "fail" with reason "rtt calibration invalid" and
   stop). Write it with EXACTLY this file contract — ASCII digits plus a
   trailing newline, nothing else:
   `printf '%s\n' "$warmup_rtt_ms" > /opt/testbed/results/markers/at8-rtt`
   The coordinator waits (bounded) for this marker, validates it
   (^[0-9]+$, 1..60000), and arms Phase B with `--after` =
   clamp((rtt+1)/2, 300, 1500) — your marker is the ONLY calibration
   input; the prompt never chooses or defaults the delay.

   --- Phase A: freeze BEFORE the send (expected branch (a), write lost) ---
3. Phase-A arm: poll until `/opt/testbed/results/markers/at8-armed` exists
   (the coordinator has launched the out-of-band freeze with no --after;
   bound 60s). Record the marker contents (UTC timestamp) in `detail`.
4. Phase-A timeout send: immediately run `ATM_IDENTITY=fx-at8-alpha atm send
   fx-at8-beta "AT8-PHASE-A" --team fx-at8 --json`. Capture the request id
   from the output (record it in `detail`; note if none is visible). Expect a
   non-zero exit code (observed on atm 1.4.3: exit 9, stdout EMPTY, stderr
   `HTTP client request exceeded its absolute request budget`). Record the
   exit code and exact stderr text.
5. Phase-A freeze completed: poll until `/opt/testbed/results/markers/at8-done`
   exists (bound 30s). Wait-gate semantics — not pass/fail on its own.
6. Phase-A log truth check: search `~/.atm/logs/atm.log.jsonl` (via `atm log
   filter` or `atm log tail`, per docs/user-documents/doctor-and-log.md) for
   a send entry correlated with the step-4 request — prefer matching by the
   captured request id, else by message text `AT8-PHASE-A`. Record in
   `detail` whether you found `"action":"send"..."outcome":"sent"` (PRESENT)
   or not (ABSENT), and how you correlated. For phase A expect ABSENT.
7. Phase-A retry decision: apply the rule. If step 6 = ABSENT, retry ONCE:
   `ATM_IDENTITY=fx-at8-alpha atm send fx-at8-beta "AT8-PHASE-A" --team
   fx-at8 --json` (the daemon is thawed now). Record that you retried and its
   exit code. If step 6 = PRESENT (unexpected for phase A), do NOT retry and
   record why.
8. Phase-A delivery count: `ATM_IDENTITY=fx-at8-beta ATM_TEAM=fx-at8 atm list
   fx-at8-beta --all --json` — count occurrences of `AT8-PHASE-A` in rows[].
   PASS this step only if the count is exactly 1 AND your step-7 choice
   matched the step-6 log outcome. Record the count.

   --- Phase B: freeze AFTER the send starts (expected branch (b), landed) ---
9. Phase-B arm: poll until `/opt/testbed/results/markers/at8-armed` exists
   AGAIN (the coordinator read your `at8-rtt` marker, validated it, computed
   `after_ms=clamp((rtt+1)/2,300,1500)`, and re-launched the hook out of
   band with `--after <after_ms> --source-rtt <your rtt> --trigger
   /opt/testbed/results/markers/at8-trigger`; the hook clears both markers
   when it re-arms, so wait for the FRESH at8-armed — bound 60s). Record
   the marker contents in `detail`: the UTC timestamp, `after_ms=<value>`
   AND `source_rtt_ms=<value>` (your step-2 RTT as validated by the
   coordinator). You never choose or default the delay — if at8-armed lacks
   after_ms/source_rtt_ms, record step status "fail" with reason
   "calibrated arm marker incomplete".
10. Phase-B timeout send: `touch /opt/testbed/results/markers/at8-trigger`
    && IMMEDIATELY (same shell line, &&-chained) run
    `ATM_IDENTITY=fx-at8-alpha atm send fx-at8-beta "AT8-PHASE-B" --team
    fx-at8 --json`. The hook's --after delay starts at YOUR touch, so the
    daemon accepts+persists your send, then freezes before replying — the
    reply lands past the 3.25s budget. Capture the request id. Expect a
    non-zero exit code (client budget abort). Record exit code and stderr.
11. Phase-B freeze completed: poll until `/opt/testbed/results/markers/at8-done`
    exists (bound 30s). Wait-gate semantics — not pass/fail on its own.
12. Phase-B log truth check: same as step 6 but for `AT8-PHASE-B`. For phase B
    expect PRESENT (the daemon accepted+persisted before the reply timed out).
    Record PRESENT/ABSENT and the correlation method. CALIBRATION GUARD
    (fenix tweak): confirm from the log entry's timestamp that the request
    was persisted BEFORE the SIGSTOP time (the at8-armed timestamp plus the
    after_ms delay from step 9). If the freeze preceded the persist, this
    row is FAIL with reason "freeze preceded persist (delay too short)" —
    never rerun-until-green.
13. Phase-B retry decision: apply the rule. If step 12 = PRESENT, do NOT
    retry; record that you did not and why. If step 12 = ABSENT (unexpected
    for phase B), retry once and record it.
14. Phase-B delivery count: `atm list fx-at8-beta --all --json` as
    fx-at8-beta — count occurrences of `AT8-PHASE-B`. PASS only if count == 1
    AND your step-13 choice matched the step-12 log outcome.

REPORT CONTRACT — after step 14 (or immediately after step 1 if skipped),
write the file /opt/testbed/results/prompt-AT8.json with exactly this shape
(real values):

{
  "schema": "prompt-report-1",
  "test_id": "AT8-send-timeout-truth",
  "agent": "claude-code",
  "steps": [
    {"name": "harness-hook-precondition", "status": "pass|fail|skip", "detail": ""},
    {"name": "warm-up-send", "status": "", "detail": ""},
    {"name": "phase-a-freeze-before-send", "status": "", "detail": ""},
    {"name": "phase-a-timeout-send-observed", "status": "", "detail": ""},
    {"name": "phase-a-freeze-completed", "status": "", "detail": ""},
    {"name": "phase-a-log-truth-check", "status": "", "detail": ""},
    {"name": "phase-a-retry-decision", "status": "", "detail": ""},
    {"name": "phase-a-exactly-one-copy", "status": "", "detail": ""},
    {"name": "phase-b-freeze-after-send-start", "status": "", "detail": ""},
    {"name": "phase-b-timeout-send-observed", "status": "", "detail": ""},
    {"name": "phase-b-freeze-completed", "status": "", "detail": ""},
    {"name": "phase-b-log-truth-check", "status": "", "detail": ""},
    {"name": "phase-b-no-retry-decision", "status": "", "detail": ""},
    {"name": "phase-b-exactly-one-copy", "status": "", "detail": ""}
  ],
  "verdict": "pass if no step failed, else fail",
  "atm_versions": {"atm": "", "hermes_atm": "", "atm_graft": ""},
  "started_at": "", "finished_at": ""
}

Then print the single line: SMOKE-REPORT-WRITTEN /opt/testbed/results/prompt-AT8.json
