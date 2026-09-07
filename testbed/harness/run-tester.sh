#!/bin/sh
# Launch the ATM test agent (claude-code) as the non-root 'hermes' user.
# claude refuses --dangerously-skip-permissions as root — mirror run-prompts.sh's
# su-hermes treatment. su -m preserves the pane environment (ANTHROPIC_API_KEY,
# ATM_IDENTITY/ATM_TEAM) that default su would reset; HOME is reset to the hermes
# user's real home (/opt/data) for claude's config/cache.
set -eu
cd /opt/testbed
exec su hermes -m -s /bin/sh -c '
  export HOME=/opt/data
  cd /opt/testbed
  exec claude --model haiku --dangerously-skip-permissions \
    --agent-id "${ATM_IDENTITY}@${ATM_TEAM}" \
    --agent-name "${ATM_IDENTITY}" \
    --team-name "${ATM_TEAM}"
'
