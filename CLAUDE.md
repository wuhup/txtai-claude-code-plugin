# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**vs** is a lightweight, universal CLI tool for semantic search over document vaults using txtai AI embeddings. It finds notes by meaning, not just keywords.

### Design Philosophy

- **Search-only** - Claude handles file reading via Read tool
- **No MCP server** - avoid context bloat
- **Single vault focus** - no multi-collection complexity
- **Daemon-first** - fast searches on CPU-only hardware
- **Universal tool** - works standalone, with any AI, or scripted
- **AI integrations are opt-in** - only install what you use

## Commands

```bash
# Search (via installed wrapper)
vs "your query"                    # Semantic search (default action)
vs "query" -n 10                   # More results
vs "query" --json                  # JSON output for scripting
vs "query" --files                 # Paths only (for pipelines)
vs "query" --fast                  # Skip reranking (~5x faster)
vs "query" --min-score 0.5         # Filter low-relevance results

# Management
vs status                          # Index stats + daemon state
vs update                          # Incremental update
vs index                           # Full rebuild of search index
vs serve                           # Start daemon
vs stop                            # Stop daemon
vs config                          # Show config
vs config --vault PATH             # Set vault path

# Run script directly (development)
uv run --script scripts/vs.py <command>
```

## Architecture

### Repository Structure
```
vs/
├── scripts/
│   ├── vs.py                    # Core tool (universal)
│   ├── setup.sh                 # Interactive setup wizard
│
├── integrations/
│   ├── claude/
│   │   ├── SKILL.md             # Claude Code skill
│   │   └── plugin.json          # Minimal plugin manifest
│   └── codex/
│       └── AGENTS.md            # OpenAI Codex instructions
│
└── README.md                    # General documentation
```

### Installation Layout (after setup.sh)
```
~/.local/
  bin/
    vs                           # Shell wrapper (in PATH)
  share/
    vault-search/
      vs.py                      # Installed copy of main script
      config.json                # Configuration
      index/                     # Search index

# Optional AI integrations (user chooses location during setup):
~/.claude/plugins/vault-search/  # Global - or project's .claude/plugins/
  plugin.json
  SKILL.md
```

### Search Pipeline
1. **Hybrid search**: BM25 keyword matching + semantic embeddings via txtai
2. **Reranking**: Cross-encoder reranks top results for quality (skip with --fast)
3. **Daemon mode**: Unix socket server keeps models in memory for ~100ms searches vs ~5s cold start

### Models
- **Embeddings**: `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` (multilingual, 118M params)
- **Reranker**: `cross-encoder/ms-marco-MiniLM-L-6-v2`

### Data Locations
- Config: `~/.local/share/vault-search/config.json`
- Index: `~/.local/share/vault-search/index/`
- Socket: `~/.local/share/vault-search/.vault-search.sock`
- Setup marker: `~/.local/share/vault-search/.setup-complete`

### Design Decisions
- Single-file Python script using `uv run --script` with inline dependencies (no venv management)
- Daemon uses Unix socket for fast repeated searches
- Excludes `.git`, `.obsidian`, `.beads`, `.claude`, `node_modules`, `.trash` from indexing
- AI integrations are optional; Claude skill can be global or project-local

## Output Formats

The tool supports three output formats:

1. **Default (console)** - Human-readable with scores and snippets
2. **JSON (`--json`)** - Structured output for scripting
3. **Files (`--files`)** - Paths only, one per line for shell pipelines
