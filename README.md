# vs - Lightweight Semantic Search

A universal command-line tool for semantic search over document vaults using [txtai](https://github.com/neuml/txtai) AI embeddings.

**Find notes by meaning, not just keywords.**

## Features

- **Semantic search** - finds documents by meaning, not just keyword matching
- **Hybrid search** - combines BM25 keywords + neural embeddings
- **Daemon mode** - keeps models in memory for ~100ms searches
- **Multiple output formats** - human-readable, JSON, or file paths only
- **Optional AI integrations** - Claude Code, OpenAI Codex, etc.

## Installation

### Interactive Setup (Recommended)

```bash
git clone https://github.com/wuhup/vault-search
cd vault-search
./scripts/setup.sh
```

The setup wizard will:
1. Configure your document path
2. Install `vs` to `~/.local/bin`
3. Optionally install AI integrations (Claude, Codex)
4. Download models (~500MB)
5. Build your search index
6. Start the daemon and verify

### One-Line Install

```bash
curl -sSL https://raw.githubusercontent.com/wuhup/vault-search/main/scripts/setup.sh | bash
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

The `vs` command works standalone, but you can install optional AI integrations:

### Claude Code

During setup, answer "y" to "Install Claude Code skill?" or manually:

```bash
mkdir -p .claude-plugin/skills/vault-search
cp integrations/claude/plugin.json .claude-plugin/
cp integrations/claude/SKILL.md .claude-plugin/skills/vault-search/
```

Then Claude can search your vault when you ask:
> "What do I have about project planning?"
> "Find my notes on authentication"

### OpenAI Codex

During setup, answer "y" to "Install OpenAI Codex AGENTS.md?" or manually:

```bash
cp integrations/codex/AGENTS.md ./AGENTS.md
```

## How It Works

### Hybrid Search
Combines BM25 keyword matching with semantic embeddings for best results.

### Models Used
- **Embeddings**: `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` (118M params, multilingual)
- **Reranker**: `cross-encoder/ms-marco-MiniLM-L-6-v2` (quality reranking)

### Daemon Mode
Run `vs serve` to keep models in memory:
- **Fast searches**: ~100ms vs ~5s cold start
- **Auto-updates**: Index refreshes every 60s

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
└── daemon.log         # Daemon logs
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
│   │   ├── SKILL.md             # Claude Code skill
│   │   └── plugin.json          # Plugin manifest
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
