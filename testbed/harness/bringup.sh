#!/bin/sh
# bringup.sh — everything inside the container after the mTLS identity and peer trust exist.
# Run by run.sh; rerunnable (every step is a restart, not an add). Root, inside the container.
#   1 ATM daemon        (trust store is snapshotted at daemon start, so trust must exist before this)
#   2 perms + symlink   (the hermes user reaches the daemon socket/db through /opt/data/.atm)
#   3 herdr server      (socket world-writable so the hermes-user Claude Code hook reports its state)
#   4 roster            (team `testbed`: stub-alpha, stub-beta, tester[herdr], hermes)
#   5 hermes-atm hook   (as hermes, from the profile dir /opt/data), receiver dir, gateway restart
#   6 Claude Code tester(herdr hook for hermes, hmux team from /opt/testbed/.atm.toml, agent rename)
set -eu
TEAM=testbed
CHAT_ID="${TESTBED_CHAT_ID:-1}"
AS_HERMES="setpriv --reuid=hermes --regid=hermes --init-groups env HOME=/opt/data HERMES_HOME=/opt/data USER=hermes LOGNAME=hermes"
export ATM_IDENTITY=stub-alpha ATM_TEAM=$TEAM

# 1
pkill -x atm-daemon 2>/dev/null || true; sleep 1
rm -f /root/.atm/daemon/owner.lock /root/.atm/daemon/local-http.json
nohup atm-daemon >/tmp/atm-daemon.log 2>&1 &
for i in $(seq 1 30); do atm doctor --json >/dev/null 2>&1 && break; sleep 1; done
# 2
chmod 711 /root; chmod 755 /root/.atm /root/.atm/daemon; chmod -R a+rX /root/.atm/daemon
chmod -R a+rwX /root/.atm/db /root/.atm/logs
if [ ! -L /opt/data/.atm ]; then
  [ -e /opt/data/.atm ] && mv /opt/data/.atm "/opt/data/.atm.bak.$$"
  ln -s /root/.atm /opt/data/.atm
fi
# 3
pkill -f "[h]erdr server" 2>/dev/null || true; sleep 1
nohup herdr server >/tmp/herdr-server.log 2>&1 &
for i in $(seq 1 30); do [ -S /root/.config/herdr/herdr.sock ] && break; sleep 1; done
chmod 711 /root/.config /root/.config/herdr; chmod 666 /root/.config/herdr/herdr.sock
# 4 (add-member creates the team on first use; existing members are left alone)
atm teams add-member "$TEAM" stub-alpha --agent-type stub   --home-dir /opt/testbed >/dev/null 2>&1 || true
atm teams add-member "$TEAM" stub-beta  --agent-type stub   --home-dir /opt/testbed >/dev/null 2>&1 || true
atm teams add-member "$TEAM" tester     --agent-type claude --home-dir /opt/testbed --backend herdr >/dev/null 2>&1 || true
atm teams add-member "$TEAM" hermes     --agent-type hermes --home-dir /opt/data >/dev/null 2>&1 || true
# 5 (hermes agents launch from their profile: user hermes, HERMES_HOME=HOME=cwd=/opt/data)
$AS_HERMES sh -c "cd /opt/data && /opt/hermes/.venv/bin/python -m hermes_atm install --profile default --profile-home /opt/data --identity hermes --team $TEAM --chat-id $CHAT_ID --atm-home /root/.atm --workspace-root /opt/testbed" >/tmp/hermes-atm-install.log 2>&1 || echo "bringup: WARN hermes_atm install failed (see /tmp/hermes-atm-install.log)"
$AS_HERMES sh -c "cd /opt/data && hermes plugins enable hermes-atm-native-tools" >/dev/null 2>&1 || true
mkdir -p /opt/testbed/.atm && chown -R hermes /opt/testbed/.atm
pkill -f "[h]ermes gateway run" 2>/dev/null || true   # s6 restarts the gateway with the hook loaded
# 6
$AS_HERMES sh -c "cd /opt/data && herdr integration install claude" >/dev/null 2>&1 || true
herdr pane list 2>/dev/null | python3 -c '
import sys, json, subprocess
for p in json.load(sys.stdin)["result"]["panes"]:
    subprocess.run(["herdr", "pane", "close", p["pane_id"]], capture_output=True)' 2>/dev/null || true
(cd /opt/testbed && hmux) >/tmp/hmux.log 2>&1 || echo "bringup: WARN hmux failed (see /tmp/hmux.log)"
# Claude Code registers with herdr without a name; ATM's herdr backend matches the roster name.
for i in $(seq 1 45); do
  PANE=$(herdr agent list 2>/dev/null | python3 -c '
import sys, json
for a in json.load(sys.stdin)["result"]["agents"]:
    if a.get("agent") == "claude" and not a.get("name"):
        print(a["pane_id"]); break' 2>/dev/null || true)
  if [ -n "$PANE" ]; then herdr agent rename "$PANE" tester >/dev/null 2>&1 || true; break; fi
  sleep 2
done
for i in $(seq 1 30); do pgrep -f "[h]ermes gateway run" >/dev/null 2>&1 && break; sleep 1; done
echo "bringup: done"
atm doctor --json 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print("bringup: doctor", json.dumps(d.get("summary")))' || echo "bringup: WARN doctor did not answer"
herdr agent list 2>/dev/null | python3 -c 'import sys,json; print("bringup: herdr", [(a.get("name"), a.get("agent_status")) for a in json.load(sys.stdin)["result"]["agents"]])' || true
