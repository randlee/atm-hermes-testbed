"""Machine-readable result emission for the testbed tiers.

Schema v1 — one JSON file per tier at /opt/testbed/results/tier-<x>.json,
citable as AR evidence without post-processing (agreed with fenix@atm-dev,
2026-08-28).
"""
from __future__ import annotations

import json
import os
import platform
import subprocess
import time
from pathlib import Path

RESULTS_DIR = Path("/opt/testbed/results")


def _cli_version(argv: list[str], strip_prefix: str = "") -> str:
    try:
        out = subprocess.run(argv, capture_output=True, text=True, timeout=15)
        text = (out.stdout or out.stderr).strip().splitlines()[0]
        return text.removeprefix(strip_prefix).strip()
    except Exception:  # noqa: BLE001
        return "unknown"


def _wheel_version(dist: str) -> str:
    try:
        from importlib.metadata import version
        return version(dist)
    except Exception:  # noqa: BLE001
        return "unknown"


def collect_versions() -> dict:
    return {
        "atm": _cli_version(["atm", "--version"], "atm "),
        "hermes_atm": _wheel_version("hermes-atm"),
        "atm_graft": _wheel_version("atm-graft"),
        "herdr": _cli_version(["herdr", "--version"]),
        "hermes_fork": os.environ.get("HERMES_FORK_SHA", "unknown"),
    }


def collect_host() -> dict:
    qemu = os.path.exists("/proc/sys/fs/binfmt_misc/qemu-x86_64") or \
        os.path.exists("/usr/bin/qemu-x86_64")
    return {
        "platform": platform.machine(),
        "emulation": "qemu" if qemu else "native",
    }


class Recorder:
    def __init__(self) -> None:
        self.tests: list[dict] = []
        self.started = time.time()
        self.doctor = self._doctor_snapshot()

    def record(self, name: str, status: str, detail: str | None = None) -> None:
        self.tests.append({"name": name, "status": status, "detail": detail})

    def pass_(self, name: str) -> None:
        self.record(name, "pass")

    def fail(self, name: str, detail: str) -> None:
        self.record(name, "fail", detail)

    def skip(self, name: str, detail: str) -> None:
        self.record(name, "skip", detail)

    @staticmethod
    def _doctor_snapshot() -> dict:
        """`atm doctor --json` at suite start (fenix@atm-dev schema addition):
        makes client/daemon version drift visible in the record instead of in
        a failed run."""
        try:
            out = subprocess.run(["atm", "doctor", "--json"], capture_output=True,
                                 text=True, timeout=60)
            doc = json.loads(out.stdout)
            return {
                "client_version": (doc.get("client_context") or {}).get("version", "unknown"),
                "daemon_version": (doc.get("daemon_context") or {}).get("version", "unknown"),
                "doctor_status": (doc.get("summary") or {}).get("status", "unknown"),
            }
        except Exception:  # noqa: BLE001
            return {"client_version": "unknown", "daemon_version": "unknown",
                    "doctor_status": "unavailable"}

    @staticmethod
    def _provenance() -> dict:
        """Self-certifying artifact provenance (fenix@atm-dev schema addition).
        Artifacts parsed from the build-time asset-provenance.txt; source ref
        + CI run ids come from build-time env (AR1 drop sets them)."""
        artifacts = []
        prov_file = Path("/opt/testbed/asset-provenance.txt")
        if prov_file.exists():
            for line in prov_file.read_text().splitlines():
                parts = line.strip().split(" sha256=")
                if len(parts) == 2 and "=" in parts[0]:
                    artifacts.append({"name": parts[0].split("=", 1)[1],
                                      "sha256": parts[1]})
        return {
            "atm_core_sha": os.environ.get("ATM_CORE_SHA", ""),
            "ci_run_id": os.environ.get("CI_RUN_ID", ""),
            "artifacts": artifacts,
        }

    @property
    def verdict(self) -> str:
        return "fail" if any(t["status"] == "fail" for t in self.tests) else "pass"

    def emit(self, tier: str, suite: str) -> Path:
        counts = {s: sum(1 for t in self.tests if t["status"] == s)
                  for s in ("pass", "fail", "skip")}
        doc = {
            "schema": 1,
            "tier": tier,
            "suite": suite,
            "verdict": self.verdict,
            "counts": counts,
            "tests": self.tests,
            "versions": collect_versions(),
            "provenance": self._provenance(),
            "daemon": self.doctor,
            "image": {
                "tag": os.environ.get("TESTBED_IMAGE_TAG", "loki/hermes-testbed:testbed"),
                "digest": os.environ.get("TESTBED_IMAGE_ID", "unknown"),
            },
            "host": collect_host(),
            "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(self.started)),
            "finished_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "duration_ms": int((time.time() - self.started) * 1000),
        }
        RESULTS_DIR.mkdir(parents=True, exist_ok=True)
        path = RESULTS_DIR / f"tier-{tier.lower()}.json"
        path.write_text(json.dumps(doc, indent=2))
        return path
