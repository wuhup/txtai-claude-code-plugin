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
    echo ""

    # Show what will be removed
    echo "The following will be removed:"
    [[ -f "${BIN_DIR}/vs" ]] && echo "  - ${BIN_DIR}/vs (command)"
    [[ -d "${DATA_DIR}" ]] && echo "  - ${DATA_DIR}/ (data, config, index)"
    [[ -d "${HOME}/.claude/plugins/vault-search" ]] && echo "  - ~/.claude/plugins/vault-search/ (Claude plugin)"

    LAUNCHD_PLIST="${HOME}/Library/LaunchAgents/com.vault-search.daemon.plist"
    SYSTEMD_SERVICE="${HOME}/.config/systemd/user/vault-search.service"
    [[ -f "$LAUNCHD_PLIST" ]] && echo "  - launchd autostart config"
    [[ -f "$SYSTEMD_SERVICE" ]] && echo "  - systemd autostart config"

    echo ""
    printf "Continue? [y/N] "
    read -r CONFIRM_UNINSTALL </dev/tty
    if [[ ! "$CONFIRM_UNINSTALL" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    echo ""

    # Disable autostart first (before removing files)
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

    # Remove Claude plugin (global location)
    if [[ -d "${HOME}/.claude/plugins/vault-search" ]]; then
        rm -rf "${HOME}/.claude/plugins/vault-search"
        echo "  ✓ Removed ~/.claude/plugins/vault-search"
    fi

    # Remove vault-search section from global CLAUDE.md
    CLAUDE_MD="${HOME}/.claude/CLAUDE.md"
    if [[ -f "$CLAUDE_MD" ]] && grep -q "## Vault Search" "$CLAUDE_MD" 2>/dev/null; then
        # Remove section from "## Vault Search" to next heading or EOF
        awk '/^## Vault Search$/{skip=1; next} /^## /{skip=0} !skip' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp"
        mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
        echo "  ✓ Removed vault-search section from ~/.claude/CLAUDE.md"
    fi

    echo ""
    echo "Uninstall complete."
    echo ""
    echo "Note: Project-local installations (.claude/plugins/vault-search in your vault),"
    echo "project CLAUDE.md sections, and AGENTS.md files are not removed."
    echo "Delete them manually if needed."
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
                    echo "  ⚠ This will delete the existing index and rebuild from scratch."
                    echo "  Rebuilding may take several minutes depending on vault size."
                    printf "  Continue? [y/N] "
                    read -r CONFIRM_REINSTALL </dev/tty
                    if [[ ! "$CONFIRM_REINSTALL" =~ ^[Yy]$ ]]; then
                        echo "Cancelled."
                        exit 0
                    fi
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
    echo "  uv is required but not installed."
    echo "  uv is a fast Python package manager from Astral (https://astral.sh/uv)"
    printf "  Install uv now? [y/N] "
    read -r INSTALL_UV </dev/tty
    if [[ ! "$INSTALL_UV" =~ ^[Yy]$ ]]; then
        echo ""
        echo "  Install uv manually: curl -LsSf https://astral.sh/uv/install.sh | sh"
        echo "  Then re-run this setup."
        exit 1
    fi
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

# Save config (preserve existing settings, update vault_path)
VAULT_PATH="$VAULT_PATH" CONFIG_FILE="${DATA_DIR}/config.json" python3 -c "
import json, os
config_file = os.environ['CONFIG_FILE']
try:
    with open(config_file) as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {}
config['vault_path'] = os.environ['VAULT_PATH']
print(json.dumps(config))
" > "${DATA_DIR}/config.json.tmp" && mv "${DATA_DIR}/config.json.tmp" "${DATA_DIR}/config.json"

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
        echo "  Where to install?"
        echo "    [g] Global (~/.claude/plugins/) - available everywhere"
        echo "    [p] Project (${VAULT_PATH}/.claude/plugins/) - this vault only"
        printf "  Choice [g/p]: "
        read -r CLAUDE_LOCATION </dev/tty
        case "$CLAUDE_LOCATION" in
            [Pp])
                PLUGIN_DIR="${VAULT_PATH}/.claude/plugins/vault-search"
                ;;
            *)
                PLUGIN_DIR="${HOME}/.claude/plugins/vault-search"
                ;;
        esac
        mkdir -p "${PLUGIN_DIR}/skills/search"
        cp "${LOCAL_REPO}/integrations/claude/plugin.json" "${PLUGIN_DIR}/plugin.json"
        cp "${LOCAL_REPO}/integrations/claude/skills/search/SKILL.md" "${PLUGIN_DIR}/skills/search/SKILL.md"
        echo "  ✓ Claude skill installed to ${PLUGIN_DIR}"

        # Append to corresponding CLAUDE.md
        if [[ "$CLAUDE_LOCATION" =~ ^[Pp]$ ]]; then
            CLAUDE_MD="${VAULT_PATH}/.claude/CLAUDE.md"
        else
            CLAUDE_MD="${HOME}/.claude/CLAUDE.md"
        fi
        mkdir -p "$(dirname "$CLAUDE_MD")"
        if [[ -f "$CLAUDE_MD" ]] && grep -q "## Vault Search" "$CLAUDE_MD" 2>/dev/null; then
            echo "  ✓ CLAUDE.md already has vault-search instructions"
        else
            cat >> "$CLAUDE_MD" << 'CLAUDEMD'

