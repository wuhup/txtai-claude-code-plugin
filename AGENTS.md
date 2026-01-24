# Repository Guidelines

## Project Structure & Module Organization
- `scripts/vs.py` is the single-file Python CLI runtime.
- `scripts/setup.sh` is the interactive setup wizard (installs `vs` wrapper).
- `integrations/claude/` contains the Claude Code skill (`SKILL.md`) and plugin manifest (`plugin.json`).
- `integrations/codex/AGENTS.md` documents the Codex instructions.
- There is no dedicated `tests/` directory; validation is currently manual.

## Build, Test, and Development Commands
- `scripts/setup.sh` — first-time setup; installs `uv`, downloads models, prompts for vault path, and builds the index.
- `uv run --script scripts/vs.py <command>` — run the CLI directly (e.g., `search`, `index`, `serve`).
- `vs "query"` — convenience wrapper for `vs search`.
- `vs serve` / `vs stop` — start/stop the daemon for faster repeated searches.

## Coding Style & Naming Conventions
- Python uses 4-space indentation, type hints, and short docstrings; keep the `#!/usr/bin/env -S uv run --script` header intact.
- Favor small, focused functions and explicit constants (see `DATA_DIR`, `SOCKET_PATH`, etc.).
- Bash scripts use `#!/bin/bash`, `set -e`, and clear step-by-step sections.
- Command names and subcommands are lowercase (e.g., `vault-search index`, `vault-search update`).

## Testing Guidelines
- No automated test framework is configured.
- Manual smoke checks: `vs config`, `vs index`, and `vs search "query"`.
- If touching daemon behavior, also validate `vs serve` and `vs stop`.

## Commit & Pull Request Guidelines
- Commit messages in history are short, imperative sentences (e.g., “Harden daemon update handling”).
- PRs should include a concise summary, the commands run for manual validation, and note any changes to setup/model downloads.
- Link related issues when applicable; screenshots are not required for this CLI-centric project.

## Security & Configuration Tips
- Local state lives in `~/.local/share/vault-search/`; avoid committing personal paths or config examples with real vault locations.
- Use `VAULT_SEARCH_PATH` for overrides instead of hardcoding paths in code.
