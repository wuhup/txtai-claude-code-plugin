# Vault Search

The `vs` command provides semantic search over the user's document vault. It finds notes by meaning, not just keywords.

## Available Commands

```bash
# Search
vs "query"                 # Search (default action)
vs "query" --json          # JSON output for parsing
vs "query" --files         # Paths only, one per line
vs "query" -n 10           # Return more results
vs "query" --fast          # Skip reranking (~5x faster)
vs "query" --min-score 0.5 # Filter low-relevance results

# Maintenance
vs status                  # Show index stats and daemon state
vs update                  # Update index with new/changed files
vs index                   # Full rebuild of search index

# Daemon (for faster searches)
vs serve                   # Start daemon
vs stop                    # Stop daemon
```

## Output Formats

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

## Usage Guidelines

1. **Start with search** - use `vs "query"` to find relevant notes
2. **Read files directly** - after finding paths, read them with your file tools
3. **Use JSON for processing** - when you need to parse results programmatically
4. **Use files for pipelines** - when piping paths to other commands

## When to Use

- User asks about their notes/documents
- Looking for related content in the vault
- Finding context for a topic before writing
- Searching for specific information the user has documented
