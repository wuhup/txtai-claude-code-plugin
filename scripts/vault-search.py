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
import fcntl
import json
import os
import platform
import signal
import socket
import stat
import subprocess
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
LOCK_FILE = DATA_DIR / ".vault-search.lock"
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


def ensure_secure_dir(path: Path):
    """Create directory with secure permissions (0700) if it doesn't exist."""
    if not path.exists():
        path.mkdir(parents=True, exist_ok=True)
        os.chmod(path, 0o700)
    elif path.is_dir():
        # Ensure existing directory has secure permissions
        current_mode = path.stat().st_mode & 0o777
        if current_mode != 0o700:
            os.chmod(path, 0o700)


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
    ensure_secure_dir(DATA_DIR)
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
    vault_root_resolved = vault_root.resolve()
    for md_file in vault_root.rglob("*.md"):
        # Skip symlinks to prevent path traversal attacks
        if md_file.is_symlink():
            continue
        # Verify resolved path stays within vault (defense in depth)
        try:
            resolved = md_file.resolve()
            if not str(resolved).startswith(str(vault_root_resolved)):
                continue
        except (OSError, ValueError):
            continue
        if any(excl in md_file.parts for excl in EXCLUDE_PATTERNS):
            continue
        files.append(md_file)
    return files


def get_file_metadata(filepath: Path) -> dict:
    """Get file metadata (mtime + size) for change detection. Fast: no file read."""
    stat = filepath.stat()
    return {"mtime": stat.st_mtime, "size": stat.st_size}


def file_changed(filepath: Path, old_meta: dict | None) -> bool:
    """Check if file changed using mtime+size. Returns True if changed or new."""
    if old_meta is None:
        return True
    try:
        stat = filepath.stat()
        return stat.st_mtime != old_meta.get("mtime") or stat.st_size != old_meta.get("size")
    except OSError:
        return True


def load_file_metadata() -> dict:
    """Load cached file metadata."""
    if METADATA_FILE.exists():
        try:
            data = json.loads(METADATA_FILE.read_text())
            # Handle legacy hash-only format: migrate to new format
            if data and isinstance(next(iter(data.values()), None), str):
                return {}  # Force re-index on format change
            return data
        except (json.JSONDecodeError, StopIteration):
            pass
    return {}


def save_file_metadata(metadata: dict):
    """Save file metadata."""
    ensure_secure_dir(INDEX_DIR)
    METADATA_FILE.write_text(json.dumps(metadata))


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


