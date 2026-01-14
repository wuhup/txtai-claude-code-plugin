---
description: Semantic vault search. Triggers on "search vault", "find in vault", "what do I have about", "notes on".
---

# Vault Search

`vs "query"` - semantic search over Obsidian vault (finds by meaning, not keywords).

```bash
vs "meeting notes from project planning"
vs "authentication ideas" -n 10    # more results
```

Returns: title, path, score, preview snippet.

**Maintenance:** `vault-search update` after adding notes, `vault-search serve` for faster repeated searches.
