#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "txtai[pipeline]",
#     "sentence-transformers",
# ]
# ///
"""
Semantic search over an Obsidian vault using txtai.

Usage:
    vault-search search "query"       Search the vault
    vault-search search "query" -n 10 Return top 10 results
    vault-search serve                Start daemon (keeps models in memory)
    vault-search stop                 Stop daemon
    vault-search index                Build/rebuild the search index
    vault-search update               Update index with new/changed files
    vault-search config               Show current configuration
    vault-search config --vault PATH  Set vault path

Environment:
    VAULT_SEARCH_PATH    Path to vault (overrides config file)

Models:
    Embeddings: sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2
    Reranker: cross-encoder/ms-marco-MiniLM-L-6-v2 (daemon mode)
"""

import argparse
import hashlib
import json
import os
import signal
import socket
import stat
import sys
import time
from pathlib import Path

# ─────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────

DATA_DIR = Path.home() / ".local" / "share" / "vault-search"
CONFIG_FILE = DATA_DIR / "config.json"
INDEX_DIR = DATA_DIR / "index"
METADATA_FILE = INDEX_DIR / "file_hashes.json"
SOCKET_PATH = DATA_DIR / ".vault-search.sock"
PID_FILE = DATA_DIR / ".vault-search.pid"
SETUP_MARKER = DATA_DIR / ".setup-complete"

# Files/directories to exclude from indexing
EXCLUDE_PATTERNS = {
    ".git",
    ".obsidian",
    ".beads",
    ".claude",
    "node_modules",
    ".trash",
    ".txtai-index",
}

# Model configuration (multilingual, lightweight)
EMBEDDING_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
RERANKER_MODEL = "cross-encoder/ms-marco-MiniLM-L-6-v2"


def load_config() -> dict:
    """Load configuration from file."""
    if CONFIG_FILE.exists():
        try:
            return json.loads(CONFIG_FILE.read_text())
        except json.JSONDecodeError:
            pass
    return {}


