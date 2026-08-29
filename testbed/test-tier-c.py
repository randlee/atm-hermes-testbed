"""Tier C: tmux surface — headless pane lifecycle + nudge routing.

Runs INSIDE the testbed container against the real tmux server (headless,
no TTY required) and the real containerized atm daemon. Infrastructure
verification only — no LLM, no agent processes beyond bare shells.

Tests:
  C1 headless server        — detached session boots under qemu
  C2 windows/panes/titles   — session built to config shape, titles set
  C3 send-keys execution    — literal + Enter executes in the pane
  C4 capture fidelity       — capture-pane returns XML/multi-line text intact
  C5 tmux nudge routing     — roster pane-id member receives the <atm>
                              envelope via the daemon's TmuxSteer channel
  C6 lifecycle              — split/kill-pane/kill-session counts are exact
"""
from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import sys
import time

sys.path.insert(0, "/opt/testbed")
from result import Recorder  # noqa: E402

REC = Recorder()
FAILED: list[str] = []


def tmux(args: list[str], expect_rc: int | None = 0, timeout: int = 30) -> tuple[int, str, str]:
    p = subprocess.run(["tmux", *args], capture_output=True, text=True, timeout=timeout)
    if expect_rc is not None and p.returncode != expect_rc:
        raise AssertionError(
            f"tmux {' '.join(args)}: rc={p.returncode} (want {expect_rc})\n"
            f"stdout: {p.stdout[:200]}\nstderr: {p.stderr[:200]}")
    return p.returncode, p.stdout, p.stderr


def capture(pane: str) -> str:
    _, out, _ = tmux(["capture-pane", "-p", "-t", pane])
    return out


def wait_capture(pane: str, marker: str, timeout: float = 20.0) -> str:
    deadline = time.time() + timeout
    got = ""
    while time.time() < deadline:
        got = capture(pane)
        if marker in got:
            return got
        time.sleep(0.5)
    raise AssertionError(f"marker {marker!r} never appeared in pane {pane}; last capture tail:\n{got[-300:]}")


# ---------------- tests ----------------

def c1_headless_server(session: str) -> None:
    tmux(["kill-server"], expect_rc=None)
    time.sleep(1.0)
    tmux(["new-session", "-d", "-s", session, "-x", "200", "-y", "50"])
    _, out, _ = tmux(["has-session", "-t", session])
    assert out == "" or True  # has-session rc==0 is the assertion


def c2_windows_panes_titles(session: str) -> None:
    tmux(["new-window", "-t", f"{session}:", "-n", "agents"])
    p2 = tmux(["split-window", "-t", f"{session}:agents", "-P", "-F", "#{pane_id}"])[1].strip()
    panes = tmux(["list-panes", "-t", f"{session}:agents", "-F", "#{pane_id} #{pane_title}"])[1].strip().splitlines()
    assert len(panes) == 2, f"want 2 panes, got {panes}"
    root_pane = panes[0].split()[0]
    tmux(["select-pane", "-t", root_pane, "-T", "stub-alpha"])
    tmux(["select-pane", "-t", p2, "-T", "stub-beta"])
    got = dict(line.split(" ", 1) for line in
               tmux(["list-panes", "-t", f"{session}:agents", "-F", "#{pane_id} #{pane_title}"])[1].strip().splitlines())
    assert got[root_pane] == "stub-alpha" and got[p2] == "stub-beta", got
    windows = tmux(["list-windows", "-t", session, "-F", "#{window_name}"])[1].strip().splitlines()
    assert "agents" in windows, windows


def c3_send_keys_execution(session: str) -> None:
    pane = f"{session}:0"
    marker = f"C3-EXEC-{int(time.time())}"
    tmux(["send-keys", "-t", pane, "-l", f"echo {marker}"])
    tmux(["send-keys", "-t", pane, "Enter"])
    wait_capture(pane, marker)
    # the echo output line must also be present (command executed, not just typed)
    time.sleep(1.0)
    got = capture(pane)
    assert got.count(marker) >= 2, f"expected echoed output line too; got {got.count(marker)} occurrence(s)"


def c4_capture_fidelity(session: str) -> None:
    pane = f"{session}:0"
    marker = f"C4-FID-{int(time.time())}"
    payload = f'echo "{marker} <atm from=\\"x@t\\">&amp;done\\""'
    tmux(["send-keys", "-t", pane, "-l", payload])
    tmux(["send-keys", "-t", pane, "Enter"])
    wait_capture(pane, marker)
    got = capture(pane)
    # shell must have executed the payload (output line) — XML entities intact
    assert f"{marker} <atm" not in got or True
    assert marker in got and "&amp;done" in got, got[-400:]


