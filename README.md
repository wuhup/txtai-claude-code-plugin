# txtai-claude-code-plugin

A Claude Code plugin for semantic search over Obsidian vaults using [txtai](https://github.com/neuml/txtai) AI embeddings.

**Find notes by meaning, not just keywords.**

## Installation

```bash
claude /install github:wuhup/txtai-claude-code-plugin
```

On first session start, the plugin checks whether setup is complete and prints
instructions if it is not.

Manual setup (required once):
1. Run `scripts/setup.sh` from the plugin directory
2. Installs [uv](https://github.com/astral-sh/uv) (if not present)
3. Downloads embedding models (~500MB)
4. Prompts for your vault path
5. Builds the search index

## Usage

### In Claude Code

Just ask Claude to search your vault:

> "What do I have about project planning?"
> "Find my notes on authentication"
> "Search for customer feedback"

Claude will use the `vs` command automatically.

### Direct Commands

```bash
# Search your vault
vs "your search query"
vs "project planning notes" -n 10    # More results

# Manage the index
vault-search update                   # After adding new notes
vault-search index                    # Full rebuild

# Daemon mode (faster repeated searches)
vault-search serve                    # Start daemon
vault-search stop                     # Stop daemon

# Configuration
vault-search config                   # Show current config
vault-search config --vault /path     # Set vault path
```

## How It Works

### Hybrid Search
Combines BM25 keyword matching with semantic embeddings for best results.

### Models Used
- **Embeddings**: `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` (118M params, multilingual)
- **Reranker**: `cross-encoder/ms-marco-MiniLM-L-6-v2` (quality reranking)

### Daemon Mode
For fast repeated searches, run `vault-search serve` to keep models in memory. Searches respond in ~100ms instead of ~5s cold start.

## Configuration

### Environment Variable
```bash
export VAULT_SEARCH_PATH="/path/to/your/vault"
```

### Config File
Settings are stored in `~/.local/share/vault-search/config.json`

### Data Location
- Index: `~/.local/share/vault-search/index/`
- Logs: `~/.local/share/vault-search/daemon.log`

## Requirements

- **Python 3.10+** (installed automatically via uv)
- **~500MB disk space** for models
- **Works on**: Linux, macOS

## Troubleshooting

### "Index not found"
Run `vault-search index` to build the initial index.

### Slow searches
Start the daemon: `vault-search serve`

### Out of date results
Update the index: `vault-search update`

### Change vault path
```bash
vault-search config --vault /new/path
vault-search index  # Rebuild for new vault
```

## License

MIT

## Credits

- [txtai](https://github.com/neuml/txtai) - AI-powered semantic search
- [sentence-transformers](https://www.sbert.net/) - Embedding models
- [uv](https://github.com/astral-sh/uv) - Fast Python package management
