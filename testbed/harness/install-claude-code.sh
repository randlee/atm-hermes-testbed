#!/bin/sh
# Install claude-code inside the testbed container — fixture requirement for
# the prompts/atm-team AT0-AT8 suite (fenix@atm-dev, agent = claude-code).
# Idempotent; uses the fork image's Node env. Run inside the container:
#   docker exec hermes-testbed /opt/testbed/harness/install-claude-code.sh
# The ANTHROPIC_API_KEY for haiku flows from env/allowlist.env through
# run.sh's --env-file into the process env of everything exec'd in the
# container (claude-code reads ANTHROPIC_API_KEY natively).
set -eu
if command -v claude >/dev/null 2>&1; then
  claude --version
  exit 0
fi
npm install -g @anthropic-ai/claude-code
claude --version
