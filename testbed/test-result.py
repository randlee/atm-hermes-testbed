#!/usr/bin/env python3
"""Focused regression tests for citable fixture evidence."""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import result


class RecorderEvidenceTests(unittest.TestCase):
    def recorder(self) -> result.Recorder:
        recorder = object.__new__(result.Recorder)
        recorder.tests = []
        recorder.started = 1_000.0
        recorder.started_monotonic = 500.0
        recorder.doctor = {
            "client_version": "1.5.3",
            "daemon_version": "1.5.3",
            "doctor_status": "ok",
            "doctor_findings": [],
        }
        return recorder

    def emit(self, env: dict[str, str]) -> tuple[Path, dict]:
        with tempfile.TemporaryDirectory() as tmpdir, \
                patch.object(result, "RESULTS_DIR", Path(tmpdir)), \
                patch.object(result, "collect_versions", return_value={}), \
                patch.object(result, "collect_host", return_value={}), \
                patch.object(result.Recorder, "_provenance", return_value={}), \
                patch.dict(os.environ, env, clear=True), \
                patch.object(result.time, "monotonic", return_value=501.25), \
                patch.object(result.time, "time", return_value=1_001.0):
            path = self.recorder().emit("A", "protocol-core")
            return path, json.loads(path.read_text())

    def test_development_result_is_written_but_not_citable(self) -> None:
        _path, doc = self.emit({})
        self.assertFalse(doc["evidence"]["citable"])
        self.assertEqual(
            doc["evidence"]["missing_provenance"],
            list(result.REQUIRED_PROVENANCE_ENV),
        )
        self.assertEqual(doc["duration_ms"], 1_250)

    def test_complete_provenance_is_citable(self) -> None:
        env = {name: f"value-for-{name}" for name in result.REQUIRED_PROVENANCE_ENV}
        _path, doc = self.emit(env)
        self.assertTrue(doc["evidence"]["citable"])
        self.assertEqual(doc["evidence"]["missing_provenance"], [])

    def test_release_proof_writes_diagnostic_json_then_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir, \
                patch.object(result, "RESULTS_DIR", Path(tmpdir)), \
                patch.object(result, "collect_versions", return_value={}), \
                patch.object(result, "collect_host", return_value={}), \
                patch.object(result.Recorder, "_provenance", return_value={}), \
                patch.dict(os.environ, {"TESTBED_RELEASE_PROOF": "1"}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "release-proof provenance missing"):
                self.recorder().emit("D", "herdr-surface")
            doc = json.loads((Path(tmpdir) / "tier-d.json").read_text())
            self.assertFalse(doc["evidence"]["citable"])

    def test_doctor_snapshot_keeps_only_aggregate_warning_and_error_codes(self) -> None:
        payload = {
            "client_context": {"version": "1.5.3"},
            "daemon_context": {"version": "1.5.3"},
            "summary": {"status": "warn"},
            "findings": [
                {"code": "W1", "severity": "warning", "message": "secret one"},
                {"code": "W1", "severity": "warning", "message": "secret two"},
                {"code": "E1", "severity": "error", "message": "secret three"},
                {"code": "I1", "severity": "info", "message": "ignored"},
            ],
        }
        completed = Mock(stdout=json.dumps(payload))
        with patch.object(result.subprocess, "run", return_value=completed):
            snapshot = result.Recorder._doctor_snapshot()
        self.assertEqual(
            snapshot["doctor_findings"],
            [
                {"code": "E1", "severity": "error", "count": 1},
                {"code": "W1", "severity": "warning", "count": 2},
            ],
        )
        self.assertNotIn("secret", json.dumps(snapshot))


if __name__ == "__main__":
    unittest.main()
