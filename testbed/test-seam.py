"""Phase-1 seam proof: ATM nudge -> graft receiver -> GatewayRunner.inject_internal_message.

Runs INSIDE the testbed container. Real components:
  - GatewayRunner.inject_internal_message (the fork's public seam, real code)
  - hermes_atm.hook.handle (the real installed hook, gateway:startup)
  - hermes_atm.HermesAtmRuntime + atm_graft receiver (real native transport)
  - containerized atm daemon (atm send)
Stubbed: the Telegram adapter only (no bot token in the testbed — same as the
fork's own 26-test seam suite).

Exit 0 + PASS on success.
"""
from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

sys.path.insert(0, "/opt/hermes")  # hermes checkout lives here in the image

PROFILE = "testbed"
TEAM = "testbed"
IDENTITY = "stub-alpha"
CHAT_ID = "1001"
WORKSPACE_ROOT = "/opt/testbed"
ATM_HOME = "/root/.atm"
CONFIG_PATH = Path("/tmp/hermes-atm-hook-config.json")
PROOF_TEXT = f"SEAM-PROOF-{int(time.time())}"


def _start_daemon() -> None:
    """Start atm-daemon via a detached SHELL launch. Empirically (2026-08-27):
    working deliveries used shell-detached daemons; also note pgrep/pkill -f
    'atm-daemon' self-matches wrapper shells — match the full binary path,
    and under qemu the process name is qemu-x86_64, not atm-daemon."""
    subprocess.run(
        ["sh", "-c", "pkill -9 -x atm-daemon 2>/dev/null; true"],
        capture_output=True,
    )
    time.sleep(1.0)
    lock = Path("/root/.atm/daemon/owner.lock")
    if lock.exists():
        lock.unlink()
    subprocess.run(
        ["sh", "-c", "nohup atm-daemon > /tmp/atm-daemon.log 2>&1 &"],
        capture_output=True,
    )


def _ensure_daemon() -> None:
    """The graft receiver needs the container daemon publishing local-http.json.

    Cold-start empiricism (2026-08-27): the endpoint record appears ~0s after
    daemon start, but the nudge delivery path is not live until ~16-30s later.
    Wait out a warm-up so first-attempt sends can actually nudge.
    """
    record = Path("/root/.atm/daemon/local-http.json")
    if not record.exists():
        _start_daemon()
        deadline = time.time() + 40
        while time.time() < deadline and not record.exists():
            time.sleep(0.5)
        if not record.exists():
            # one retry cycle with diagnostics
            print("WARN: no endpoint record after 40s; daemon log tail:")
            subprocess.run(["sh", "-c", "tail -5 /tmp/atm-daemon.*.log 2>/dev/null"])
            _start_daemon()
            deadline = time.time() + 40
            while time.time() < deadline and not record.exists():
                time.sleep(0.5)
    if not record.exists():
        raise SystemExit("FAIL: atm-daemon did not publish local-http.json")
    # Warm-up gate: nudge delivery is not live until ~16-30s after the daemon
    # published its endpoint record (slower under x86_64 emulation on arm64).
    age = time.time() - record.stat().st_mtime
    remaining = 45.0 - age
    if remaining > 0:
        print(f"daemon warm-up: waiting {remaining:.0f}s for nudge path")
        time.sleep(remaining)


def _ensure_roster() -> None:
    """Register the test team roster WITH verification.

    workspace-root + harness are REQUIRED on EVERY member for nudge routing —
    the daemon resolves the member's graft endpoint from workspace_root.
    Fire-and-forget registration once silently lost stub-alpha's update
    (2026-08-27); query the roster DB and retry until the metadata persists.
    """
    env = dict(os.environ, ATM_IDENTITY="stub-beta", ATM_TEAM=TEAM)
    for member in (IDENTITY, "stub-beta"):
        subprocess.run(
            ["atm", "teams", "add-member", TEAM, member,
             "--agent-type", "stub", "--home-dir", WORKSPACE_ROOT],
            env=env, capture_output=True, text=True, timeout=30,
        )
    for member in (IDENTITY, "stub-beta"):
        for attempt in range(1, 4):
            subprocess.run(
                ["atm", "teams", "update-member", TEAM, member,
                 "--workspace-root", WORKSPACE_ROOT, "--harness", "hermes"],
                env=env, capture_output=True, text=True, timeout=30,
            )
            if _roster_has_workspace_root(member):
                break
            print(f"roster verify: {member} attempt {attempt} not persisted, retrying")
            time.sleep(2.0)
        else:
            raise SystemExit(f"FAIL: workspace_root never persisted for {member}")


