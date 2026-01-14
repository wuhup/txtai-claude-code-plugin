#!/bin/bash
# Quick wrapper for vault-search search command
# Usage: vs "query"

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${PLUGIN_ROOT}/scripts/vault-search.py"

if [[ $# -eq 0 ]]; then
    echo "Usage: vs \"search query\""
    echo "       vs \"search query\" -n 10  (for more results)"
    exit 1
fi

# Run search, filter noisy warnings
uv run --script "${SCRIPT}" search "$@" 2>&1 | grep -v "pkg_resources\|UserWarning\|Device set to use\|__import__"
