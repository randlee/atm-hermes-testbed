"""Shared seam-test harness for the in-container testbed.

Provides daemon lifecycle, roster registration-with-verification, and the
GatewayRunner stub-adapter builder. Imported by test-seam.py (phase-1 proof /
Tier B1) and test-tier-b.py (envelope-fidelity tiers).
"""
from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

DAEMON_RECORD = Path("/root/.atm/daemon/local-http.json")
ROSTER_DB = Path("/root/.atm/db/mail.db")
WS_ROOT = "/opt/testbed"
ATM_HOME = "/root/.atm"
WARMUP_S = 45.0


def start_daemon() -> None:
    """Start atm-daemon via a detached SHELL launch (empirically the only
    launch mode whose nudge delivery works under qemu; 2026-08-27)."""
    subprocess.run(["sh", "-c", "pkill -9 -f '[a]tm-daemon' 2>/dev/null; true"],
                   capture_output=True)
    time.sleep(1.0)
    lock = Path("/root/.atm/daemon/owner.lock")
    if lock.exists():
        lock.unlink()
    subprocess.run(["sh", "-c", "nohup atm-daemon > /tmp/atm-daemon.log 2>&1 &"],
                   capture_output=True)


def ensure_daemon() -> None:
    """Guarantee the daemon endpoint record exists + warm up the nudge path.

    Cold-start empiricism (2026-08-27): local-http.json appears ~0s after
    start, but the nudge delivery path is not live until ~16-30s later
    (slower under x86_64 emulation on arm64). Gate on 45s of record age.
    """
    if not DAEMON_RECORD.exists():
        start_daemon()
        deadline = time.time() + 40
        while time.time() < deadline and not DAEMON_RECORD.exists():
            time.sleep(0.5)
        if not DAEMON_RECORD.exists():
            subprocess.run(["sh", "-c", "tail -5 /tmp/atm-daemon.log 2>/dev/null"])
            start_daemon()
            deadline = time.time() + 40
            while time.time() < deadline and not DAEMON_RECORD.exists():
                time.sleep(0.5)
    if not DAEMON_RECORD.exists():
        raise SystemExit("FATAL: atm-daemon did not publish local-http.json")
    age = time.time() - DAEMON_RECORD.stat().st_mtime
    remaining = WARMUP_S - age
    if remaining > 0:
        print(f"daemon warm-up: waiting {remaining:.0f}s for nudge path")
        time.sleep(remaining)


def roster_has_workspace_root(member: str, team: str) -> bool:
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


def ensure_roster(team: str, members: list[str], admin: str | None = None) -> None:
    """Register members WITH verification. workspace_root + harness are
    REQUIRED on EVERY member for nudge routing — silent registration loss
    was the root cause of the 2026-08-27 'send succeeds, no nudge' bug."""
    admin = admin or members[0]
    env = dict(os.environ, ATM_IDENTITY=admin, ATM_TEAM=team)
    for m in members:
        subprocess.run(["atm", "teams", "add-member", team, m,
                        "--agent-type", "stub", "--home-dir", WS_ROOT],
                       env=env, capture_output=True, text=True, timeout=30)
    for m in members:
        for attempt in range(1, 4):
            subprocess.run(["atm", "teams", "update-member", team, m,
                            "--workspace-root", WS_ROOT, "--harness", "hermes"],
                           env=env, capture_output=True, text=True, timeout=30)
            if roster_has_workspace_root(m, team):
                break
            print(f"roster verify: {m} attempt {attempt} not persisted, retrying")
            time.sleep(2.0)
        else:
            raise SystemExit(f"FATAL: workspace_root never persisted for {m}@{team}")


def build_runner(profile: str = "testbed"):
    """Build a GatewayRunner with a stub Telegram adapter (no bot token in
    the testbed — same shape as the fork's own seam suite)."""
    import sys
    sys.path.insert(0, "/opt/hermes")
    from gateway.config import GatewayConfig, Platform, PlatformConfig
    from gateway.run import GatewayRunner

    class _StubAdapter:
        def __init__(self):
            self.handled_events = []
            self.sent = []
            self.platform = Platform.TELEGRAM

        async def send(self, chat_id, text, **kwargs):
            self.sent.append((chat_id, text))
            return MagicMock(success=True, error=None)

        async def handle_message(self, event):
            self.handled_events.append(event)

    runner = object.__new__(GatewayRunner)
    runner.config = GatewayConfig(
        platforms={Platform.TELEGRAM: PlatformConfig(enabled=True, token="testbed-stub")})
    adapter = _StubAdapter()
    runner.adapters = {Platform.TELEGRAM: adapter}
    runner._profile_adapters = {}
    runner._active_profile_name = lambda: profile
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


def write_hook_config(path: Path, profile: str, identity: str, team: str,
                      chat_id: str = "1001") -> None:
    path.write_text(json.dumps({
        "schema_version": 1,
        "profile": profile,
        "atm_home": ATM_HOME,
        "identity": identity,
        "team": team,
        "chat_id": chat_id,
        "workspace_root": WS_ROOT,
    }))