def _roster_has_workspace_root(member: str) -> bool:
    import sqlite3
    try:
        con = sqlite3.connect("/root/.atm/db/mail.db", timeout=10)
        row = con.execute(
            "select metadata_json from team_roster where team_name=? and agent_name=?",
            (TEAM, member),
        ).fetchone()
        con.close()
        return bool(row and "workspace_root" in (row[0] or ""))
    except sqlite3.Error:
        return False


def _build_runner():
    from gateway.config import GatewayConfig, Platform, PlatformConfig
    from gateway.run import GatewayRunner

    class _StubAdapter:
        def __init__(self):
            self.handled_events = []
            self.sent = []
            self._message_handler = None
            self.platform = Platform.TELEGRAM

        async def send(self, chat_id, text, **kwargs):
            self.sent.append((chat_id, text))
            return MagicMock(success=True, error=None)

        async def handle_message(self, event):
            self.handled_events.append(event)

    runner = object.__new__(GatewayRunner)
    runner.config = GatewayConfig(
        platforms={Platform.TELEGRAM: PlatformConfig(enabled=True, token="testbed-stub")}
    )
    adapter = _StubAdapter()
    runner.adapters = {Platform.TELEGRAM: adapter}
    runner._profile_adapters = {}
    runner._active_profile_name = lambda: PROFILE
    runner._running_agents = {}
    runner._running_agents_ts = {}
    runner._session_run_generation = {}
    runner._pending_messages = {}
    runner._pending_approvals = {}
    runner._voice_mode = {}
    runner._background_tasks = set()
    runner._draining = False
    runner._restart_requested = False
    runner._restart_task_started = False
    runner._restart_detached = False
    runner._restart_via_service = False
    runner._restart_drain_timeout = 0.0
    runner._stop_task = None
    runner._exit_code = None
    runner._update_runtime_status = MagicMock()
    runner._is_user_authorized = lambda _source: True
    runner.hooks = MagicMock()
    runner.hooks.emit = AsyncMock()
    runner.delivery_router = MagicMock()
    return runner, adapter


async def main() -> int:
    from hermes_atm import hook

    _ensure_daemon()
    _ensure_roster()
    CONFIG_PATH.write_text(json.dumps({
        "schema_version": 1,
        "profile": PROFILE,
        "atm_home": ATM_HOME,
        "identity": IDENTITY,
        "team": TEAM,
        "chat_id": CHAT_ID,
        "workspace_root": WORKSPACE_ROOT,
    }))

    runner, adapter = _build_runner()
    assert callable(getattr(runner, "inject_internal_message", None)), \
        "seam missing: inject_internal_message not exposed on GatewayRunner"

    # Real hook, real runtime, real graft receiver publication
    await hook.handle("gateway:startup", {"gateway_runner": runner}, CONFIG_PATH)
    print("hook: gateway:startup handled, receiver activated")

    # Wait for the graft endpoint record to be published + resolvable before
    # sending; fresh-container timing otherwise races the daemon's resolution.
    graft_record = Path(f"{WORKSPACE_ROOT}/.atm/graft/{TEAM}/{IDENTITY}.lock")
    deadline = time.time() + 10
    while time.time() < deadline and not graft_record.exists():
        await asyncio.sleep(0.25)
    await asyncio.sleep(1.0)  # daemon endpoint-cache settle

    # Deliver through the real daemon + graft transport. Retry a few times:
    # on a cold container the daemon's nudge delivery path can lag the first
    # send by several seconds (mailbox persists either way), so retry until an
    # event lands or attempts are exhausted.
    send_env = dict(os.environ, ATM_IDENTITY="stub-beta", ATM_TEAM=TEAM)
    received = None
    for attempt in range(1, 6):
        text = f"{PROOF_TEXT}-{attempt}"
        send = subprocess.run(
            ["atm", "send", IDENTITY, text, "--team", TEAM],
            capture_output=True, text=True, timeout=30, env=send_env,
        )
        print(f"atm send #{attempt}: rc={send.returncode} {send.stdout.strip()[:100]}")
        if send.returncode != 0:
            print(f"atm send stderr: {send.stderr.strip()[:400]}")
            return 1
        deadline = time.time() + 15
        while time.time() < deadline:
            if adapter.handled_events:
                received = adapter.handled_events[0]
                break
            await asyncio.sleep(0.25)
        if received is not None:
            break
        print(f"attempt {attempt}: no event yet, retrying")

    if received is None:
        print("FAIL: no event reached the adapter after 5 attempts")
        return 1

    event = received
    body = getattr(getattr(event, "text", None), "strip", lambda: "")() or str(event)
    platform = getattr(getattr(event, "source", None), "platform", None)
    print(f"PASS: injected event received | platform={platform} | text={body[:80]!r}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
