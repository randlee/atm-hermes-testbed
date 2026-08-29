"""Tier B: seam + nudge envelope fidelity.

Runs INSIDE the testbed container. Exercises the real seam:
  daemon -> graft receiver -> HermesAtmRuntime -> inject_internal_message.

Tests:
  B1 seam regression        — send reaches the stub adapter (phase-1 proof shape)
  B2a delivery envelope     — plain send renders the Delivery template byte-exact
  B2b requires-ack envelope — --requires-ack renders DeliveryAck byte-exact
  B2c task envelope         — --task-id renders DeliveryTask byte-exact
  B3 ack envelope           — ack reply delivers <atm kind="ack" .../> to the
                              SECOND receiver (two graft receivers, one process)
  B6 no-receiver queueing   — send succeeds, message queued, no crash

Envelope templates transcribed from atm-core src/send/nudge_template.rs
(default_template). description = summary-if-nonempty-else-text (send/hook.rs).
"""
from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, "/opt/testbed")
from result import Recorder  # noqa: E402
from seam_harness import ensure_daemon, ensure_roster, WS_ROOT  # noqa: E402

REC = Recorder()
FAILED: list[str] = []
TEAM_FMT = "b-{suffix}"


def expected_envelope(kind: str, sender: str, team: str, mid: str,
                      description: str = "", task_id: str = "",
                      body: str = "") -> str:
    """1.4.3 injected only the envelope. 1.4.6 (develop) appends the raw
    message body after the envelope, separated by a blank line:
    `envelope + "\n\n" + body`. The `body` arg carries that trailing text."""
    head = f'<atm from="{sender}@{team}" message-id="{mid}">'
    env = ""
    if kind == "delivery":
        env = (f"{head}\n  <action>read atm --team {team}</action>\n"
               f"  <description>{description}</description>\n"
               f"  <action>execute the assigned task</action>\n"
               f'  <when idle="immediate" busy="after-current-task"/>\n'
               f'  <console announce="concise" pause="false"/>\n</atm>')
    elif kind == "delivery_ack":
        env = (f"{head}\n  <action>read atm --team {team}</action>\n"
               f"  <action>ack the message</action>\n"
               f"  <description>{description}</description>\n"
               f"  <action>execute the assigned task</action>\n"
               f'  <when idle="immediate" busy="after-current-task"/>\n'
               f'  <console announce="concise" pause="false"/>\n</atm>')
    elif kind == "delivery_task":
        env = (f"{head}\n  <action>read atm --team {team}</action>\n"
               f'  <task id="{task_id}">{description}</task>\n'
               f"  <action>execute the assigned task</action>\n"
               f'  <when idle="immediate" busy="after-current-task"/>\n'
               f'  <console announce="concise" pause="false"/>\n</atm>')
    elif kind == "delivery_task_ack":
        env = (f"{head}\n  <action>read atm --team {team}</action>\n"
               f"  <action>ack the message</action>\n"
               f'  <task id="{task_id}">{description}</task>\n'
               f"  <action>execute the assigned task</action>\n"
               f'  <when idle="immediate" busy="after-current-task"/>\n'
               f'  <console announce="concise" pause="false"/>\n</atm>')
    elif kind == "acknowledge":
        env = f'<atm kind="ack" from="{sender}@{team}" message-id="{mid}"/>'
    else:
        raise ValueError(kind)
    return env + (f"\n\n{body}" if body else "")


class Receiver:
    """One graft receiver + injected-event collector for one identity."""

    def __init__(self, identity: str, team: str, ws_root: str, profile: str):
        self.identity = identity
        self.team = team
        self.ws_root = ws_root
        self.events: list[dict] = []
        self.runtime = None
        self._profile = profile

    async def _inject(self, **kwargs):
        self.events.append(kwargs)

    def activate(self, loop):
        import atm_graft  # noqa: F401  (available in the container venv)
        from hermes_atm.runtime import HermesAtmRuntime
        self.runtime = HermesAtmRuntime.from_components(
            inject_internal_message=self._inject,
            loop=loop,
            platform=None,  # runtime carries platform through untouched
            profile=self._profile,
            environment={
                "ATM_HOME": "/root/.atm",
                "ATM_IDENTITY": self.identity,
                "ATM_TEAM": self.team,
                "ATM_CHAT_ID": "1001",
                "ATM_WORKSPACE_ROOT": self.ws_root,
            },
        )

    def close(self):
        if self.runtime is not None:
            self.runtime.close()
            self.runtime = None


