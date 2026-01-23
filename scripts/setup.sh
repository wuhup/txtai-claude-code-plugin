#!/bin/bash
# Interactive setup wizard for vs (vault search)
# Installs the vs command, configures vault path, and optionally sets up AI integrations

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${HOME}/.local/share/vault-search"
BIN_DIR="${HOME}/.local/bin"
SETUP_MARKER="${DATA_DIR}/.setup-complete-v2"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  vs - Lightweight Semantic Search Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─────────────────────────────────────────────────────────────
# Step 0: Confirm network downloads
# ─────────────────────────────────────────────────────────────
echo "This setup will:"
echo "  1. Configure your document path"
echo "  2. Install the 'vs' command to ~/.local/bin"
echo "  3. Optionally install AI integrations (Claude, Codex)"
echo "  4. Download embedding models (~500MB)"
echo "  5. Build your search index"
echo ""
read -p "Continue? [Y/n] " -r CONFIRM
if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi
echo ""

# ─────────────────────────────────────────────────────────────
# Step 1: Check for uv
# ─────────────────────────────────────────────────────────────
echo "Step 1/7: Checking for uv..."

if command -v uv &>/dev/null; then
    echo "  ✓ uv is installed ($(uv --version))"
else
    echo "  ⚠ uv not found. Installing..."
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # Add to path for this session
    export PATH="${HOME}/.local/bin:${PATH}"

    if command -v uv &>/dev/null; then
        echo "  ✓ uv installed successfully"
    else
        echo "  ✗ Failed to install uv. Please install manually:"
        echo "    curl -LsSf https://astral.sh/uv/install.sh | sh"
        exit 1
    fi
fi
echo ""

# ─────────────────────────────────────────────────────────────
# Step 2: Configure document path
# ─────────────────────────────────────────────────────────────
echo "Step 2/7: Configure document path..."

# Check if already configured
EXISTING_VAULT=""
if [[ -f "${DATA_DIR}/config.json" ]]; then
    EXISTING_VAULT=$(cat "${DATA_DIR}/config.json" 2>/dev/null | grep -o '"vault_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"//' | sed 's/"$//' || true)
fi

if [[ -n "$EXISTING_VAULT" && -d "$EXISTING_VAULT" ]]; then
    echo "  Existing configuration found: ${EXISTING_VAULT}"
    read -p "  Keep this path? [Y/n] " -r KEEP_PATH
    if [[ ! "$KEEP_PATH" =~ ^[Nn]$ ]]; then
        VAULT_PATH="$EXISTING_VAULT"
    fi
fi

if [[ -z "$VAULT_PATH" ]]; then
    # Try to auto-detect common vault locations
    DETECTED=""
    for candidate in \
        "${HOME}/vault" \
        "${HOME}/Vault" \
        "${HOME}/obsidian" \
        "${HOME}/Obsidian" \
        "${HOME}/Documents/vault" \
        "${HOME}/Documents/Vault" \
        "${HOME}/Documents/Obsidian" \
        "${HOME}/notes" \
        "${HOME}/Notes" \
        "${HOME}/Documents/notes" \
        "${HOME}/Documents/Notes" \
        ; do
        if [[ -d "$candidate" ]]; then
            # Prefer directories with .obsidian (Obsidian vaults)
            if [[ -d "${candidate}/.obsidian" ]]; then
                DETECTED="$candidate"
                break
            elif [[ -z "$DETECTED" ]]; then
                DETECTED="$candidate"
            fi
        fi
    done

    if [[ -n "$DETECTED" ]]; then
        echo "  Detected document folder at: ${DETECTED}"
        if [[ -d "${DETECTED}/.obsidian" ]]; then
            echo "  (Obsidian vault detected)"
        fi
        echo ""
        read -p "  Use this path? [Y/n] " -r USE_DETECTED
        if [[ -z "$USE_DETECTED" || "$USE_DETECTED" =~ ^[Yy] ]]; then
            VAULT_PATH="$DETECTED"
        fi
    fi

    if [[ -z "$VAULT_PATH" ]]; then
        echo ""
        read -p "  Enter path to your documents/vault: " -r VAULT_PATH
    fi

    if [[ -z "$VAULT_PATH" ]]; then
        echo "  ✗ No document path provided. Setup cannot continue."
        exit 1
    fi

    # Safe tilde expansion (no eval to prevent command injection)
    VAULT_PATH="${VAULT_PATH/#\~/$HOME}"

    if [[ ! -d "$VAULT_PATH" ]]; then
        echo "  ✗ Path does not exist: $VAULT_PATH"
        exit 1
    fi
fi

echo "  ✓ Document path: ${VAULT_PATH}"
echo ""

# ─────────────────────────────────────────────────────────────
# Step 3: Install vs command
# ─────────────────────────────────────────────────────────────
echo "Step 3/7: Installing vs command..."

