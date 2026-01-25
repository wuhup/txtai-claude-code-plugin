# vs - Lightweight Semantic Search

A universal command-line tool for semantic search over document vaults using [txtai](https://github.com/neuml/txtai) AI embeddings. **Optimized for CPU-only systems** - no GPU required.

**Find notes by meaning, not just keywords.**

## Features

- **CPU-optimized** - runs on any machine without GPU, using lightweight models
- **Semantic search** - finds documents by meaning, not just keyword matching
- **Hybrid search** - combines BM25 keywords + neural embeddings
- **Daemon mode** - keeps models in memory for fast searches (~1s with `--fast`)
- **Multiple output formats** - human-readable, JSON, or file paths only
- **Optional AI integrations** - Claude Code, OpenAI Codex, etc.

## Installation

### One-Line Install

```bash
curl -sSL https://raw.githubusercontent.com/wuhup/vault-search/main/scripts/setup.sh | bash
```

The setup wizard will:
1. Install [uv](https://github.com/astral-sh/uv) (with your permission)
2. Configure your document path
3. Install `vs` to `~/.local/bin`
4. Optionally install AI integrations (Claude, Codex)
5. Download models (~500MB) and build index
6. Optionally enable daemon autostart

### From Cloned Repo

```bash
git clone https://github.com/wuhup/vault-search
cd vault-search
./scripts/setup.sh
```

### Updating

Run setup again to update:

```bash
curl -sSL https://raw.githubusercontent.com/wuhup/vault-search/main/scripts/setup.sh | bash
```

If an existing installation is detected, you'll be offered:
- **Update** - updates vs.py, runs incremental index update, keeps existing config
- **Reinstall** - fresh install from scratch

### Uninstall

```bash
curl -sSL https://raw.githubusercontent.com/wuhup/vault-search/main/scripts/setup.sh | bash -s -- --uninstall
# or from cloned repo:
./scripts/setup.sh --uninstall
```

## Usage

### Search Commands

```bash
vs "your query"                 # Search (default action)
vs "query" -n 10                # More results
vs "query" --json               # JSON output
vs "query" --files              # Paths only (for pipelines)
vs "query" --fast               # Skip reranking (~5x faster)
vs "query" --min-score 0.5      # Filter low-relevance results
vs "query" -q                   # Quiet mode (suppress warnings)
vs "query" -v                   # Verbose mode (debug output)
```

### Output Formats

**Default (human-readable):**
```
────────────────────────────────────────────────────────────
Results for: authentication
────────────────────────────────────────────────────────────

1. OAuth Implementation Notes
   📁 projects/auth/oauth-notes.md
   Score: 0.892
   Notes on implementing OAuth 2.0 with PKCE flow...
```

**JSON (`--json`):**
```json
{
  "query": "authentication",
  "count": 5,
  "results": [
    {"rank": 1, "path": "projects/auth/oauth-notes.md", "title": "OAuth Implementation Notes", "score": 0.892, "snippet": "..."}
  ]
}
```

**Files only (`--files`):**
```
projects/auth/oauth-notes.md
security/passwords.md
```

### Management Commands

```bash
vs status                       # Show index stats and daemon state
vs update                       # Update index with new/changed files
vs index                        # Full rebuild of search index
vs serve                        # Start daemon
vs stop                         # Stop daemon
vs config                       # Show current configuration
vs config --vault /path         # Set vault path
vs autostart --enable           # Auto-start daemon on login
vs autostart --disable          # Disable auto-start
```

## AI Integrations (Optional)

The `vs` command works standalone, but you can install optional AI integrations during setup (works with both curl and cloned repo installs).

### Claude Code

Answer "y" to "Install Claude Code skill?" during setup. You can choose:
- **Global** (`~/.claude/plugins/vault-search/`) - works in any project
- **Project** (`your-vault/.claude/plugins/vault-search/`) - this vault only

```
~/.claude/plugins/vault-search/   # or .claude/plugins/vault-search/ in project
├── plugin.json
└── skills/
    └── search/
        └── SKILL.md
```

Then Claude can search your vault when you ask:
> "What do I have about project planning?"
> "Find my notes on authentication"

### OpenAI Codex

Answer "y" to "Install OpenAI Codex AGENTS.md?" during setup. This installs `AGENTS.md` to your vault root.

## How It Works

### Hybrid Search
Combines BM25 keyword matching with semantic embeddings for best results.

### Models Used (CPU-optimized)
- **Embeddings**: `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` (118M params, multilingual)
- **Reranker**: `cross-encoder/ms-marco-MiniLM-L-2-v2` (2-layer model for fast CPU inference)

### Daemon Mode
The daemon keeps models in memory for fast searches:
- **With `--fast`**: ~1s (no reranking)
- **With reranking**: ~10-15s (cross-encoder on CPU)
- **Cold start**: ~5s model loading
- **Auto-updates**: Index refreshes every 60s
- **Auto-restart**: When enabled, daemon restarts on crash or reboot

## Configuration

### Environment Variable
```bash
export VAULT_SEARCH_PATH="/path/to/your/vault"
```

### Config File
Settings stored in `~/.local/share/vault-search/config.json`

### Data Locations
```
~/.local/share/vault-search/
├── vs.py              # Installed script
├── config.json        # Configuration
├── index/             # Search index
└── launchd.log        # Daemon logs (macOS)

# Autostart config (created by setup)
~/Library/LaunchAgents/com.vault-search.daemon.plist  # macOS
~/.config/systemd/user/vault-search.service           # Linux
```

## Requirements

- **macOS or Linux** (Windows not supported - uses Unix daemon architecture)
- **Python 3.10–3.12** (managed by uv)
- **~500MB disk space** for models

## Troubleshooting

### "Index not found"
Run `vs index` to build the initial index.

### Slow searches
Start the daemon: `vs serve`

### Out of date results
Daemon auto-updates every 60s. To force immediate: `vs update`

### OpenMP error on macOS
If you see `OMP: Error #15: Initializing libomp.dylib`, the tool sets
`KMP_DUPLICATE_LIB_OK=TRUE` by default to avoid crashes.

### Change vault path
```bash
vs config --vault /new/path
vs index  # Rebuild for new vault
```

## Repository Structure

```
vs/
├── scripts/
│   ├── vs.py                    # Core tool
│   └── setup.sh                 # Setup script (interactive or curl | bash)
│
├── integrations/
│   ├── claude/
│   │   ├── plugin.json          # Plugin manifest
│   │   └── skills/
│   │       └── search/
│   │           └── SKILL.md     # Claude Code skill
│   └── codex/
│       └── AGENTS.md            # OpenAI Codex instructions
│
└── README.md
```

## License

MIT

## Credits

- [txtai](https://github.com/neuml/txtai) - AI-powered semantic search
- [sentence-transformers](https://www.sbert.net/) - Embedding models
- [uv](https://github.com/astral-sh/uv) - Fast Python package management