def _register_roster(team: str, members: dict[str, str], admin: str) -> None:
    """members maps identity -> workspace_root; update each member's
    workspace_root to its own receiver directory (daemon resolves the graft
    endpoint from the roster)."""
    env = dict(os.environ, ATM_IDENTITY=admin, ATM_TEAM=team)
    for member in members:
        subprocess.run(["atm", "teams", "add-member", team, member,
                        "--agent-type", "stub", "--home-dir", WS_ROOT],
                       env=env, capture_output=True, text=True, timeout=30)
    for member, ws in members.items():
        Path(ws).mkdir(parents=True, exist_ok=True)
        for attempt in range(1, 4):
            subprocess.run(["atm", "teams", "update-member", team, member,
                            "--workspace-root", ws, "--harness", "hermes"],
                           env=env, capture_output=True, text=True, timeout=30)
            if _roster_ws(member, team) == ws:
                break
            time.sleep(1.5)
        else:
            raise AssertionError(f"workspace_root={ws} never persisted for {member}")


def _roster_ws(member: str, team: str) -> str | None:
    import sqlite3
    try:
        con = sqlite3.connect("/root/.atm/db/mail.db", timeout=10)
        row = con.execute(
            "select metadata_json from team_roster where team_name=? and agent_name=?",
            (team, member)).fetchone()
        con.close()
        if row and row[0]:
            return json.loads(row[0]).get("workspace_root")
    except Exception:
        pass
    return None


def send(identity: str, team: str, to: str, text: str, extra: list[str] | None = None) -> dict:
    env = dict(os.environ, ATM_IDENTITY=identity, ATM_TEAM=team)
    p = subprocess.run(["atm", "send", to, text, *(extra or []), "--json"],
                       env=env, capture_output=True, text=True, timeout=30)
    assert p.returncode == 0, f"send failed: {p.stderr[:300]}"
    return json.loads(p.stdout)


async def wait_event(recv: Receiver, timeout: float = 20.0) -> dict | None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if recv.events:
            return recv.events[0]
        await asyncio.sleep(0.25)
    return None


def _event_text(ev: dict) -> str:
    return str(ev.get("text", "")).strip()


# ---------------- tests ----------------

async def b1_seam_regression(team: str) -> None:
    alpha_ws, beta_ws = f"{WS_ROOT}/b1-alpha", f"{WS_ROOT}/b1-beta"
    _register_roster(team, {"alpha": alpha_ws, "beta": beta_ws}, "alpha")
    loop = asyncio.get_running_loop()
    recv = Receiver("alpha", team, alpha_ws, "b1")
    recv.activate(loop)
    try:
        mid = send("beta", team, "alpha", "B1-SEAM")["message_id"]
        ev = await wait_event(recv)
        assert ev is not None, "no injected event"
        assert _event_text(ev).startswith(f'<atm from="beta@{team}"'), _event_text(ev)[:80]
        assert f'message-id="{mid}"' in _event_text(ev)
    finally:
        recv.close()


async def _envelope_case(team: str, tag: str, extra: list[str] | None,
                         kind: str, task_id: str = "") -> None:
    ws = f"{WS_ROOT}/b2-{tag}"
    recipient = f"rcv-{tag}"
    _register_roster(team, {recipient: ws, "alpha": f"{WS_ROOT}/b2-{tag}-sender"}, recipient)
    loop = asyncio.get_running_loop()
    recv = Receiver(f"rcv-{tag}", team, ws, f"b2-{tag}")
    recv.activate(loop)
    try:
        body = f"B2-{tag.upper()}-BODY"
        mid = send("alpha", team, recipient, body, extra)["message_id"]
        ev = await wait_event(recv)
        assert ev is not None, f"{tag}: no injected event"
        got = _event_text(ev)
        want = expected_envelope(kind, "alpha", team, mid, description=body,
                                 task_id=task_id, body=body)
        assert got == want, (
            f"{tag}: envelope mismatch\n--- got ---\n{got}\n--- want ---\n{want}")
    finally:
        recv.close()


async def b2a_delivery_envelope(team: str) -> None:
    await _envelope_case(team, "plain", None, "delivery")


async def b2b_requires_ack_envelope(team: str) -> None:
    await _envelope_case(team, "reqack", ["--requires-ack"], "delivery_ack")