## Vault Search
For semantic search over the vault, use `vs` (augments Explore agent):
```bash
vs "query"              # find by meaning, not keywords
vs "query" --json       # structured output for parsing
vs "query" --fast       # skip reranking (~10x faster)
```
CLAUDEMD
            echo "  ✓ Added vault-search instructions to ${CLAUDE_MD}"
        fi
    fi

    printf "  Install OpenAI Codex AGENTS.md? [y/N] "
    read -r INSTALL_CODEX </dev/tty
    if [[ "$INSTALL_CODEX" =~ ^[Yy]$ ]]; then
        if [[ -f "${VAULT_PATH}/AGENTS.md" ]]; then
            echo "  ⚠ AGENTS.md already exists at ${VAULT_PATH}/AGENTS.md"
            printf "  Append vault-search instructions? [y/N] "
            read -r APPEND_AGENTS </dev/tty
            if [[ "$APPEND_AGENTS" =~ ^[Yy]$ ]]; then
                echo "" >> "${VAULT_PATH}/AGENTS.md"
                echo "<!-- vault-search integration -->" >> "${VAULT_PATH}/AGENTS.md"
                cat "${LOCAL_REPO}/integrations/codex/AGENTS.md" >> "${VAULT_PATH}/AGENTS.md"
                echo "  ✓ Appended to AGENTS.md"
            else
                echo "  Skipped (file not modified)"
            fi
        else
            cp "${LOCAL_REPO}/integrations/codex/AGENTS.md" "${VAULT_PATH}/AGENTS.md"
            echo "  ✓ AGENTS.md installed"
        fi
    fi
    echo ""
else
    echo "Step 4/5: AI integrations (optional)..."
    echo ""

    printf "  Install Claude Code skill? [y/N] "
    read -r INSTALL_CLAUDE </dev/tty
    if [[ "$INSTALL_CLAUDE" =~ ^[Yy]$ ]]; then
        echo "  Where to install?"
        echo "    [g] Global (~/.claude/plugins/) - available everywhere"
        echo "    [p] Project (${VAULT_PATH}/.claude/plugins/) - this vault only"
        printf "  Choice [g/p]: "
        read -r CLAUDE_LOCATION </dev/tty
        case "$CLAUDE_LOCATION" in
            [Pp])
                PLUGIN_DIR="${VAULT_PATH}/.claude/plugins/vault-search"
                ;;
            *)
                PLUGIN_DIR="${HOME}/.claude/plugins/vault-search"
                ;;
        esac
        mkdir -p "${PLUGIN_DIR}/skills/search"
        if curl -sSLf "${REPO_URL}/integrations/claude/plugin.json" -o "${PLUGIN_DIR}/plugin.json" && \
           curl -sSLf "${REPO_URL}/integrations/claude/skills/search/SKILL.md" -o "${PLUGIN_DIR}/skills/search/SKILL.md"; then
            echo "  ✓ Claude skill installed to ${PLUGIN_DIR}"

            # Append to corresponding CLAUDE.md
            if [[ "$CLAUDE_LOCATION" =~ ^[Pp]$ ]]; then
                CLAUDE_MD="${VAULT_PATH}/.claude/CLAUDE.md"
            else
                CLAUDE_MD="${HOME}/.claude/CLAUDE.md"
            fi
            mkdir -p "$(dirname "$CLAUDE_MD")"
            if [[ -f "$CLAUDE_MD" ]] && grep -q "## Vault Search" "$CLAUDE_MD" 2>/dev/null; then
                echo "  ✓ CLAUDE.md already has vault-search instructions"
            else
                cat >> "$CLAUDE_MD" << 'CLAUDEMD'

## Vault Search
For semantic search over the vault, use `vs` (augments Explore agent):
```bash
vs "query"              # find by meaning, not keywords
vs "query" --json       # structured output for parsing
vs "query" --fast       # skip reranking (~10x faster)
```
CLAUDEMD
                echo "  ✓ Added vault-search instructions to ${CLAUDE_MD}"
            fi
        else
            echo "  ✗ Failed to download Claude skill files"
            rm -rf "${PLUGIN_DIR}" 2>/dev/null || true
        fi
    fi

    printf "  Install OpenAI Codex AGENTS.md? [y/N] "
    read -r INSTALL_CODEX </dev/tty
    if [[ "$INSTALL_CODEX" =~ ^[Yy]$ ]]; then
        if [[ -f "${VAULT_PATH}/AGENTS.md" ]]; then
            echo "  ⚠ AGENTS.md already exists at ${VAULT_PATH}/AGENTS.md"
            printf "  Append vault-search instructions? [y/N] "
            read -r APPEND_AGENTS </dev/tty
            if [[ "$APPEND_AGENTS" =~ ^[Yy]$ ]]; then
                echo "" >> "${VAULT_PATH}/AGENTS.md"
                echo "<!-- vault-search integration -->" >> "${VAULT_PATH}/AGENTS.md"
                curl -sSLf "${REPO_URL}/integrations/codex/AGENTS.md" >> "${VAULT_PATH}/AGENTS.md"
                echo "  ✓ Appended to AGENTS.md"
            else
                echo "  Skipped (file not modified)"
            fi
        else
            if curl -sSLf "${REPO_URL}/integrations/codex/AGENTS.md" -o "${VAULT_PATH}/AGENTS.md"; then
                echo "  ✓ AGENTS.md installed"
            else
                echo "  ✗ Failed to download AGENTS.md"
            fi
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

    # Ask about autostart
    echo "  The daemon keeps models in memory for fast searches (~100ms vs ~5s)."
    printf "  Enable daemon autostart on login? [y/N] "
    read -r ENABLE_AUTOSTART </dev/tty
    if [[ "$ENABLE_AUTOSTART" =~ ^[Yy]$ ]]; then
        uv run --script "${VS_SCRIPT}" autostart --enable
        sleep 2
    else
        echo "  Skipped. Run 'vs serve' manually when needed, or 'vs autostart --enable' later."
    fi
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
