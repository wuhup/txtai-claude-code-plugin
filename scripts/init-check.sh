#!/bin/bash
# Check if vault-search is set up, run setup if not
# This runs on SessionStart via hook

set -e

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${HOME}/.local/share/vault-search"
SETUP_MARKER="${DATA_DIR}/.setup-complete-v1"

# If already set up, exit silently
if [[ -f "$SETUP_MARKER" ]]; then
    exit 0
fi

# Run setup
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 vault-search: First-time setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exec "${PLUGIN_ROOT}/scripts/setup.sh"
