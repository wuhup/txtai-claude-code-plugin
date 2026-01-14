#!/bin/bash
# Check if vault-search is set up, prompt for setup if not
# This runs on SessionStart via hook

set -e

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${HOME}/.local/share/vault-search"
SETUP_MARKER="${DATA_DIR}/.setup-complete-v1"

# If not set up, prompt for setup
if [[ ! -f "$SETUP_MARKER" ]]; then
    echo "--------------------------------------------------------"
    echo "vault-search: setup required"
    echo "--------------------------------------------------------"
    echo "Run: ${PLUGIN_ROOT}/scripts/setup.sh"
    echo "This will download dependencies and models."
    exit 0
fi

# Index auto-updates are handled by the daemon (every 60s)
# Run 'vault-search serve' to start the daemon

exit 0