def save_config(config: dict):
    """Save configuration to file."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(config, indent=2))


def get_vault_path() -> Path | None:
    """Get vault path from environment or config."""
    # Environment variable takes precedence
    env_path = os.environ.get("VAULT_SEARCH_PATH")
    if env_path:
        return Path(env_path).expanduser().resolve()

    # Fall back to config file
    config = load_config()
    if "vault_path" in config:
        return Path(config["vault_path"]).expanduser().resolve()

    return None


def require_vault_path() -> Path:
    """Get vault path or exit with error."""
    vault = get_vault_path()
    if not vault:
        print("Error: Vault path not configured.", file=sys.stderr)
        print("  Set with: vault-search config --vault /path/to/vault", file=sys.stderr)
        print("  Or set VAULT_SEARCH_PATH environment variable", file=sys.stderr)
        sys.exit(1)
    if not vault.exists():
        print(f"Error: Vault path does not exist: {vault}", file=sys.stderr)
        sys.exit(1)
    return vault


# ─────────────────────────────────────────────────────────────
# Indexing
# ─────────────────────────────────────────────────────────────

def get_markdown_files(vault_root: Path) -> list[Path]:
    """Get all markdown files in the vault, excluding certain directories."""
    files = []
    for md_file in vault_root.rglob("*.md"):
        if any(excl in md_file.parts for excl in EXCLUDE_PATTERNS):
            continue
        files.append(md_file)
    return files


def compute_file_hash(filepath: Path) -> str:
    """Compute MD5 hash of file contents."""
    return hashlib.md5(filepath.read_bytes()).hexdigest()


def load_file_hashes() -> dict:
    """Load cached file hashes."""
    if METADATA_FILE.exists():
        return json.loads(METADATA_FILE.read_text())
    return {}


def save_file_hashes(hashes: dict):
    """Save file hashes to metadata file."""
    INDEX_DIR.mkdir(parents=True, exist_ok=True)
    METADATA_FILE.write_text(json.dumps(hashes, indent=2))


def extract_document(filepath: Path, vault_root: Path) -> dict | None:
    """Extract document data for indexing."""
    try:
        content = filepath.read_text(encoding="utf-8")
    except Exception as e:
        print(f"  Warning: Could not read {filepath}: {e}", file=sys.stderr)
        return None

    rel_path = filepath.relative_to(vault_root)
    title = filepath.stem
    for line in content.split("\n"):
        if line.startswith("# "):
            title = line[2:].strip()
            break

    return {
        "id": str(rel_path),
        "text": content,
        "title": title,
        "path": str(rel_path),
    }


def create_embeddings():
    """Create txtai embeddings instance with hybrid search."""
    from txtai import Embeddings
    return Embeddings({
        "path": EMBEDDING_MODEL,
        "content": True,
        "hybrid": True,
    })


def create_reranker():
    """Create cross-encoder reranker pipeline."""
    from txtai.pipeline import CrossEncoder
    return CrossEncoder(RERANKER_MODEL)


def build_index(incremental: bool = False):
    """Build or update the search index."""
    vault_root = require_vault_path()

    print(f"{'Updating' if incremental else 'Building'} index for: {vault_root}")
    start = time.time()

    md_files = get_markdown_files(vault_root)
    print(f"  Found {len(md_files)} markdown files")

    old_hashes = load_file_hashes() if incremental else {}
    new_hashes = {}
    documents = []

    for filepath in md_files:
        file_key = str(filepath.relative_to(vault_root))
        current_hash = compute_file_hash(filepath)
        new_hashes[file_key] = current_hash

        if incremental and old_hashes.get(file_key) == current_hash:
            continue

        doc = extract_document(filepath, vault_root)
        if doc:
            documents.append(doc)

    if incremental and not documents:
        print("  No changes detected, index is up to date")
        return

    print(f"  Indexing {len(documents)} documents...")
    embeddings = create_embeddings()

    embeddings_path = INDEX_DIR / "embeddings"
    if incremental and embeddings_path.exists():
        embeddings.load(str(embeddings_path))
        embeddings.upsert([(d["id"], d, None) for d in documents])
    else:
        embeddings.index([(d["id"], d, None) for d in documents])

    INDEX_DIR.mkdir(parents=True, exist_ok=True)
    embeddings.save(str(embeddings_path))
    save_file_hashes(new_hashes)

    elapsed = time.time() - start
    print(f"  Done in {elapsed:.1f}s")
    print(f"  Index saved to {INDEX_DIR}")


# ─────────────────────────────────────────────────────────────
# Search
# ─────────────────────────────────────────────────────────────

def do_search(query: str, limit: int, rerank: bool, embeddings, reranker) -> list:
    """Perform search with pre-loaded models."""
    search_limit = limit * 2 if rerank else limit
    results = embeddings.search(query, limit=search_limit)

    if not results:
        return []

    if rerank and len(results) > 1 and reranker:
        texts = [r.get("text", "")[:1000] if isinstance(r, dict) else "" for r in results]
        scores = reranker(query, texts)
        ranked = sorted(zip(results, scores), key=lambda x: x[1], reverse=True)
        results = [r for r, _ in ranked[:limit]]
    else:
        results = results[:limit]

    return results


def format_results(query: str, results: list) -> str:
    """Format search results for display."""
    lines = [f"\n{'─' * 60}", f"Results for: {query}", f"{'─' * 60}\n"]

    for i, result in enumerate(results, 1):
        if isinstance(result, dict):
            path = result.get("path", result.get("id", "unknown"))
            title = result.get("title", Path(path).stem)
            score = result.get("score", 0)
            text = result.get("text", "")
        else:
            path = result[0] if len(result) > 0 else "unknown"
            score = result[1] if len(result) > 1 else 0
            title = Path(path).stem
            text = ""

        preview = text[:200].replace("\n", " ").strip() if text else ""
        if len(text) > 200:
            preview += "..."

        lines.append(f"{i}. {title}")
        lines.append(f"   📁 {path}")
        lines.append(f"   Score: {score:.3f}")
        if preview:
            lines.append(f"   {preview}")
        lines.append("")

    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────
# Daemon mode
# ─────────────────────────────────────────────────────────────

def daemon_running() -> bool:
    """Check if daemon is running."""
    if not PID_FILE.exists():
        return False
    try:
        pid = int(PID_FILE.read_text().strip())
        os.kill(pid, 0)  # Check if process exists
        return True
    except (ProcessLookupError, ValueError):
        PID_FILE.unlink(missing_ok=True)
        SOCKET_PATH.unlink(missing_ok=True)
        return False


def start_daemon():
    """Start the search daemon."""
    if daemon_running():
        print("Daemon already running")
        return

    embeddings_path = INDEX_DIR / "embeddings"
    if not embeddings_path.exists():
        print("Error: Index not found. Run 'vault-search index' first.", file=sys.stderr)
        sys.exit(1)

    # Fork to background
    pid = os.fork()
    if pid > 0:
        # Parent: wait briefly then confirm
        time.sleep(2)
        if daemon_running():
            print(f"Daemon started (PID {pid})")
        else:
            print("Daemon failed to start")
        return

    # Child: become daemon
    os.setsid()

    # Redirect stdout/stderr to log file (secure permissions)
    log_file = DATA_DIR / "daemon.log"
    fd = os.open(log_file, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    sys.stdout = os.fdopen(fd, "a")
    sys.stderr = sys.stdout

    # Write PID
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()))

    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Daemon starting...")

    # Load models
    embeddings = create_embeddings()
    embeddings.load(str(embeddings_path))
    reranker = create_reranker()

    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Models loaded, starting socket server...")

    # Create socket with secure permissions (owner-only access)
    SOCKET_PATH.unlink(missing_ok=True)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(str(SOCKET_PATH))
    os.chmod(SOCKET_PATH, stat.S_IRUSR | stat.S_IWUSR)  # 0600
    sock.listen(5)
    sock.settimeout(1.0)

    def cleanup(signum, frame):
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Daemon stopping...")
        SOCKET_PATH.unlink(missing_ok=True)
        PID_FILE.unlink(missing_ok=True)
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Daemon ready, listening on {SOCKET_PATH}")

    # Serve requests
    while True:
        try:
            conn, _ = sock.accept()
            data = conn.recv(4096).decode()
            req = json.loads(data)

            if req.get("cmd") == "search":
                results = do_search(
                    req["query"],
                    req.get("limit", 5),
                    req.get("rerank", True),
                    embeddings,
                    reranker
                )
                response = {"results": results}
            elif req.get("cmd") == "ping":
                response = {"status": "ok"}
            else:
                response = {"error": "unknown command"}

            conn.send(json.dumps(response).encode())
            conn.close()
        except socket.timeout:
            continue
        except Exception as e:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Error: {e}")
            continue


def stop_daemon():
    """Stop the search daemon."""
    if not daemon_running():
        print("Daemon not running")
        return

    pid = int(PID_FILE.read_text().strip())
    os.kill(pid, signal.SIGTERM)
    time.sleep(0.5)
    PID_FILE.unlink(missing_ok=True)
    SOCKET_PATH.unlink(missing_ok=True)
    print("Daemon stopped")


def query_daemon(query: str, limit: int, rerank: bool) -> list:
    """Send query to daemon."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(str(SOCKET_PATH))
    sock.send(json.dumps({
        "cmd": "search",
        "query": query,
        "limit": limit,
        "rerank": rerank
    }).encode())
    # Receive all data (responses can exceed 64KB buffer)
    chunks = []
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        chunks.append(chunk)
    sock.close()
    data = b"".join(chunks).decode()
    return json.loads(data).get("results", [])