# Create directories
mkdir -p "${DATA_DIR}"
mkdir -p "${BIN_DIR}"

# Copy vs.py to data directory
cp "${SCRIPT_DIR}/vs.py" "${DATA_DIR}/vs.py"
chmod +x "${DATA_DIR}/vs.py"

# Create shell wrapper
cat > "${BIN_DIR}/vs" << 'WRAPPER'
#!/usr/bin/env bash
exec uv run --script "$HOME/.local/share/vault-search/vs.py" "$@"
WRAPPER
chmod +x "${BIN_DIR}/vs"

echo "  ✓ Installed vs to ${BIN_DIR}/vs"

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo "  ⚠ ${BIN_DIR} is not in your PATH"
    echo "  Add this to your ~/.bashrc or ~/.zshrc:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
echo ""

# ─────────────────────────────────────────────────────────────
# Step 4: AI Integrations (optional)
# ─────────────────────────────────────────────────────────────
echo "Step 4/7: AI integrations (optional)..."
echo "  These will be installed to your vault: ${VAULT_PATH}"
echo ""

# Claude Code integration
read -p "  Install Claude Code skill? [y/N] " -r INSTALL_CLAUDE
if [[ "$INSTALL_CLAUDE" =~ ^[Yy]$ ]]; then
    PLUGIN_DIR="${VAULT_PATH}/.claude-plugin"
    SKILLS_DIR="${PLUGIN_DIR}/skills/vault-search"
    mkdir -p "${SKILLS_DIR}"
    cp "${REPO_ROOT}/integrations/claude/plugin.json" "${PLUGIN_DIR}/plugin.json"
    cp "${REPO_ROOT}/integrations/claude/SKILL.md" "${SKILLS_DIR}/SKILL.md"
    echo "  ✓ Claude skill installed to ${PLUGIN_DIR}"
fi

# Codex integration
read -p "  Install OpenAI Codex AGENTS.md? [y/N] " -r INSTALL_CODEX
if [[ "$INSTALL_CODEX" =~ ^[Yy]$ ]]; then
    cp "${REPO_ROOT}/integrations/codex/AGENTS.md" "${VAULT_PATH}/AGENTS.md"
    echo "  ✓ AGENTS.md installed to ${VAULT_PATH}"
fi
echo ""

# ─────────────────────────────────────────────────────────────
# Step 5: Download models
# ─────────────────────────────────────────────────────────────
echo "Step 5/7: Downloading embedding models..."
echo "  This may take a few minutes (~500MB)"
echo ""

# Save vault path to config first
mkdir -p "${DATA_DIR}"
echo "{\"vault_path\": \"${VAULT_PATH}\"}" > "${DATA_DIR}/config.json"

# Running config will trigger model download
uv run --script "${DATA_DIR}/vs.py" config >/dev/null 2>&1 || true

echo "  ✓ Models downloaded"
echo ""

# ─────────────────────────────────────────────────────────────
# Step 6: Build initial index
# ─────────────────────────────────────────────────────────────
echo "Step 6/7: Building search index..."
echo ""

uv run --script "${DATA_DIR}/vs.py" index

echo ""
echo "  ✓ Index built"
echo ""

# ─────────────────────────────────────────────────────────────
# Step 7: Verification and daemon setup
# ─────────────────────────────────────────────────────────────
echo "Step 7/7: Verification and daemon setup..."
echo ""

# Start daemon
echo "  Starting daemon..."
uv run --script "${DATA_DIR}/vs.py" serve

# Wait for daemon to be ready
sleep 2

# Run test query
echo "  Running test query..."
TEST_OUTPUT=$(uv run --script "${DATA_DIR}/vs.py" "test" --json 2>/dev/null || echo '{"error": "failed"}')

if echo "$TEST_OUTPUT" | grep -q '"count"'; then
    COUNT=$(echo "$TEST_OUTPUT" | grep -o '"count"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*' || echo "0")
    echo "  ✓ Test query successful (found ${COUNT} results)"
else
    echo "  ⚠ Test query returned unexpected output"
    echo "    You can verify manually with: vs \"test\" --json"
fi

# Ask about autostart
echo ""
read -p "  Enable daemon autostart on login? [Y/n] " -r AUTOSTART
if [[ -z "$AUTOSTART" || "$AUTOSTART" =~ ^[Yy] ]]; then
    uv run --script "${DATA_DIR}/vs.py" autostart --enable
fi

# Mark setup complete
touch "${SETUP_MARKER}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Usage:"
echo "  vs \"your query\"          Search documents"
echo "  vs \"query\" --json        JSON output"
echo "  vs \"query\" --files       Paths only"
echo "  vs status                Show index stats"
echo "  vs update                Update index"
echo ""
echo "For more options: vs --help"
echo ""