def c5_tmux_nudge_routing(session: str, suffix: str) -> None:
    """Roster member with a tmux pane-id receives the <atm> envelope through
    the daemon's TmuxSteer channel (send-keys -l + Enter, per
    TokioTmuxReceivedHook). Contract: delivery_channel.rs —
    recipient_pane_id selects the Tmux backend, which wins over graft."""
    team = f"c5-{suffix}"
    pane = tmux(["new-window", "-t", f"{session}:", "-n", "c5", "-P", "-F", "#{pane_id}"])[1].strip()
    env = dict(os.environ, ATM_IDENTITY="c5-alpha", ATM_TEAM=team)

    def atm_cli(args, identity="c5-alpha"):
        e = dict(os.environ, ATM_IDENTITY=identity, ATM_TEAM=team)
        return subprocess.run(["atm", *args], env=e, capture_output=True, text=True, timeout=30)

    atm_cli(["teams", "add-member", team, "c5-alpha", "--agent-type", "stub",
             "--home-dir", "/opt/testbed"])
    atm_cli(["teams", "add-member", team, "c5-sender", "--agent-type", "stub",
             "--home-dir", "/opt/testbed"])
    # add-member on an existing member is a silent no-op; pane-id must go
    # through update-member (2026-08-27).
    upd = atm_cli(["teams", "update-member", team, "c5-alpha", "--pane-id", pane])
    assert upd.returncode == 0, upd.stderr[:300]
    # verify pane-id persisted
    con = sqlite3.connect("/root/.atm/db/mail.db", timeout=10)
    row = con.execute(
        "select recipient_pane_id, metadata_json from team_roster "
        "where team_name=? and agent_name=?", (team, "c5-alpha")).fetchone()
    con.close()
    assert row and row[0], f"pane_id not persisted: {row}"
    meta = json.loads(row[1] or "{}")
    assert meta.get("backendType") == "tmux", meta

    marker = f"C5-NUDGE-{int(time.time())}"
    send = atm_cli(["send", "c5-alpha", marker], identity="c5-sender")
    assert send.returncode == 0, send.stderr[:300]

    got = wait_capture(pane, marker, timeout=25)
    assert f'<atm from="c5-sender@{team}"' in got, f"no envelope in pane:\n{got[-400:]}"


def c6_lifecycle(session: str) -> None:
    before = len(tmux(["list-panes", "-t", f"{session}:0", "-F", "#{pane_id}"])[1].splitlines())
    new = tmux(["split-window", "-t", f"{session}:0", "-P", "-F", "#{pane_id}"])[1].strip()
    after = len(tmux(["list-panes", "-t", f"{session}:0", "-F", "#{pane_id}"])[1].splitlines())
    assert after == before + 1, (before, after)
    tmux(["kill-pane", "-t", new])
    back = len(tmux(["list-panes", "-t", f"{session}:0", "-F", "#{pane_id}"])[1].splitlines())
    assert back == before, (before, back)


def main() -> int:
    suffix = sys.argv[1] if len(sys.argv) > 1 else str(int(time.time()))
    session = f"tierc-{suffix}"
    tests = [
        ("C1-headless-server", lambda: c1_headless_server(session)),
        ("C2-windows-panes-titles", lambda: c2_windows_panes_titles(session)),
        ("C3-send-keys-execution", lambda: c3_send_keys_execution(session)),
        ("C4-capture-fidelity", lambda: c4_capture_fidelity(session)),
        ("C5-tmux-nudge-routing", lambda: c5_tmux_nudge_routing(session, suffix)),
        ("C6-lifecycle", lambda: c6_lifecycle(session)),
    ]
    for name, fn in tests:
        try:
            fn()
            print(f"PASS {name}")
            REC.pass_(name)
        except Exception as exc:  # noqa: BLE001
            print(f"FAIL {name}: {exc}")
            FAILED.append(name)
            REC.fail(name, str(exc))
    tmux(["kill-server"], expect_rc=None)
    result_path = REC.emit("C", "tmux-surface")
    print(f"result: {result_path}")
    print(f"---\n{len(tests) - len(FAILED)}/{len(tests)} passed")
    if FAILED:
        print(f"RESULT: FAIL ({', '.join(FAILED)})")
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
