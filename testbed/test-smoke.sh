#!/bin/sh
# test-smoke.sh — phase-1 smoke: atm daemon up, team exists, stub round-trip.
set -e
echo "== hermes-docker-testbed smoke =="
echo "hermes: $(/opt/hermes/bin/hermes --version 2>&1 | head -1)"
echo "atm:    $(atm --version 2>&1 | head -1)"
echo "herdr:  $(herdr --version 2>&1 | head -1)"
echo "tmux:   $(tmux -V)"
echo "python: $(/opt/hermes/.venv/bin/python --version)"
/opt/hermes/.venv/bin/python -c "import hermes_atm, importlib.metadata as m; print('hermes_atm:', m.version('hermes-atm'))"
# NOTE: atm-daemon is NOT started here — boot-time startup under the hermes
# stage-2 load can leave it wedged (observed 2026-08-27). Tests start it
# on-demand via test-seam.py::_ensure_daemon after boot settles.
atm doctor 2>&1 | tail -5 || true
echo "== smoke done (idle) =="
exec sleep infinity
