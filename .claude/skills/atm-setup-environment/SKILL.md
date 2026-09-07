---
name: atm-setup-environment
description: Verify the ATM daemon, roster and doctor are ready before any integration test. Run it first on every fixture (local host or the colima testbed); it makes every expected team member exist in the roster and requires `atm doctor` to pass. Produces the standard ATM test report.
---

# atm-setup-environment

One sentence triggers it: "run the atm-setup-environment skill and send the report to <agent@team.host>".
The test is identical on every fixture. Only the report's `fixture` line differs.

## Inputs

- `ATM_IDENTITY` / `ATM_TEAM`: your own identity (must already be set).
- Expected roster: only a list the request introduces with the words "expected roster:". The
  report address is an address, never a roster entry. If no expected roster is given, the roster is
  whatever `atm teams` already holds and step 2 is a no-op. Never create a team, and never touch a
  team you are not a member of.
- Fixture name: `$ATM_TEST_FIXTURE` if set, otherwise `hostname`.

## Steps

Record PASS or FAIL for every step with the observable that decided it.

1. **Daemon answers.** `atm doctor --json` returns exit 0 within 10 s.
   Observable: `.summary.status`, `.client_context.version`, `.daemon_context.version`.
   FAIL if the command errors, times out, or the two versions differ.
2. **Roster complete.** For every team named in the expected roster, `atm members --team <team>`
   lists every expected member. Add each missing one with
   `atm teams add-member <team> <member> --agent-type <type>` (types: `lead`, `worker`,
   `qa`, `general-purpose`) and re-list. Observable: members added, members still missing.
   FAIL if any expected member is still missing after the add.
3. **Doctor passes.** `atm doctor --json`: `.summary.error_count` must be 0.
   List every warning `code` once with its count. `ATM_ROSTER_NO_LEAD` on teams that are not in the
   expected roster is acceptable; any warning on an expected team is FAIL.
4. **Self round trip** (the fastest test; every agent runs it first). Send one line to yourself,
   read it by id, confirm it left the unread list.
   - native: `atm_send(to=<you>, body)`, then `atm_read(message_id=<id>)`, then `atm_list()`.
   - CLI: `atm send <you> --host localhost --stdin <<'EOF' … EOF` (a bare same-team self-send is
     rejected by design; the host-qualified form is the self-send), then
     `atm read --message-id <id> --json`, then `atm list --unread --json`.
   Observable: message id; `count` 1 and `mutation_applied` true; id absent from unread afterwards.
   If the send fails with `no enabled trusted peer matches 'localhost'` or a peer-trust/mTLS-authority
   error, the fixture's bring-up did not register the localhost trust entry before the daemon started
   (the trust store is snapshotted at daemon start, so adding it now changes nothing until the daemon
   restarts, which is not yours to do). Do not add, replace or edit trust entries; do not try other
   ports. Record FAIL — cause: `localhost trust entry missing at daemon start (bring-up)`; fix: none
   possible; and continue with step 5.

5. **Cross-host peer (when the fixture has one).** If the request names a peer host (the testbed
   always does: host and container are peers from the start), `atm peer trust list --json` shows that
   host `enabled`, and `atm send <requester> --host <peer-host> --stdin` with one line returns a
   message id. Observable: enabled yes/no, message id. Missing trust is an environment fix
   (`atm peer trust add --host <peer-host> --fingerprint <its fingerprint> --https-port <port> --yes`,
   fingerprint from that host's `atm peer certificate show --json`; never print fingerprints), then
   retest. SKIP with that word when the request names no peer host.

## Report

Send exactly one message to the address given in the request, copied verbatim including its
`.host` suffix (`atm send <agent@team.host> --stdin <<'EOF' … EOF`; the suffix is what routes the
report across hosts — without it the message lands in a local queue nobody reads). Use the template
`../atm-smoke/REPORT.md` (sibling skill directory), skill name `atm-setup-environment`.
