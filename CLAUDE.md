# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Claude Code plugin** that provides semantic search over Obsidian vaults using txtai AI embeddings. It finds notes by meaning, not just keywords.

## Commands

```bash
# Search (quick wrapper)
vs "your query"                    # Semantic search
vs "query" -n 10                   # More results

# Full vault-search CLI
vault-search search "query"        # Search the vault
vault-search index                 # Full rebuild of search index
vault-search update                # Incremental update
vault-search serve                 # Start daemon (keeps models in memory)
vault-search stop                  # Stop daemon
vault-search config                # Show config
vault-search config --vault PATH   # Set vault path

# Run the main script directly
uv run --script scripts/vault-search.py <command>
```

## Architecture

### Plugin Structure
```
.claude-plugin/plugin.json    # Plugin manifest
hooks/hooks.json              # SessionStart hook → init-check.sh
skills/vault-search/SKILL.md  # Skill definition for Claude
scripts/
  vault-search.py             # Core Python implementation (single-file)
  vs.sh                       # Quick search wrapper
  setup.sh                    # First-time setup wizard
  init-check.sh               # Checks if setup is complete
```

### Search Pipeline
1. **Hybrid search**: BM25 keyword matching + semantic embeddings via txtai
2. **Reranking**: Cross-encoder reranks top results for quality
3. **Daemon mode**: Unix socket server keeps models in memory for ~100ms searches vs ~5s cold start

### Models
- **Embeddings**: `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` (multilingual, 118M params)
- **Reranker**: `cross-encoder/ms-marco-MiniLM-L-6-v2`

### Data Locations
- Config: `~/.local/share/vault-search/config.json`
- Index: `~/.local/share/vault-search/index/`
- Socket: `~/.local/share/vault-search/.vault-search.sock`
- Setup marker: `~/.local/share/vault-search/.setup-complete-v1`

### Design Decisions
- Single-file Python script using `uv run --script` with inline dependencies (no venv management)
- Daemon uses Unix socket for fast repeated searches
- Excludes `.git`, `.obsidian`, `.beads`, `.claude`, `node_modules`, `.trash` from indexing
