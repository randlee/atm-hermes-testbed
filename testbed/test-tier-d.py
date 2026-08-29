"""Tier D: herdr surface — peer tech, independent of tmux.

Runs INSIDE the testbed container against the real herdr binary (headless
server mode — the TUI panics under qemu, the server does not).

Scope split (2026-08-27, verified against atm-core source):
  D1-D6 herdr primitives: provable NOW. herdr runs headless; atm's herdr
        routing (Phase AQ, LocalMessageReceivedBackend::Herdr /
        HerdrReceivedHook) is NOT in the container's atm 1.4.3 release —
        `strings atm-daemon | grep -ci herdr` == 0, and git confirms the
        herdr backend is not in v1.4.3 ancestry.
  D7    ATM->herdr nudge routing: SKIPPED until an atm release >= 1.4.4
        ships the herdr delivery backend (release-candidate-v1.4.4 tag
        exists; GitHub release pending).
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, "/opt/testbed")
from result import Recorder  # noqa: E402

REC = Recorder()
FAILED: list[str] = []
SKIPPED: list[str] = []
SOCKET = Path("/root/.config/herdr/herdr.sock")
SERVER_LOG = "/tmp/herdr-server.log"


def herdr(args: list[str], expect_rc: int | None = 0, timeout: int = 60) -> tuple[int, str, str]:
    p = subprocess.run(["herdr", *args], capture_output=True, text=True, timeout=timeout)
    if expect_rc is not None and p.returncode != expect_rc:
        raise AssertionError(
            f"herdr {' '.join(args)}: rc={p.returncode} (want {expect_rc})\n"
            f"stdout: {p.stdout[:300]}\nstderr: {p.stderr[:300]}")
    return p.returncode, p.stdout, p.stderr


def herdr_json(args: list[str]) -> dict:
    """herdr ALWAYS emits {"id":..., "result":{...}} JSON (no --json flag)."""
    _, out, _ = herdr(args)
    data = json.loads(out)
    if "error" in data:
        raise AssertionError(f"herdr {args}: {data['error']}")
    return data["result"]


def ensure_server() -> None:
    if SOCKET.exists():
        return
    subprocess.run(["sh", "-c", "pkill -f '[h]erdr server' 2>/dev/null; true"],
                   capture_output=True)
    time.sleep(1.0)
    subprocess.run(["sh", "-c", f"nohup herdr server > {SERVER_LOG} 2>&1 &"],
                   capture_output=True)
    deadline = time.time() + 30
    while time.time() < deadline and not SOCKET.exists():
        time.sleep(0.5)
    if not SOCKET.exists():
        subprocess.run(["sh", "-c", f"tail -10 {SERVER_LOG}"])
        raise AssertionError("herdr server never published its socket")


def wait_read(pane: str, marker: str, timeout_ms: int = 20000) -> str:
    _, out, _ = herdr(["pane", "read", pane, "--source", "recent-unwrapped"])
    if marker in out:
        return out
    rc, out2, err = herdr(["pane", "wait-output", "--match", marker,
                           "--timeout", str(timeout_ms), pane], expect_rc=None)
    if rc != 0:
        raise AssertionError(f"wait-output for {marker!r} failed: {err[:200]}")
    _, out3, _ = herdr(["pane", "read", pane, "--source", "recent-unwrapped"])
    return out3


# ---------------- tests ----------------

def d1_server_headless(label: str) -> None:
    ensure_server()
    assert SOCKET.exists()
    rc, out, _ = herdr(["status"], expect_rc=None)
    assert rc == 0 or "server" in out.lower(), out[:200]


def d2_workspace_round_trip(label: str) -> None:
    ws = herdr_json(["workspace", "create", "--label", label])
    workspace = ws.get("workspace", ws)
    wid = workspace.get("workspace_id") or workspace.get("id")
    assert wid, f"no workspace id: {ws}"
    assert workspace.get("label") == label, workspace
    listed = herdr_json(["workspace", "list"])
    items = listed.get("workspaces", [])
    labels = [w.get("label") for w in items]
    assert label in labels, f"{label} not in {labels}"


def _pane_ids(wid: str) -> list[str]:
    panes = herdr_json(["pane", "list", "--workspace", wid])
    items = panes.get("panes", [])
    return [p.get("pane_id") or p.get("id") for p in items]


def d3_pane_split_rename(label: str, wid: str) -> None:
    items = _pane_ids(wid)
    assert items, f"workspace {wid} has no panes"
    root = items[0]
    new = herdr_json(["pane", "split", root, "--direction", "down"])
    pane = new.get("pane", new)
    new_id = pane.get("pane_id") or pane.get("id")
    assert new_id, f"split returned no pane id: {new}"
    herdr(["pane", "rename", new_id, "stub-beta"])
    panes = herdr_json(["pane", "list", "--workspace", wid])
    got = {p.get("pane_id"): (p.get("label") or p.get("title")) for p in panes.get("panes", [])}
    assert got.get(new_id) == "stub-beta", got
    assert len(got) == len(items) + 1, (len(items), len(got))


def d4_pane_run_execution(wid: str) -> None:
    pane = _pane_ids(wid)[0]
    marker = f"D4-RUN-{int(time.time())}"
    herdr(["pane", "run", pane, f"echo {marker}"])
    got = wait_read(pane, marker)
    assert got.count(marker) >= 2, \
        f"command typed but output line missing (count={got.count(marker)}):\n{got[-300:]}"


def d5_wait_output_sentinel(wid: str) -> None:
    pane = _pane_ids(wid)[0]
    marker = f"D5-SENTINEL-{int(time.time())}"
    # readiness sentinel pattern: background command, wait-output gates on it
    herdr(["pane", "run", pane, f"(sleep 2; echo {marker}) &"])
    rc, out, err = herdr(["pane", "wait-output", "--match", marker,
                          "--timeout", "15000", pane], expect_rc=None)
    assert rc == 0, f"sentinel never matched: {err[:200]}"


def d6_agent_list_surface(label: str) -> None:
    rc, out, _ = herdr(["agent", "list"], expect_rc=None)
    assert rc == 0, out[:200]


def d7_herdr_nudge_routing(label: str) -> None:
    raise AssertionError("unreachable: D7 is skipped, not run")


def main() -> int:
    suffix = sys.argv[1] if len(sys.argv) > 1 else str(int(time.time()))
    label = f"tierd-{suffix}"
    wid_holder: dict[str, str] = {}

    def d2_run(_label: str) -> None:
        d2_workspace_round_trip(label)
        listed = herdr_json(["workspace", "list"])
        for w in listed.get("workspaces", []):
            if w.get("label") == label:
                wid_holder["wid"] = w.get("workspace_id") or w.get("id")
        assert wid_holder.get("wid"), f"could not resolve wid for {label}"

    def d3_run(_label: str) -> None:
        d3_pane_split_rename(label, wid_holder["wid"])

    def d4_run(_label: str) -> None:
        d4_pane_run_execution(wid_holder["wid"])

    def d5_run(_label: str) -> None:
        d5_wait_output_sentinel(wid_holder["wid"])

    tests = [
        ("D1-server-headless", d1_server_headless),
        ("D2-workspace-round-trip", d2_run),
        ("D3-pane-split-rename", d3_run),
        ("D4-pane-run-execution", d4_run),
        ("D5-wait-output-sentinel", d5_run),
        ("D6-agent-list-surface", d6_agent_list_surface),
    ]
    for name, fn in tests:
        try:
            fn(label)
            print(f"PASS {name}")
            REC.pass_(name)
        except Exception as exc:  # noqa: BLE001
            print(f"FAIL {name}: {exc}")
            FAILED.append(name)
            REC.fail(name, str(exc))

    # D7: ATM->herdr nudge routing — blocked on an atm pre-release dispatch
    # carrying the herdr delivery backend (Phase AQ). v1.4.3 and v1.4.4 do NOT
    # carry it (verified: git grep HerdrSteer on both tags is empty); the first
    # binary with it is the prerelease dispatch (planned 1.4.6, PR #1096,
    # team-lead@atm-dev).
    SKIPPED.append("D7-herdr-nudge-routing (needs first pre-release dispatch w/ herdr backend)")
    REC.skip("D7-herdr-nudge-routing", "needs first pre-release dispatch (Phase AQ herdr backend)")

    result_path = REC.emit("D", "herdr-surface")
    print(f"result: {result_path}")
    print(f"---\n{len(tests) - len(FAILED)}/{len(tests)} passed")
    for s in SKIPPED:
        print(f"SKIP {s}")
    if FAILED:
        print(f"RESULT: FAIL ({', '.join(FAILED)})")
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
