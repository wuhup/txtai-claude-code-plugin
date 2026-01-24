#!/bin/bash
# Setup for vs (vault search)
# Usage:
#   ./setup.sh              Install (or update if already installed)
#   ./setup.sh --uninstall  Uninstall
#   curl -sSL <url>/setup.sh | bash
#
# Update mode: If an existing installation is detected, offers to update
# vs.py and run incremental index update while preserving the existing index.

set -e

DATA_DIR="${HOME}/.local/share/vault-search"
BIN_DIR="${HOME}/.local/bin"
VS_SCRIPT="${DATA_DIR}/vs.py"
ORIGINAL_PATH="$PATH"

# Handle --uninstall
if [[ "${1:-}" == "--uninstall" ]]; then
    echo ""
    echo "Uninstalling vs..."

    # Disable autostart first (before removing files)
    LAUNCHD_PLIST="${HOME}/Library/LaunchAgents/com.vault-search.daemon.plist"
    SYSTEMD_SERVICE="${HOME}/.config/systemd/user/vault-search.service"

    if [[ -f "$LAUNCHD_PLIST" ]]; then
        launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
        rm -f "$LAUNCHD_PLIST"
        echo "  ✓ Disabled autostart (launchd)"
    fi

    if [[ -f "$SYSTEMD_SERVICE" ]]; then
        systemctl --user stop vault-search.service 2>/dev/null || true
        systemctl --user disable vault-search.service 2>/dev/null || true
        rm -f "$SYSTEMD_SERVICE"
        systemctl --user daemon-reload 2>/dev/null || true
        echo "  ✓ Disabled autostart (systemd)"
    fi

    # Stop daemon if still running
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
# Detect existing installation
# ─────────────────────────────────────────────────────────────
UPDATE_MODE=false
EXISTING_VAULT=""

if [[ -f "${DATA_DIR}/config.json" ]] && [[ -d "${DATA_DIR}/index" ]]; then
    echo "Existing installation detected."
    echo ""

    # Get existing vault path
    EXISTING_VAULT=$(python3 -c "import json; print(json.load(open('${DATA_DIR}/config.json')).get('vault_path', ''))" 2>/dev/null || echo "")

    if [[ -n "$EXISTING_VAULT" ]]; then
        echo "  Vault: $EXISTING_VAULT"
    fi

    # Validate index by checking if embeddings exist
    if [[ -d "${DATA_DIR}/index/embeddings" ]]; then
        echo "  Index: found"

        # Try a test query to validate index is loadable
        echo "  Validating index..."
        export PATH="${BIN_DIR}:${PATH}"
        if [[ -f "${VS_SCRIPT}" ]] && uv run --script "${VS_SCRIPT}" "test" --json >/dev/null 2>&1; then
            echo "  Status: ✓ valid"
            echo ""
            echo "Options:"
            echo "  [u] Update - update vs.py, keep index, run incremental update"
            echo "  [r] Reinstall - fresh install, rebuild index from scratch"
            echo "  [c] Cancel"
            echo ""
            printf "Choice [u/r/c]: "
            read -r CHOICE </dev/tty

            case "$CHOICE" in
                [Uu])
                    UPDATE_MODE=true
                    VAULT_PATH="$EXISTING_VAULT"
                    echo ""
                    echo "Updating existing installation..."
                    echo ""
                    ;;
                [Rr])
                    echo ""
                    echo "Reinstalling from scratch..."
                    echo ""
                    ;;
                *)
                    echo ""
                    echo "Cancelled."
                    exit 0
                    ;;
            esac
        else
            echo "  Status: ✗ index corrupted or incompatible"
            echo ""
            echo "Index validation failed. A fresh install is required."
            printf "Continue with reinstall? [y/N] "
            read -r CONFIRM </dev/tty
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "Cancelled."
                exit 0
            fi
            echo ""
        fi
    else
        echo "  Index: not found"
        echo ""
        echo "Incomplete installation detected. Continuing with fresh install..."
        echo ""
    fi
fi

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

if [[ "$UPDATE_MODE" == true ]]; then
    echo "  ✓ Using existing: $VAULT_PATH"
else
    printf "  Enter path to your documents: "
    read -r VAULT_PATH </dev/tty

    # Expand tilde
    VAULT_PATH="${VAULT_PATH/#\~/$HOME}"

    if [[ -z "$VAULT_PATH" || ! -d "$VAULT_PATH" ]]; then
        echo "  ✗ Invalid path: $VAULT_PATH"
        exit 1
    fi

    echo "  ✓ Document path: $VAULT_PATH"
fi
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

