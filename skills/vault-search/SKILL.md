---
description: >
  Semantic search over an Obsidian vault using AI embeddings. Use when the user asks about content in their vault, wants to find notes on a topic, or needs to locate information that keyword search would miss. Triggers on: "search vault", "find in vault", "what do I have about", "notes on", "vault search", semantic questions about vault content.
---

# Vault Semantic Search

Use `vs "query"` to search the user's Obsidian vault semantically. This finds notes by meaning, not just keywords.

## When to Use

- User asks about topics in their vault ("What do I have about X?")
- User wants to find notes related to a concept
- User needs to locate information that simple grep/search would miss
- Working in an Obsidian vault context and need to find relevant notes

## Command

```bash
vs "your search query"
```

Options:
- `-n 10` - Return more results (default: 5)

## Examples

```bash
# Find notes about a topic
vs "meeting notes from project planning"

# Search for concepts
vs "authentication implementation ideas"

# Find related content
vs "customer feedback about pricing" -n 10
```

## Output

Returns ranked results with:
- Note title
- File path
- Relevance score
- Preview snippet

## Notes

- First run triggers one-time setup (downloads models, ~500MB)
- Uses hybrid search (BM25 + semantic embeddings)
- Results are reranked for quality
- Run `vault-search serve` to keep models in memory for faster repeated searches
- Run `vault-search update` after adding new notes to update the index
