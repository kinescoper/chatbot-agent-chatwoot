#!/usr/bin/env bash
# Invoke the Cursor CLI agent on the VPS (gdrant-agent).
# Usage: ./scripts/remote-agent-gdrant.sh "your prompt"
#        ./scripts/remote-agent-gdrant.sh -p "one-shot prompt"

set -e
AGENT_NAME="gdrant-agent"
REMOTE_AGENT="/root/.local/bin/agent"

if [[ -z "$1" ]]; then
  echo "Usage: $0 \"prompt\"   or   $0 -p \"prompt\"" >&2
  echo "Example: $0 \"list files in current directory\"" >&2
  exit 1
fi

# If first arg is -p, use print mode; otherwise pass all args as the prompt
if [[ "$1" == "-p" ]]; then
  PROMPT="$2"
  MODE="-p"
else
  PROMPT="$*"
  MODE="-p"
fi

echo "[$AGENT_NAME] Running: agent $MODE \"$PROMPT\"" >&2
echo "---" >&2
ssh gdrant-agent "${REMOTE_AGENT}" ${MODE} "${PROMPT}"
echo "---" >&2
echo "[$AGENT_NAME] Done." >&2
