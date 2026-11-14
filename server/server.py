#!/usr/bin/env python3
"""
YewBuilder builder server — stdlib only, no pip packages.

What it does
------------
Your iPhone cannot run cargo or trunk, so this little server does the
build for it:

  iPhone --POST /build {5 source files}--> this server
         --runs `trunk build --release`-->
  iPhone <--{dist/ files as base64 + build log}-- this server
  iPhone --FTP upload--> ftp.mikegyver-studio.si

The server NEVER sees your FTP password. It only builds. The phone
uploads to FTP itself, using the password from its Keychain.

Run it
-------
Windows (PowerShell), in this folder — needs Rust + trunk first:
  PS> winget install Rustlang.Rustup
  PS> rustup default stable
  PS> rustup target add wasm32-unknown-unknown
  PS> cargo install trunk
  PS> python server.py
  # listens on http://0.0.0.0:8080 — put that machine's LAN IP in the
  # iPhone app Settings, e.g. http://192.168.1.10:8080

  Or use run-server.ps1, which checks the tools first.

API
---
  GET  /health  -> {"ok": true, "trunk": "trunk 0.22.1", "cargo": "..."}
  POST /build   -> {"files": [{"path": "index.html", "content": "..."}, ...]}
                <- {"success": true, "log": "...",
                    "files": [{"path": "index.html", "content_base64": "..."}]}
  On build failure: {"success": false, "log": "<trunk output>", "files": []}
  On bad input: HTTP 400 with {"success": false, "log": "...", "files": []}
"""
import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# The only project paths the iPhone app sends. Anything else (notably
# ".." escapes) is rejected.
ALLOWED_PATHS = {"index.html", "styles.css", "Cargo.toml", "Trunk.toml", "src/main.rs"}
MAX_BODY_BYTES = 5 * 1024 * 1024
BUILD_TIMEOUT_SECONDS = 300


def run(cmd, cwd=None, timeout=30):
    """Run a command, return (returncode, combined stdout+stderr)."""
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout
        )
        return proc.returncode, (proc.stdout or "") + (proc.stderr or "")
    except FileNotFoundError:
        return 127, f"command not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {timeout}s: {' '.join(cmd)}"


def tool_version(cmd):
    code, out = run(cmd, timeout=15)
    if code != 0:
        return None
    return (out or "").strip().splitlines()[0] if out.strip() else None


def build_project(files):
    """Write the five files to a temp dir, run trunk, read dist/. Returns (success, log, built_files)."""
    log_lines = []
    tmp = Path(tempfile.mkdtemp(prefix="yewbuilder-"))
    try:
        for item in files:
            path = item.get("path", "")
            content = item.get("content", "")
            if path not in ALLOWED_PATHS:
                return False, f"Rejected path: {path!r}. Only {sorted(ALLOWED_PATHS)} are allowed.", []
            dest = tmp / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(content, encoding="utf-8")
            log_lines.append(f"wrote {path} ({len(content)} chars)")

        missing = ALLOWED_PATHS - {f.get("path") for f in files}
        if missing:
            return False, f"Missing files: {sorted(missing)}", []

        trunk_toml = (tmp / "Trunk.toml").read_text(encoding="utf-8", errors="ignore")
        if 'public_url = "./"' not in trunk_toml and 'public_url="./"' not in trunk_toml:
            log_lines.append("WARNING: Trunk.toml does not set public_url = \"./\" — "
                             "the built site may 404 in a subfolder. See README.md.")

        log_lines.append("running: trunk build --release")
        code, out = run(["trunk", "build", "--release"], cwd=str(tmp),
                        timeout=BUILD_TIMEOUT_SECONDS)
        log_lines.append(out)
        if code != 0:
            return False, "\n".join(log_lines), []

        dist = tmp / "dist"
        if not dist.is_dir():
            return False, "\n".join(log_lines) + "\nERROR: trunk exited 0 but no dist/ folder appeared.", []

        built = []
        for path in sorted(dist.rglob("*")):
            if path.is_file():
                rel = path.relative_to(dist).as_posix()
                built.append({
                    "path": rel,
                    "content_base64": base64.b64encode(path.read_bytes()).decode("ascii"),
                })
                log_lines.append(f"built {rel} ({path.stat().st_size} bytes)")
        if not built:
            return False, "\n".join(log_lines) + "\nERROR: dist/ is empty.", []
        return True, "\n".join(log_lines), built
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # keep stdout readable
        sys.stderr.write("[yewbuilder] " + fmt % args + "\n")

    def _send_json(self, status, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/health"):
            trunk = tool_version(["trunk", "--version"])
            cargo = tool_version(["cargo", "--version"])
            ok = trunk is not None and cargo is not None
            self._send_json(200 if ok else 503, {
                "ok": ok,
                "trunk": trunk,
                "cargo": cargo,
                "error": None if ok else "trunk and/or cargo not found on this machine — install Rust, add the wasm32 target, and `cargo install trunk`.",
            })
        else:
            self._send_json(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        if self.path != "/build":
            self._send_json(404, {"success": False, "log": "not found", "files": []})
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY_BYTES:
            self._send_json(400, {"success": False, "log": f"Bad Content-Length: {length}", "files": []})
            return
        try:
            payload = json.loads(self.rfile.read(length))
        except Exception as exc:
            self._send_json(400, {"success": False, "log": f"Invalid JSON: {exc}", "files": []})
            return
        files = payload.get("files")
        if not isinstance(files, list) or not files:
            self._send_json(400, {"success": False, "log": "Expected {\"files\": [...]} with the 5 project files.", "files": []})
            return
        success, log, built = build_project(files)
        self._send_json(200, {"success": success, "log": log, "files": built})


def main():
    port = int(os.environ.get("PORT", "8080"))
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    print(f"YewBuilder server on http://0.0.0.0:{port}  (trunk: {tool_version(['trunk', '--version'])})")
    print("POST /build with the 5 files; GET /health to check the toolchain.")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
