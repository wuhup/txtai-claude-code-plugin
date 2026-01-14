#!/bin/bash
# First-time setup for vault-search plugin
# Installs uv (if needed), downloads models, and prompts for vault path

set -e

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${HOME}/.local/share/vault-search"
SETUP_MARKER="${DATA_DIR}/.setup-complete-v1"
SCRIPT="${PLUGIN_ROOT}/scripts/vault-search.py"

echo ""

# ─────────────────────────────────────────────────────────────
# Step 0: Confirm network downloads
# ─────────────────────────────────────────────────────────────
echo "This setup will download and install dependencies and models."
echo "Approximate download size: 500MB"
read -p "Continue? [y/N] " -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi
echo ""

# ─────────────────────────────────────────────────────────────
# Step 1: Check for uv
# ─────────────────────────────────────────────────────────────
echo "Step 1/4: Checking for uv..."

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
# Step 2: Download models (via first run)
# ─────────────────────────────────────────────────────────────
echo "Step 2/4: Downloading embedding models..."
echo "  This may take a few minutes on first run (~500MB)"
echo ""

# Just importing txtai will trigger model download
uv run --script "${SCRIPT}" config >/dev/null 2>&1 || true

echo "  ✓ Dependencies installed"
echo ""

# ─────────────────────────────────────────────────────────────
# Step 3: Configure vault path
# ─────────────────────────────────────────────────────────────
echo "Step 3/4: Configuring vault path..."

# Check if already configured
EXISTING_VAULT=$(uv run --script "${SCRIPT}" config 2>/dev/null | grep "Vault path:" | sed 's/.*: //' || true)

if [[ -n "$EXISTING_VAULT" && "$EXISTING_VAULT" != "(not set)" ]]; then
    echo "  Vault already configured: ${EXISTING_VAULT}"
    VAULT_PATH="$EXISTING_VAULT"
else
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
        ; do
        if [[ -d "$candidate" && -d "${candidate}/.obsidian" ]]; then
            DETECTED="$candidate"
            break
        fi
    done

    if [[ -n "$DETECTED" ]]; then
        echo "  Detected vault at: ${DETECTED}"
        echo ""
        read -p "  Use this path? [Y/n] " -r USE_DETECTED
        if [[ -z "$USE_DETECTED" || "$USE_DETECTED" =~ ^[Yy] ]]; then
            VAULT_PATH="$DETECTED"
        fi
    fi

    if [[ -z "$VAULT_PATH" ]]; then
        echo ""
        read -p "  Enter path to your Obsidian vault: " -r VAULT_PATH
    fi

    if [[ -z "$VAULT_PATH" ]]; then
        echo "  ⚠ No vault path provided. You can set it later with:"
        echo "    vault-search config --vault /path/to/vault"
    else
        # Safe tilde expansion (no eval to prevent command injection)
        VAULT_PATH="${VAULT_PATH/#\~/$HOME}"
        uv run --script "${SCRIPT}" config --vault "$VAULT_PATH"
    fi
fi

echo ""

# ─────────────────────────────────────────────────────────────
# Step 4: Build initial index
# ─────────────────────────────────────────────────────────────
echo "Step 4/4: Building search index..."

if [[ -n "$VAULT_PATH" && -d "$VAULT_PATH" ]]; then
    uv run --script "${SCRIPT}" index
    echo ""
    echo "  ✓ Index built successfully"
else
    echo "  ⚠ Skipping index build (no vault configured)"
    echo "  Run 'vault-search index' after setting vault path"
fi

echo ""

# ─────────────────────────────────────────────────────────────
# Done!
# ─────────────────────────────────────────────────────────────
mkdir -p "${DATA_DIR}"
touch "${SETUP_MARKER}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ vault-search setup complete!"
echo ""
echo "Usage:"
echo "  vault-search search \"your query\"  Search the vault"
echo "  vault-search serve                Start daemon for faster searches"
echo "  vault-search update               Update index after vault changes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