async def b2c_task_envelope(team: str) -> None:
    # --task-id forces requires_ack (request_requires_ack: task_id.is_some()),
    # so the rendered kind is DeliveryTaskAck, not DeliveryTask.
    await _envelope_case(team, "task", ["--task-id", "T-123"], "delivery_task_ack",
                         task_id="T-123")


async def b3_ack_envelope_two_receivers(team: str) -> None:
    alpha_ws, beta_ws = f"{WS_ROOT}/b3-alpha", f"{WS_ROOT}/b3-beta"
    _register_roster(team, {"alpha": alpha_ws, "beta": beta_ws}, "alpha")
    loop = asyncio.get_running_loop()
    ra = Receiver("alpha", team, alpha_ws, "b3a")
    rb = Receiver("beta", team, beta_ws, "b3b")
    ra.activate(loop)
    rb.activate(loop)
    try:
        d = send("beta", team, "alpha", "B3-TASK", ["--requires-ack"])
        mid = d["message_id"]
        ev = await wait_event(ra)
        assert ev is not None and f'message-id="{mid}"' in _event_text(ev), \
            f"alpha did not receive delivery nudge: {ev and _event_text(ev)[:80]}"
        # alpha reads + acks; the ack reply must nudge BETA with kind="ack"
        env = dict(os.environ, ATM_IDENTITY="alpha", ATM_TEAM=team)
        subprocess.run(["atm", "read", "--json"], env=env, capture_output=True,
                       text=True, timeout=30)
        ack = subprocess.run(["atm", "ack", mid, "B3-DONE", "--json"], env=env,
                             capture_output=True, text=True, timeout=30)
        assert ack.returncode == 0, ack.stderr[:300]
        ack_json = json.loads(ack.stdout)
        reply_mid = ack_json["reply_disposition"]["reply_message_id"]
        # drain alpha's own possible ack-of-ack echo before asserting on beta
        evb = await wait_event(rb)
        assert evb is not None, "beta got no ack-envelope nudge"
        got = _event_text(evb)
        want = expected_envelope("acknowledge", "alpha", team, reply_mid,
                                 body="B3-DONE")
        assert got == want, f"ack envelope mismatch\n--- got ---\n{got}\n--- want ---\n{want}"
    finally:
        ra.close()
        rb.close()


async def b6_no_receiver_queueing(team: str) -> None:
    ws = f"{WS_ROOT}/b6-ghost"
    _register_roster(team, {"ghost": ws, "alpha": f"{WS_ROOT}/b6-alpha"}, "ghost")
    # no receiver activated: the send must succeed and the message must queue
    d = send("alpha", team, "ghost", "B6-QUEUED")
    env = dict(os.environ, ATM_IDENTITY="ghost", ATM_TEAM=team)
    p = subprocess.run(["atm", "list", "--json"], env=env, capture_output=True,
                       text=True, timeout=30)
    data = json.loads(p.stdout)
    bc = data["bucket_counts"]
    assert bc["unread"] == 1, bc
    assert data["rows"][0]["message_id"] == d["message_id"]


def run(name: str, coro_fn, team: str) -> None:
    try:
        asyncio.run(coro_fn(team))
        print(f"PASS {name}")
        REC.pass_(name)
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL {name}: {exc}")
        FAILED.append(name)
        REC.fail(name, str(exc))


def main() -> int:
    suffix = sys.argv[1] if len(sys.argv) > 1 else str(int(time.time()))
    ensure_daemon()
    tests = [
        ("B1-seam-regression", b1_seam_regression),
        ("B2a-delivery-envelope", b2a_delivery_envelope),
        ("B2b-requires-ack-envelope", b2b_requires_ack_envelope),
        ("B2c-task-envelope", b2c_task_envelope),
        ("B3-ack-envelope-two-receivers", b3_ack_envelope_two_receivers),
        ("B6-no-receiver-queueing", b6_no_receiver_queueing),
    ]
    for name, fn in tests:
        run(name, fn, f"{name.split('-')[0].lower()}-{suffix}")
    result_path = REC.emit("B", "seam-envelope-fidelity")
    print(f"result: {result_path}")
    print(f"---\n{len(tests) - len(FAILED)}/{len(tests)} passed")
    if FAILED:
        print(f"RESULT: FAIL ({', '.join(FAILED)})")
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
