# YewBuilder builder server

Stdlib-only Python. No pip packages. It receives the five source files
from the iPhone app, runs `trunk build --release`, and returns the
finished `dist/` files.

It never sees your FTP password — the phone uploads to FTP itself.

## Run on Windows (the usual path)

PowerShell, in this folder:

```powershell
winget install Rustlang.Rustup
# close and reopen PowerShell, then:
rustup default stable
rustup target add wasm32-unknown-unknown
cargo install trunk
powershell -ExecutionPolicy Bypass -File .\run-server.ps1
```

Then find this PC's LAN IP (`ipconfig`, look for IPv4 Address, e.g.
`192.168.1.10`) and put `http://192.168.1.10:8080` in the iPhone app
under Settings → Builder server. Test it there with "Test builder
connection" — it should report the trunk version.

Windows Firewall will ask the first time — allow Python on private
networks, or the phone cannot reach it.

## Run with Docker (VPS / any Linux host)

```bash
docker build -t yewbuilder-server .
docker run -p 8080:8080 yewbuilder-server
```

Then the builder URL is `http://<your-server-IP>:8080` (use https behind
a reverse proxy if it is on the public internet — the iPhone app sends
source code to it in plain text otherwise).

## API

- `GET /health` → `{"ok": true, "trunk": "trunk 0.22.1", "cargo": "..."}`
- `POST /build` with `{"files": [{"path": "index.html", "content": "..."}, ...], "deploy_path": "/public_html/my-app"}`
  → `{"success": true, "log": "...", "deploy_path": "/public_html/my-app", "files": [{"path": "index.html", "content_base64": "..."}]}`
  `deploy_path` is optional (older clients omit it; it defaults to
  `/`). The server validates it — `..` escapes, backslashes and NUL
  bytes are rejected with HTTP 400 — normalises it, logs it as
  `deploy target: ...`, and echoes it back. The phone uploads to
  exactly that echoed folder. The server itself never deploys
  anywhere; it only builds.

Only these five paths are accepted: `index.html`, `styles.css`,
`Cargo.toml`, `Trunk.toml`, `src/main.rs`. Anything else is rejected.

## test-project/

The same starter project the iPhone app ships with, as files on disk —
handy for testing the server without the phone:

```powershell
# from this folder, with the server running in another window:
python -c "import json,urllib.request,pathlib; files=[{'path':str(p.relative_to('test-project')).replace(chr(92),'/'),'content':p.read_text()} for p in pathlib.Path('test-project').rglob('*') if p.is_file()]; req=urllib.request.Request('http://127.0.0.1:8080/build', data=json.dumps({'files':files}).encode(), headers={'Content-Type':'application/json'}); print(urllib.request.urlopen(req, timeout=300).read().decode()[:2000])"
```

Without trunk installed the build step fails with a clear log line
("command not found: trunk") — that is the expected result on a machine
that has not run the setup above yet.
