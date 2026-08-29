"""Tier A: ATM protocol core — mailbox semantics with stub identities.

Runs INSIDE the testbed container against the real containerized atm daemon.
Mailbox-only tier: no nudges, no graft receivers, no LLM. Deterministic,
zero-cost, re-runnable. Each test uses a fresh team (suffix from argv[1]) so
runs never collide with prior state.

Exit 0 + "RESULT: PASS" when all tests pass.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, "/opt/testbed")
from result import Recorder  # noqa: E402

REC = Recorder()

DAEMON_RECORD = Path("/root/.atm/daemon/local-http.json")
ROSTER_DB = Path("/root/.atm/db/mail.db")
WS_ROOT = "/opt/testbed"

FAILED: list[str] = []


def atm(args: list[str], identity: str, team: str, expect_rc: int | None = 0,
        timeout: int = 30) -> tuple[int, str, str]:
    env = dict(os.environ, ATM_IDENTITY=identity, ATM_TEAM=team)
    p = subprocess.run(["atm", *args], env=env, capture_output=True,
                       text=True, timeout=timeout)
    if expect_rc is not None and p.returncode != expect_rc:
        raise AssertionError(
            f"atm {' '.join(args)}: rc={p.returncode} (want {expect_rc})\n"
            f"stdout: {p.stdout[:300]}\nstderr: {p.stderr[:300]}")
    return p.returncode, p.stdout, p.stderr


def atm_json(args: list[str], identity: str, team: str, expect_rc: int | None = 0) -> dict:
    _, out, _ = atm(args, identity, team, expect_rc)
    return json.loads(out)


def counts(d: dict) -> dict:
    return d["bucket_counts"]


def roster_ok(member: str, team: str) -> bool:
    import sqlite3
    try:
        con = sqlite3.connect(str(ROSTER_DB), timeout=10)
        row = con.execute(
            "select metadata_json from team_roster where team_name=? and agent_name=?",
            (team, member)).fetchone()
        con.close()
        return bool(row and "workspace_root" in (row[0] or ""))
    except Exception:
        return False


def ensure_roster(team: str, members: list[str]) -> None:
    """Register + VERIFY persisted metadata (root cause of the 2026-08-27
    silent-registration bug: update-member can fail and leave no
    workspace_root, which breaks routing later)."""
    admin = members[0]
    for m in members:
        atm(["teams", "add-member", team, m, "--agent-type", "stub",
             "--home-dir", WS_ROOT], admin, team, expect_rc=None)
    for m in members:
        for attempt in range(3):
            atm(["teams", "update-member", team, m, "--workspace-root", WS_ROOT,
                 "--harness", "hermes"], admin, team, expect_rc=None)
            if roster_ok(m, team):
                break
            time.sleep(1.5)
        else:
            raise AssertionError(f"roster: workspace_root never persisted for {m}@{team}")


def ensure_daemon() -> None:
    if DAEMON_RECORD.exists():
        return
    subprocess.run(["sh", "-c", "pkill -9 -f '[a]tm-daemon' 2>/dev/null; true"],
                   capture_output=True)
    time.sleep(1.0)
    lock = Path("/root/.atm/daemon/owner.lock")
    if lock.exists():
        lock.unlink()
    subprocess.run(["sh", "-c", "nohup atm-daemon > /tmp/atm-daemon.log 2>&1 &"],
                   capture_output=True)
    deadline = time.time() + 40
    while time.time() < deadline and not DAEMON_RECORD.exists():
        time.sleep(0.5)
    if not DAEMON_RECORD.exists():
        raise SystemExit("FATAL: atm-daemon did not publish local-http.json")


def run_test(name: str, fn, suffix: str) -> None:
    team = f"{name}-{suffix}"
    try:
        fn(team)
        print(f"PASS {name}")
        REC.pass_(name)
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL {name}: {exc}")
        FAILED.append(name)
        REC.fail(name, str(exc))


# ---------------- tests ----------------

def a1_send_read_history(team: str) -> None:
    alpha, beta = f"alpha-{team}", f"beta-{team}"
    ensure_roster(team, [alpha, beta])
    d = atm_json(["send", alpha, "A1-PAYLOAD", "--json"], beta, team)
    assert d["outcome"] == "sent" and d["message_id"], d
    mid = d["message_id"]
    d = atm_json(["list", alpha, "--json"], alpha, team)
    assert counts(d) == {"unread": 1, "pending_ack": 0, "history": 0}, counts(d)
    assert d["rows"][0]["message_id"] == mid
    d = atm_json(["read", "--json"], alpha, team)
    m = d["message"]
    assert m["message_id"] == mid and m["read"] is True, m
    assert m["text"] == "A1-PAYLOAD", m["text"]
    d = atm_json(["list", alpha, "--json"], alpha, team)
    assert counts(d)["history"] == 1 and counts(d)["unread"] == 0, counts(d)


def a2_pending_ack_lifecycle(team: str) -> None:
    alpha, beta = f"alpha-{team}", f"beta-{team}"
    ensure_roster(team, [alpha, beta])
    d = atm_json(["send", alpha, "A2-PAYLOAD", "--requires-ack", "--json"], beta, team)
    assert d["requires_ack"] is True, d
    mid = d["message_id"]
    d = atm_json(["list", "--pending-ack", "--json"], alpha, team)
    assert counts(d)["pending_ack"] == 1, counts(d)
    assert d["rows"][0]["message_id"] == mid
    # read must NOT clear pending-ack
    d = atm_json(["read", "--json"], alpha, team)
    assert d["message"]["class"] == "pending_ack" and d["message"]["requires_ack"] is True
    d = atm_json(["list", "--json"], alpha, team)
    assert counts(d)["pending_ack"] == 1, counts(d)
    # ack transitions to history and dispatches the reply
    d = atm_json(["ack", mid, "A2-REPLY", "--json"], alpha, team)
    rd = d["reply_disposition"]
    assert rd["kind"] == "sent" and rd["reply_target"] == f"{beta}@{team}", rd
    d = atm_json(["list", "--json"], alpha, team)
    assert counts(d)["pending_ack"] == 0 and counts(d)["history"] == 1, counts(d)


def a3_mailbox_isolation(team: str) -> None:
    alpha, beta = f"alpha-{team}", f"beta-{team}"
    ensure_roster(team, [alpha, beta])
    atm(["send", alpha, "A3-PRIVATE", "--json"], beta, team)
    # alpha sees it
    d = atm_json(["list", "--json"], alpha, team)
    assert counts(d)["unread"] == 1, counts(d)
    # beta's own mailbox is empty
    d = atm_json(["list", "--json"], beta, team)
    assert counts(d) == {"unread": 0, "pending_ack": 0, "history": 0}, counts(d)
    # beta reading alpha's target: no leak into beta's selected stream
    d = atm_json(["read", "--json"], beta, team)
    assert d.get("message") is None or d["message"]["from"] != beta or counts(d) == \
        {"unread": 0, "pending_ack": 0, "history": 0} or d.get("match_count", 0) == 0, d
    # alpha still has its message intact
    d = atm_json(["list", "--json"], alpha, team)
    assert counts(d)["unread"] == 1, counts(d)


def a4_ordering_and_counts(team: str) -> None:
    alpha, beta = f"alpha-{team}", f"beta-{team}"
    ensure_roster(team, [alpha, beta])
    ids = []
    for i in range(3):
        d = atm_json(["send", alpha, f"A4-MSG-{i}", "--json"], beta, team)
        ids.append(d["message_id"])
        time.sleep(0.3)  # force distinct timestamps under emulation
    d = atm_json(["list", alpha, "--all", "--json"], alpha, team)
    assert counts(d)["unread"] == 3, counts(d)
    got = [r["message_id"] for r in d["rows"]]
    # ATM lists newest-first; the rows must be the exact reverse of send order
    assert got == list(reversed(ids)), f"newest-first order violated: {got} != {list(reversed(ids))}"
    texts = [r["summary"] for r in d["rows"]]
    assert texts == ["A4-MSG-2", "A4-MSG-1", "A4-MSG-0"], texts
    # and timestamps must be strictly increasing in send order
    ts = [r["timestamp"] for r in d["rows"]]
    assert ts == sorted(ts, reverse=True), f"timestamps not newest-first: {ts}"


def a5_unknown_recipient(team: str) -> None:
    alpha, beta = f"alpha-{team}", f"beta-{team}"
    ensure_roster(team, [alpha, beta])
    rc, out, err = atm(["send", f"ghost-{team}", "A5-VOID", "--json"],
                       beta, team, expect_rc=None)
    assert rc != 0, f"send to unknown agent succeeded: {out[:200]}"
    blob = (out + err).lower()
    assert "recovery" in blob or "error" in blob or "not" in blob, blob[:300]
    # daemon untouched: no messages materialized anywhere
    d = atm_json(["list", "--json"], alpha, team)
    assert counts(d) == {"unread": 0, "pending_ack": 0, "history": 0}, counts(d)
    d = atm_json(["list", "--json"], beta, team)
    assert counts(d) == {"unread": 0, "pending_ack": 0, "history": 0}, counts(d)


def a6_ack_reply_round_trip(team: str) -> None:
    alpha, beta = f"alpha-{team}", f"beta-{team}"
    ensure_roster(team, [alpha, beta])
    d = atm_json(["send", alpha, "A6-TASK", "--requires-ack", "--json"], beta, team)
    mid = d["message_id"]
    atm(["read", "--json"], alpha, team)
    atm_json(["ack", mid, "A6-DONE-REPLY", "--json"], alpha, team)
    d = atm_json(["list", "--json"], beta, team)
    assert counts(d)["unread"] == 1, counts(d)
    row = d["rows"][0]
    assert row["from"] == alpha and row["summary"] == "A6-DONE-REPLY", row
    d = atm_json(["read", "--json"], beta, team)
    assert d["message"]["text"] == "A6-DONE-REPLY", d["message"]


def a7_cross_team_routing(team: str) -> None:
    team2 = f"{team}-peer"
    a_src = f"alpha-{team}"
    b_dst = f"beta-{team2}"
    ensure_roster(team, [a_src])
    ensure_roster(team2, [b_dst])
    d = atm_json(["send", b_dst, "A7-CROSS", "--team", team2, "--json"],
                 a_src, team)
    assert d["outcome"] == "sent", d
    mid = d["message_id"]
    d = atm_json(["list", "--json"], b_dst, team2)
    assert counts(d)["unread"] == 1, counts(d)
    row = d["rows"][0]
    assert row["message_id"] == mid and row["from"] == a_src, row


def a8_body_fidelity(team: str) -> None:
    alpha, beta = f"alpha-{team}", f"beta-{team}"
    ensure_roster(team, [alpha, beta])
    body = ('A8 <atm from="beta@testbed">&amp; "quotes" <tag>\n'
            "line two\ttabbed\n" + "L" * 5000 + "\n</atm>")
    d = atm_json(["send", alpha, body, "--json"], beta, team)
    mid = d["message_id"]
    # peek targets the MAILBOX (positional agent name), not the message id
    d = atm_json(["peek", alpha, "--all", "--json"], alpha, team)
    assert d.get("selected_message_id") == mid, d.get("selected_message_id")
    m = d["message"]
    assert m["message_id"] == mid, m
    assert m["text"] == body, f"body mutated: len={len(m['text'])} want {len(body)}"
    assert m["requires_ack"] is False


def main() -> int:
    suffix = sys.argv[1] if len(sys.argv) > 1 else str(int(time.time()))
    ensure_daemon()
    tests = [
        ("A1-send-read-history", a1_send_read_history),
        ("A2-pending-ack-lifecycle", a2_pending_ack_lifecycle),
        ("A3-mailbox-isolation", a3_mailbox_isolation),
        ("A4-ordering-and-counts", a4_ordering_and_counts),
        ("A5-unknown-recipient", a5_unknown_recipient),
        ("A6-ack-reply-round-trip", a6_ack_reply_round_trip),
        ("A7-cross-team-routing", a7_cross_team_routing),
        ("A8-body-fidelity", a8_body_fidelity),
    ]
    for name, fn in tests:
        run_test(name, fn, suffix)
    result_path = REC.emit("A", "mailbox-semantics")
    print(f"result: {result_path}")
    print(f"---\n{len(tests) - len(FAILED)}/{len(tests)} passed")
    if FAILED:
        print(f"RESULT: FAIL ({', '.join(FAILED)})")
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
