#!/bin/sh
# Initialize the disposable fixture through public ATM commands only.
set -eux

TEAM=${ATM_TEAM:-testbed}
MEMBERS=${ATM_MEMBERS_FILE:-/opt/testbed/members.txt}
export ATM_IDENTITY=${ATM_IDENTITY:-stub-alpha} ATM_TEAM=$TEAM

[ -r "$MEMBERS" ] || { echo "atm-db-init: missing members file: $MEMBERS" >&2; exit 1; }

fingerprint=$(atm peer certificate show --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["fingerprint"])')
trust_row_present() {
  atm peer trust list --json | python3 -c 'import json,sys; expected=sys.argv[1]; data=json.load(sys.stdin); rows=data if isinstance(data,list) else data.get("rows",[]); raise SystemExit(0 if any(row.get("host")=="localhost" and row.get("fingerprint")==expected and row.get("https_port")==43101 for row in rows) else 1)' "$fingerprint"
}
if ! trust_row_present; then
  atm peer trust add --host localhost --fingerprint "$fingerprint" --https-port 43101 --yes
fi

nohup atm-daemon >>/tmp/atm-daemon.log 2>&1 &
ready=no
for unused in $(seq 1 30); do
  if atm doctor --json >/dev/null 2>&1; then ready=yes; break; fi
  kill -0 "$!" 2>/dev/null || { tail -20 /tmp/atm-daemon.log >&2; exit 1; }
  sleep 1
done
[ "$ready" = yes ] || { echo "atm-db-init: daemon did not become ready" >&2; tail -20 /tmp/atm-daemon.log >&2; exit 1; }

while read -r team member agent_type home_dir backend session; do
  case "$team" in ''|'#'*) continue ;; esac
  # add-member creates the team on its first row.
  set -- atm teams add-member "$team" "$member" --agent-type "$agent_type" --home-dir "$home_dir"
  [ "$backend" = - ] || set -- "$@" --backend "$backend"
  [ "$session" = - ] || set -- "$@" --session "$session"
  "$@" >/dev/null
done < "$MEMBERS"

echo "atm-db-init: ready ($(atm teams --json | python3 -c 'import json,sys; data=json.load(sys.stdin); print(len(data) if isinstance(data,list) else data.get("count", "?"))') teams)"