def search(query: str, limit: int = 5, rerank: bool = True):
    """Search the vault, using daemon if available."""
    embeddings_path = INDEX_DIR / "embeddings"
    if not embeddings_path.exists():
        print("Error: Index not found. Run 'vault-search index' first.", file=sys.stderr)
        sys.exit(1)

    # Try daemon first
    if daemon_running():
        try:
            results = query_daemon(query, limit, rerank)
            print(format_results(query, results))
            return
        except Exception:
            pass  # Fall back to direct

    # Direct search (slow but works without daemon)
    embeddings = create_embeddings()
    embeddings.load(str(embeddings_path))
    reranker = create_reranker() if rerank else None
    results = do_search(query, limit, rerank, embeddings, reranker)
    print(format_results(query, results))


# ─────────────────────────────────────────────────────────────
# Configuration commands
# ─────────────────────────────────────────────────────────────

def show_config():
    """Show current configuration."""
    config = load_config()
    vault = get_vault_path()

    print("Current configuration:")
    print(f"  Config file: {CONFIG_FILE}")
    print(f"  Data directory: {DATA_DIR}")
    print(f"  Index directory: {INDEX_DIR}")
    print(f"  Vault path: {vault or '(not set)'}")
    print(f"  Setup complete: {SETUP_MARKER.exists()}")
    print(f"  Index exists: {(INDEX_DIR / 'embeddings').exists()}")
    print(f"  Daemon running: {daemon_running()}")


def set_vault_path(path: str):
    """Set the vault path in config."""
    resolved = Path(path).expanduser().resolve()
    if not resolved.exists():
        print(f"Warning: Path does not exist: {resolved}", file=sys.stderr)

    config = load_config()
    config["vault_path"] = str(resolved)
    save_config(config)
    print(f"Vault path set to: {resolved}")


# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Semantic search over an Obsidian vault",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Index commands
    subparsers.add_parser("index", help="Build/rebuild the full search index")
    subparsers.add_parser("update", help="Update index with new/changed files")

    # Daemon commands
    subparsers.add_parser("serve", help="Start daemon (keeps models in memory)")
    subparsers.add_parser("stop", help="Stop daemon")

    # Search command
    search_parser = subparsers.add_parser("search", help="Search the vault")
    search_parser.add_argument("query", help="Search query")
    search_parser.add_argument("-n", "--limit", type=int, default=5, help="Number of results")
    search_parser.add_argument("--no-rerank", action="store_true", help="Disable reranking")

    # Config command
    config_parser = subparsers.add_parser("config", help="Show or set configuration")
    config_parser.add_argument("--vault", metavar="PATH", help="Set vault path")

    args = parser.parse_args()

    if args.command == "index":
        build_index(incremental=False)
    elif args.command == "update":
        build_index(incremental=True)
    elif args.command == "serve":
        start_daemon()
    elif args.command == "stop":
        stop_daemon()
    elif args.command == "search":
        search(args.query, limit=args.limit, rerank=not args.no_rerank)
    elif args.command == "config":
        if args.vault:
            set_vault_path(args.vault)
        else:
            show_config()


if __name__ == "__main__":
    main()
