#!/bin/sh
# Launch the ATM test agent (claude-code) as the non-root 'hermes' user.
# claude refuses --dangerously-skip-permissions as root — mirror run-prompts.sh's
# su-hermes treatment. su -m preserves the pane environment (ANTHROPIC_API_KEY,
# ATM_IDENTITY/ATM_TEAM) that default su would reset; HOME is reset to the hermes
# user's real home (/opt/data) for claude's config/cache.
set -eu
cd /opt/testbed
# setpriv (util-linux) instead of su: su keeps itself as the pane's foreground
# process group leader, so herdr never sees "claude" and the tester is not
# detected as an agent (nudges via the herdr backend need that detection).
# setpriv drops to hermes and execs, so claude IS the pane process.
AS_HERMES="setpriv --reuid=hermes --regid=hermes --init-groups env HOME=/opt/data USER=hermes LOGNAME=hermes"
# First-run onboarding (theme picker, bypass-permissions consent, folder trust,
# API-key confirmation) would park the pane on a prompt nobody answers. Seed once.
$AS_HERMES python3 - <<PY
import json, os
p = "/opt/data/.claude.json"
try:
    d = json.load(open(p))
except Exception:
    d = {}
d.update({"hasCompletedOnboarding": True, "theme": "dark", "bypassPermissionsModeAccepted": True})
d.setdefault("projects", {}).setdefault("/opt/testbed", {})["hasTrustDialogAccepted"] = True
key = os.environ.get("ANTHROPIC_API_KEY", "")
if key:
    approved = d.setdefault("customApiKeyResponses", {}).setdefault("approved", [])
    if key[-20:] not in approved:
        approved.append(key[-20:])
json.dump(d, open(p, "w"))
PY
exec $AS_HERMES claude --model haiku --dangerously-skip-permissions \
  --agent-id "${ATM_IDENTITY}@${ATM_TEAM}" \
  --agent-name "${ATM_IDENTITY}" \
  --team-name "${ATM_TEAM}"
