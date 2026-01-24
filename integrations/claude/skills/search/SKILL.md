---
description: Semantic vault search. Triggers on "search vault", "find in vault", "what do I have about", "notes on".
---

# Vault Search

`vs "query"` - semantic search over your document vault (finds by meaning, not keywords).

```bash
vs "meeting notes from project planning"
vs "authentication ideas" -n 10    # more results
vs "query" --json                  # machine-readable output
vs "query" --files                 # paths only (for pipelines)
vs "query" --fast                  # skip reranking (~5x faster)
```

Returns: title, path, score, preview snippet.

**Output formats:**
- Default: Human-readable with scores and previews
- `--json`: Structured JSON for scripting
- `--files`: One path per line for shell pipelines

**Maintenance:**
- `vs update` - update index after adding notes
- `vs status` - check index stats and daemon state
- `vs serve` - start daemon for faster searches (~100ms vs ~5s)