def build_index(incremental: bool = False, embeddings=None):
    """Build or update the search index.

    Args:
        incremental: If True, only re-index changed files
        embeddings: Pre-loaded embeddings instance (from daemon). If None, loads fresh.

    Returns:
        dict with 'changed' and 'deleted' counts, or None on error
    """
    vault_root = get_vault_path()
    if not vault_root:
        msg = "Vault path not configured"
        print(f"Error: {msg}", file=sys.stderr)
        if embeddings is not None:
            # Called from daemon - don't exit, return error
            return {"error": msg}
        sys.exit(1)
    if not vault_root.exists():
        msg = f"Vault path does not exist: {vault_root}"
        print(f"Error: {msg}", file=sys.stderr)
        if embeddings is not None:
            return {"error": msg}
        sys.exit(1)
    if not vault_root.is_dir():
        msg = f"Vault path is not a directory: {vault_root}"
        print(f"Error: {msg}", file=sys.stderr)
        if embeddings is not None:
            return {"error": msg}
        sys.exit(1)

    print(f"{'Updating' if incremental else 'Building'} index for: {vault_root}")
    start = time.time()

    md_files = get_markdown_files(vault_root)
    print(f"  Found {len(md_files)} markdown files")

    old_metadata = load_file_metadata() if incremental else {}
    new_metadata = {}
    documents = []
    current_files = set()

    for filepath in md_files:
        file_key = str(filepath.relative_to(vault_root))
        current_files.add(file_key)

        # Fast check: only read file if mtime or size changed
        if incremental and not file_changed(filepath, old_metadata.get(file_key)):
            new_metadata[file_key] = old_metadata[file_key]
            continue

        doc = extract_document(filepath, vault_root)
        if doc:
            documents.append(doc)
            new_metadata[file_key] = get_file_metadata(filepath)

    # Detect deleted files
    deleted = set(old_metadata.keys()) - current_files if incremental else set()

    if incremental and not documents and not deleted:
        print("  No changes detected, index is up to date")
        return {"changed": 0, "deleted": 0}

    print(f"  Indexing {len(documents)} changed, {len(deleted)} deleted")

    # Use provided embeddings or load fresh
    embeddings_provided = embeddings is not None
    if not embeddings_provided:
        embeddings = create_embeddings()

    embeddings_path = INDEX_DIR / "embeddings"
    if incremental and embeddings_path.exists():
        if not embeddings_provided:
            embeddings.load(str(embeddings_path))
        if documents:
            embeddings.upsert([(d["id"], d, None) for d in documents])
        if deleted:
            for doc_id in deleted:
                try:
                    embeddings.delete([doc_id])
                except Exception:
                    pass  # Already gone
    else:
        embeddings.index([(d["id"], d, None) for d in documents])

    ensure_secure_dir(INDEX_DIR)
    embeddings.save(str(embeddings_path))
    save_file_metadata(new_metadata)

    elapsed = time.time() - start
    print(f"  Done in {elapsed:.1f}s")
    print(f"  Index saved to {INDEX_DIR}")

    return {"changed": len(documents), "deleted": len(deleted)}


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

    # Acquire exclusive lock to prevent race condition on startup
    ensure_secure_dir(DATA_DIR)
    lock_fd = os.open(LOCK_FILE, os.O_WRONLY | os.O_CREAT, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(lock_fd)
        print("Another process is starting the daemon")
        return

    # Fork to background
    pid = os.fork()
    if pid > 0:
        # Parent: wait briefly then confirm, release lock
        time.sleep(2)
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)
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
    ensure_secure_dir(DATA_DIR)
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

    # Auto-update settings
    UPDATE_INTERVAL = 60  # seconds between update checks
    last_update = time.time()

    # Serve requests
    while True:
        conn = None
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
            elif req.get("cmd") == "update":
                # Manual update request
                result = build_index(incremental=True, embeddings=embeddings)
                if result and "error" not in result:
                    response = {"status": "ok", **result}
                else:
                    response = {
                        "status": "error",
                        "error": (result or {}).get("error", "update failed"),
                    }
            else:
                response = {"error": "unknown command"}

            conn.send(json.dumps(response).encode())
        except socket.timeout:
            # Check if it's time for periodic update
            now = time.time()
            if now - last_update >= UPDATE_INTERVAL:
                last_update = now
                try:
                    result = build_index(incremental=True, embeddings=embeddings)
                    if result and (result["changed"] > 0 or result["deleted"] > 0):
                        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Auto-update: {result['changed']} changed, {result['deleted']} deleted")
                except Exception as e:
                    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Auto-update error: {e}")
            continue
        except Exception as e:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Error: {e}")
        finally:
            if conn:
                try:
                    conn.close()
                except Exception:
                    pass


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
    sock.settimeout(30.0)  # Prevent indefinite hang if daemon crashes
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


def update_via_daemon() -> dict | None:
    """Send update request to daemon. Returns result dict or None if failed."""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(300.0)  # Updates can take a while for large vaults
        sock.connect(str(SOCKET_PATH))
        sock.send(json.dumps({"cmd": "update"}).encode())
        chunks = []
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
        sock.close()
        return json.loads(b"".join(chunks).decode())
    except Exception:
        return None


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
    print(f"  Autostart: {'enabled' if autostart_enabled() else 'disabled'}")


def set_vault_path(path: str):
    """Set the vault path in config."""
    resolved = Path(path).expanduser().resolve()
    if not resolved.exists():
        print(f"Error: Path does not exist: {resolved}", file=sys.stderr)
        sys.exit(1)
    if not resolved.is_dir():
        print(f"Error: Path is not a directory: {resolved}", file=sys.stderr)
        sys.exit(1)

    config = load_config()
    config["vault_path"] = str(resolved)
    save_config(config)
    print(f"Vault path set to: {resolved}")


# ─────────────────────────────────────────────────────────────
# Autostart management
# ─────────────────────────────────────────────────────────────