# Clear stale uv cache to ensure fresh dependencies after updates
# This prevents issues when dependency versions change (e.g., txtai upgrades)
UV_CACHE_DIR="${HOME}/.cache/uv/environments-v2"
if [[ -d "${UV_CACHE_DIR}" ]]; then
    rm -rf "${UV_CACHE_DIR}"/vs-* 2>/dev/null && echo "  ✓ Cleared stale dependency cache"
fi

# Create wrapper
cat > "${BIN_DIR}/vs" << 'WRAPPER'
#!/usr/bin/env bash
exec uv run --script "$HOME/.local/share/vault-search/vs.py" "$@"
WRAPPER
chmod +x "${BIN_DIR}/vs"

# Save config (use Python for proper JSON escaping of special characters)
VAULT_PATH="$VAULT_PATH" python3 -c "import json, os; print(json.dumps({'vault_path': os.environ['VAULT_PATH']}))" > "${DATA_DIR}/config.json"

echo "  ✓ Installed to ${BIN_DIR}/vs"

# Add to PATH for this session
export PATH="${BIN_DIR}:${PATH}"

# PATH warning (check original PATH, not modified one)
if [[ ":$ORIGINAL_PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo "  ⚠ Add to your shell profile:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
echo ""

# ─────────────────────────────────────────────────────────────
# Step 4: AI Integrations (skip in update mode)
# ─────────────────────────────────────────────────────────────
if [[ "$UPDATE_MODE" == true ]]; then
    echo "Step 4/5: AI integrations..."
    echo "  (skipped - keeping existing integrations)"
    echo ""
elif [[ -d "${LOCAL_REPO}/integrations" ]]; then
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
    echo "Step 4/5: AI integrations (optional)..."
    echo ""

    printf "  Install Claude Code skill? [y/N] "
    read -r INSTALL_CLAUDE </dev/tty
    if [[ "$INSTALL_CLAUDE" =~ ^[Yy]$ ]]; then
        PLUGIN_DIR="${VAULT_PATH}/.claude-plugin"
        SKILLS_DIR="${PLUGIN_DIR}/skills/vault-search"
        mkdir -p "${SKILLS_DIR}"
        if curl -sSLf "${REPO_URL}/integrations/claude/plugin.json" -o "${PLUGIN_DIR}/plugin.json" && \
           curl -sSLf "${REPO_URL}/integrations/claude/SKILL.md" -o "${SKILLS_DIR}/SKILL.md"; then
            echo "  ✓ Claude skill installed"
        else
            echo "  ✗ Failed to download Claude skill files"
            rm -rf "${PLUGIN_DIR}"
        fi
    fi

    printf "  Install OpenAI Codex AGENTS.md? [y/N] "
    read -r INSTALL_CODEX </dev/tty
    if [[ "$INSTALL_CODEX" =~ ^[Yy]$ ]]; then
        if curl -sSLf "${REPO_URL}/integrations/codex/AGENTS.md" -o "${VAULT_PATH}/AGENTS.md"; then
            echo "  ✓ AGENTS.md installed"
        else
            echo "  ✗ Failed to download AGENTS.md"
        fi
    fi
    echo ""
fi

# ─────────────────────────────────────────────────────────────
# Step 5: Build index and start daemon
# ─────────────────────────────────────────────────────────────
if [[ "$UPDATE_MODE" == true ]]; then
    echo "Step 5/5: Updating index and restarting daemon..."
    echo ""

    # Stop existing daemon before update
    uv run --script "${VS_SCRIPT}" stop 2>/dev/null || true

    # Run incremental update
    uv run --script "${VS_SCRIPT}" update

    echo ""

    # Restart daemon (autostart should already be enabled)
    uv run --script "${VS_SCRIPT}" serve
    sleep 2
else
    echo "Step 5/5: Building index and starting daemon..."
    echo "  This may take several minutes (~500MB models + indexing)"
    echo ""

    uv run --script "${VS_SCRIPT}" index

    echo ""

    # Enable autostart (includes auto-restart on failure)
    uv run --script "${VS_SCRIPT}" autostart --enable
    sleep 2
fi

# Verify
TEST_OUTPUT=$(uv run --script "${VS_SCRIPT}" "test" --json 2>/dev/null || echo '{"error": "failed"}')
if echo "$TEST_OUTPUT" | grep -q '"count"'; then
    echo "  ✓ Verification successful"
else
    echo "  ⚠ Verification returned unexpected output"
fi

# Mark setup complete for status reporting
touch "${DATA_DIR}/.setup-complete"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$UPDATE_MODE" == true ]]; then
    echo "  ✓ Update complete!"
else
    echo "  ✓ Setup complete!"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Usage:"
echo "  vs \"your query\"          Search documents"
echo "  vs \"query\" --json        JSON output"
echo "  vs status                Show index stats"
echo ""
echo "To disable autostart: vs autostart --disable"
echo ""
