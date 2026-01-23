#!/bin/bash
# Setup for vs (vault search)
# Usage:
#   ./setup.sh              Install
#   ./setup.sh --uninstall  Uninstall
#   curl -sSL <url>/setup.sh | bash

set -e

DATA_DIR="${HOME}/.local/share/vault-search"
BIN_DIR="${HOME}/.local/bin"
VS_SCRIPT="${DATA_DIR}/vs.py"

# Handle --uninstall
if [[ "${1:-}" == "--uninstall" ]]; then
    echo ""
    echo "Uninstalling vs..."

    # Stop daemon if running
    if [[ -f "${DATA_DIR}/.vault-search.pid" ]]; then
        PID=$(cat "${DATA_DIR}/.vault-search.pid" 2>/dev/null || true)
        if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null || true
            echo "  ✓ Stopped daemon"
        fi
    fi

    # Remove files
    rm -f "${BIN_DIR}/vs"
    echo "  ✓ Removed ${BIN_DIR}/vs"

    rm -rf "${DATA_DIR}"
    echo "  ✓ Removed ${DATA_DIR}"

    echo ""
    echo "Uninstall complete."
    exit 0
fi

# Detect if running from local clone or remote
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LOCAL_VS_PY="${SCRIPT_DIR}/vs.py"
LOCAL_REPO="${SCRIPT_DIR}/.."
REPO_URL="https://raw.githubusercontent.com/wuhup/vault-search/main"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  vs - Lightweight Semantic Search Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─────────────────────────────────────────────────────────────
# Step 1: Check for uv
# ─────────────────────────────────────────────────────────────
echo "Step 1/5: Checking for uv..."

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
# Step 2: Configure document path
# ─────────────────────────────────────────────────────────────
echo "Step 2/5: Configuring document path..."

printf "  Enter path to your documents: "
read -r VAULT_PATH </dev/tty

# Expand tilde
VAULT_PATH="${VAULT_PATH/#\~/$HOME}"

if [[ -z "$VAULT_PATH" || ! -d "$VAULT_PATH" ]]; then
    echo "  ✗ Invalid path: $VAULT_PATH"
    exit 1
fi

echo "  ✓ Document path: $VAULT_PATH"
echo ""

# ─────────────────────────────────────────────────────────────
# Step 3: Install vs
# ─────────────────────────────────────────────────────────────
echo "Step 3/5: Installing vs..."

mkdir -p "${DATA_DIR}"
mkdir -p "${BIN_DIR}"

# Get vs.py from local clone or download
if [[ -f "${LOCAL_VS_PY}" ]]; then
    cp "${LOCAL_VS_PY}" "${VS_SCRIPT}"
    echo "  (from local clone)"
else
    echo "  Downloading from GitHub..."
    if ! curl -sSLf "${REPO_URL}/scripts/vs.py" -o "${VS_SCRIPT}"; then
        echo "  ✗ Failed to download vs.py"
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

# Save config
echo "{\"vault_path\": \"${VAULT_PATH}\"}" > "${DATA_DIR}/config.json"

echo "  ✓ Installed to ${BIN_DIR}/vs"

# Add to PATH for this session
export PATH="${BIN_DIR}:${PATH}"

# PATH warning
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo "  ⚠ Add to your shell profile:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
echo ""

# ─────────────────────────────────────────────────────────────
# Step 4: AI Integrations (interactive only)
# ─────────────────────────────────────────────────────────────
if [[ -d "${LOCAL_REPO}/integrations" ]]; then
    echo "Step 4/5: AI integrations (optional)..."
    echo ""

    printf "  Install Claude Code skill? [y/N] "
    read -r INSTALL_CLAUDE </dev/tty
    if [[ "$INSTALL_CLAUDE" =~ ^[Yy]$ ]]; then
        PLUGIN_DIR="${VAULT_PATH}/.claude-plugin"
        SKILLS_DIR="${PLUGIN_DIR}/skills/vault-search"
        mkdir -p "${SKILLS_DIR}"
        cp "${LOCAL_REPO}/integrations/claude/plugin.json" "${PLUGIN_DIR}/plugin.json"
        cp "${LOCAL_REPO}/integrations/claude/SKILL.md" "${SKILLS_DIR}/SKILL.md"
        echo "  ✓ Claude skill installed"
    fi

    printf "  Install OpenAI Codex AGENTS.md? [y/N] "
    read -r INSTALL_CODEX </dev/tty
    if [[ "$INSTALL_CODEX" =~ ^[Yy]$ ]]; then
        cp "${LOCAL_REPO}/integrations/codex/AGENTS.md" "${VAULT_PATH}/AGENTS.md"
        echo "  ✓ AGENTS.md installed"
    fi
    echo ""
else
    echo "Step 4/5: AI integrations..."
    echo "  (skipped - run from cloned repo for AI integrations)"
    echo ""
fi

# ─────────────────────────────────────────────────────────────
# Step 5: Build index and start daemon
# ─────────────────────────────────────────────────────────────
echo "Step 5/5: Building index and starting daemon..."
echo "  This may take several minutes (~500MB models + indexing)"
echo ""

uv run --script "${VS_SCRIPT}" index

echo ""

uv run --script "${VS_SCRIPT}" serve
sleep 2

# Verify
TEST_OUTPUT=$(uv run --script "${VS_SCRIPT}" "test" --json 2>/dev/null || echo '{"error": "failed"}')
if echo "$TEST_OUTPUT" | grep -q '"count"'; then
    echo "  ✓ Verification successful"
else
    echo "  ⚠ Verification returned unexpected output"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Usage:"
echo "  vs \"your query\"          Search documents"
echo "  vs \"query\" --json        JSON output"
echo "  vs status                Show index stats"
echo ""
echo "For autostart: vs autostart --enable"
echo ""
