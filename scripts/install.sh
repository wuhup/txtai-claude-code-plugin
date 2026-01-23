#!/bin/bash
# Installer for vs (vault search)
# Usage:
#   ./install.sh /path/to/docs           # From local clone
#   ./install.sh                          # Interactive (from local clone)
#   curl -sSL <url>/install.sh | bash -s -- /path/to/docs  # Remote install
#
# This script installs vs.py, creates the wrapper, configures vault path,
# downloads models, builds index, and starts the daemon.

set -e

VAULT_PATH="${1:-}"
DATA_DIR="${HOME}/.local/share/vault-search"
BIN_DIR="${HOME}/.local/bin"
VS_SCRIPT="${DATA_DIR}/vs.py"

# Detect if running from local clone
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_VS_PY="${SCRIPT_DIR}/vs.py"

# Remote URL (for curl-based install)
REPO_URL="https://raw.githubusercontent.com/wuhup/vault-search/main"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  vs - Lightweight Semantic Search Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─────────────────────────────────────────────────────────────
# Step 1: Check for uv
# ─────────────────────────────────────────────────────────────
echo "Step 1/6: Checking for uv..."

if command -v uv &>/dev/null; then
    echo "  ✓ uv is installed"
else
    echo "  Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="${HOME}/.local/bin:${PATH}"

    if ! command -v uv &>/dev/null; then
        echo "  ✗ Failed to install uv"
        exit 1
    fi
    echo "  ✓ uv installed"
fi
echo ""

# ─────────────────────────────────────────────────────────────
# Step 2: Get vault path
# ─────────────────────────────────────────────────────────────
echo "Step 2/6: Configuring document path..."

if [[ -z "$VAULT_PATH" ]]; then
    # Try to auto-detect
    for candidate in \
        "${HOME}/vault" \
        "${HOME}/Vault" \
        "${HOME}/obsidian" \
        "${HOME}/Obsidian" \
        "${HOME}/notes" \
        "${HOME}/Notes" \
        "${HOME}/Documents/vault" \
        "${HOME}/Documents/notes" \
        ; do
        if [[ -d "$candidate" ]]; then
            DETECTED="$candidate"
            break
        fi
    done

    if [[ -n "$DETECTED" ]]; then
        echo "  Detected: $DETECTED"
        read -p "  Use this path? [y/N] " -r USE_DETECTED </dev/tty
        if [[ "$USE_DETECTED" =~ ^[Yy]$ ]]; then
            VAULT_PATH="$DETECTED"
        fi
    fi

    if [[ -z "$VAULT_PATH" ]]; then
        read -p "  Enter path to your documents: " -r VAULT_PATH </dev/tty
    fi
fi

# Expand tilde
VAULT_PATH="${VAULT_PATH/#\~/$HOME}"

if [[ -z "$VAULT_PATH" || ! -d "$VAULT_PATH" ]]; then
    echo "  ✗ Invalid path: $VAULT_PATH"
    exit 1
fi

echo "  ✓ Document path: $VAULT_PATH"
echo ""

# ─────────────────────────────────────────────────────────────
# Step 3: Install vs.py
# ─────────────────────────────────────────────────────────────
echo "Step 3/6: Installing vs..."

mkdir -p "${DATA_DIR}"
mkdir -p "${BIN_DIR}"

# Try local copy first (running from cloned repo), then remote download
if [[ -f "${LOCAL_VS_PY}" ]]; then
    cp "${LOCAL_VS_PY}" "${VS_SCRIPT}"
    echo "  (installed from local clone)"
else
    echo "  Downloading from GitHub..."
    if ! curl -sSLf "${REPO_URL}/scripts/vs.py" -o "${VS_SCRIPT}"; then
        echo "  ✗ Failed to download vs.py"
        echo "    Try cloning the repo and running ./scripts/install.sh instead"
        exit 1
    fi
fi
chmod +x "${VS_SCRIPT}"

# Create wrapper
cat > "${BIN_DIR}/vs" << 'WRAPPER'
#!/usr/bin/env bash
exec uv run --script "$HOME/.local/share/vault-search/vs.py" "$@"
WRAPPER
chmod +x "${BIN_DIR}/vs"

echo "  ✓ Installed to ${BIN_DIR}/vs"

# Add to PATH for this session
export PATH="${BIN_DIR}:${PATH}"
echo ""

# ─────────────────────────────────────────────────────────────
# Step 4: Configure vault path
# ─────────────────────────────────────────────────────────────
echo "Step 4/6: Saving configuration..."

echo "{\"vault_path\": \"${VAULT_PATH}\"}" > "${DATA_DIR}/config.json"
echo "  ✓ Configuration saved"
echo ""

# ─────────────────────────────────────────────────────────────
# Step 5: Download models and build index
# ─────────────────────────────────────────────────────────────
echo "Step 5/6: Downloading models and building index..."
echo "  This may take several minutes (~500MB download)"
echo ""

uv run --script "${VS_SCRIPT}" index

echo ""
echo "  ✓ Index built"
echo ""

# ─────────────────────────────────────────────────────────────
# Step 6: Start daemon and verify
# ─────────────────────────────────────────────────────────────
echo "Step 6/6: Starting daemon and verifying..."

uv run --script "${VS_SCRIPT}" serve
sleep 2

# Test query
TEST_OUTPUT=$(uv run --script "${VS_SCRIPT}" "test" --json 2>/dev/null || echo '{"error": "failed"}')

if echo "$TEST_OUTPUT" | grep -q '"count"'; then
    echo "  ✓ Verification successful"
else
    echo "  ⚠ Verification returned unexpected output"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Installation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Usage:"
echo "  vs \"your query\"          Search documents"
echo "  vs \"query\" --json        JSON output"
echo "  vs status                Show index stats"
echo ""

# Check if PATH needs updating
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo "Note: Add this to your shell profile:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

echo "For autostart on login: vs autostart --enable"
echo ""
