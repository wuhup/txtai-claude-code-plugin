#!/bin/bash
# Setup for vs (vault search)
# Usage:
#   ./setup.sh                           Interactive setup
#   ./setup.sh /path/to/docs             With path argument
#   curl -sSL <url>/setup.sh | bash -s -- /path/to/docs   Remote install

set -e

VAULT_PATH="${1:-}"
DATA_DIR="${HOME}/.local/share/vault-search"
BIN_DIR="${HOME}/.local/bin"
VS_SCRIPT="${DATA_DIR}/vs.py"

# Detect if running from local clone or remote
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LOCAL_VS_PY="${SCRIPT_DIR}/vs.py"
LOCAL_REPO="${SCRIPT_DIR}/.."
REPO_URL="https://raw.githubusercontent.com/wuhup/vault-search/main"

# Detect interactive mode
INTERACTIVE=false
if [[ -t 0 ]]; then
    INTERACTIVE=true
fi

# Helper to read input (works when piped via /dev/tty)
ask() {
    local prompt="$1"
    local var="$2"
    local default="$3"

    if [[ "$INTERACTIVE" == "true" ]]; then
        read -p "$prompt" -r "$var"
    else
        read -p "$prompt" -r "$var" </dev/tty 2>/dev/null || eval "$var='$default'"
    fi
}

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
        ask "  Use this path? [y/N] " USE_DETECTED ""
        if [[ "$USE_DETECTED" =~ ^[Yy]$ ]]; then
            VAULT_PATH="$DETECTED"
        fi
    fi

    if [[ -z "$VAULT_PATH" ]]; then
        ask "  Enter path to your documents: " VAULT_PATH ""
    fi
fi

# Expand tilde
VAULT_PATH="${VAULT_PATH/#\~/$HOME}"

if [[ -z "$VAULT_PATH" || ! -d "$VAULT_PATH" ]]; then
    echo "  ✗ Invalid path: $VAULT_PATH"
    echo ""
    echo "  Usage: curl -sSL <url>/setup.sh | bash -s -- /path/to/docs"
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
if [[ "$INTERACTIVE" == "true" && -d "${LOCAL_REPO}/integrations" ]]; then
    echo "Step 4/5: AI integrations (optional)..."
    echo ""

    ask "  Install Claude Code skill? [y/N] " INSTALL_CLAUDE ""
    if [[ "$INSTALL_CLAUDE" =~ ^[Yy]$ ]]; then
        PLUGIN_DIR="${VAULT_PATH}/.claude-plugin"
        SKILLS_DIR="${PLUGIN_DIR}/skills/vault-search"
        mkdir -p "${SKILLS_DIR}"
        cp "${LOCAL_REPO}/integrations/claude/plugin.json" "${PLUGIN_DIR}/plugin.json"
        cp "${LOCAL_REPO}/integrations/claude/SKILL.md" "${SKILLS_DIR}/SKILL.md"
        echo "  ✓ Claude skill installed"
    fi

    ask "  Install OpenAI Codex AGENTS.md? [y/N] " INSTALL_CODEX ""
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