# Service file paths
LAUNCHD_PLIST = Path.home() / "Library" / "LaunchAgents" / "com.vault-search.daemon.plist"
SYSTEMD_SERVICE = Path.home() / ".config" / "systemd" / "user" / "vault-search.service"


def _is_macos() -> bool:
    """Check if running on macOS."""
    return platform.system() == "Darwin"


def autostart_enabled() -> bool:
    """Check if autostart is enabled."""
    if _is_macos():
        return LAUNCHD_PLIST.exists()
    else:
        return SYSTEMD_SERVICE.exists()


def enable_autostart():
    """Enable daemon autostart on login."""
    script_path = str(Path(__file__).resolve())

    if _is_macos():
        # macOS: launchd plist
        LAUNCHD_PLIST.parent.mkdir(parents=True, exist_ok=True)

        plist_content = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vault-search.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>export PATH="$HOME/.local/bin:$PATH"; uv run --script "{script_path}" serve</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>{DATA_DIR}/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>{DATA_DIR}/launchd.log</string>
</dict>
</plist>
'''
        LAUNCHD_PLIST.write_text(plist_content)
        subprocess.run(["launchctl", "load", str(LAUNCHD_PLIST)], capture_output=True)
        print("Autostart enabled (launchd)")
        print("  Daemon will start on next login, or run: launchctl start com.vault-search.daemon")

    else:
        # Linux: systemd user service
        SYSTEMD_SERVICE.parent.mkdir(parents=True, exist_ok=True)

        service_content = f'''[Unit]
Description=Vault Search Daemon
After=network.target

[Service]
Type=simple
Environment="PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/bin/bash -c 'uv run --script "{script_path}" serve'
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
'''
        SYSTEMD_SERVICE.write_text(service_content)
        subprocess.run(["systemctl", "--user", "daemon-reload"], capture_output=True)
        subprocess.run(["systemctl", "--user", "enable", "vault-search.service"], capture_output=True)
        subprocess.run(["systemctl", "--user", "start", "vault-search.service"], capture_output=True)
        print("Autostart enabled (systemd)")
        print("  Daemon started and will start on login")


def disable_autostart():
    """Disable daemon autostart."""
    if _is_macos():
        if LAUNCHD_PLIST.exists():
            subprocess.run(["launchctl", "unload", str(LAUNCHD_PLIST)], capture_output=True)
            LAUNCHD_PLIST.unlink()
            print("Autostart disabled (launchd)")
        else:
            print("Autostart was not enabled")
    else:
        if SYSTEMD_SERVICE.exists():
            subprocess.run(["systemctl", "--user", "stop", "vault-search.service"], capture_output=True)
            subprocess.run(["systemctl", "--user", "disable", "vault-search.service"], capture_output=True)
            SYSTEMD_SERVICE.unlink()
            subprocess.run(["systemctl", "--user", "daemon-reload"], capture_output=True)
            print("Autostart disabled (systemd)")
        else:
            print("Autostart was not enabled")


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

    # Autostart command
    autostart_parser = subparsers.add_parser("autostart", help="Enable/disable daemon autostart on login")
    autostart_group = autostart_parser.add_mutually_exclusive_group(required=True)
    autostart_group.add_argument("--enable", action="store_true", help="Enable autostart")
    autostart_group.add_argument("--disable", action="store_true", help="Disable autostart")

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
        # Use daemon if running (fast, no model reload)
        if daemon_running():
            print("Updating via daemon...")
            result = update_via_daemon()
            if result and result.get("status") == "ok":
                print(f"  {result.get('changed', 0)} changed, {result.get('deleted', 0)} deleted")
            else:
                if result and result.get("error") == "unknown command":
                    print("  Daemon is outdated, restarting...")
                    stop_daemon()
                    try:
                        start_daemon()
                    except SystemExit:
                        pass
                    if daemon_running():
                        result = update_via_daemon()
                        if result and result.get("status") == "ok":
                            print(f"  {result.get('changed', 0)} changed, {result.get('deleted', 0)} deleted")
                            return
                print("  Daemon update failed, falling back to direct update")
                build_index(incremental=True)
        else:
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
    elif args.command == "autostart":
        if args.enable:
            enable_autostart()
        else:
            disable_autostart()


if __name__ == "__main__":
    main()
