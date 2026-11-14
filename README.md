# YewBuilder v1.0.0 — iOS app

Enter five files, tap **Build & Deploy**, and a Rust Yew/WASM site goes
live on your Hostek FTP host.

Bundle ID: `studio.mikegyver.yewbuilder` · iOS 17.0+ · SwiftUI ·
no third-party dependencies.

## The five files

| File | What it is |
| --- | --- |
| `index.html` | The page Trunk builds |
| `styles.css` | The look |
| `Cargo.toml` | What to build with |
| `Trunk.toml` | Build settings |
| `src/main.rs` | The app |

Each one has an editor in the Files tab (tap to edit, saves as you
type), plus **Import** from the Files app and **Load starter template**.
The starter is a minimal working Yew counter app, so Build works on
first launch with nothing typed.

## How Build works — read this first

An iPhone cannot run `cargo` or `trunk`: there is no Rust toolchain on
iOS. So Build is two steps, and the app is honest about it:

1. **Build on your builder server.** The phone sends the five files to
   a small server you run yourself (`server/server.py` — stdlib Python,
   no pip packages). That server runs `trunk build --release` and sends
   the finished `dist/` files back.
2. **Upload from the phone over FTP.** The phone uploads `dist/` to
   `ftp.mikegyver-studio.si` itself, with a plain-FTP client built into
   the app (PASV mode, binary — the `.wasm` file is never text-mangled).

## FTP settings (pre-filled)

- Host: `ftp.mikegyver-studio.si`
- Username: `itsmikeg@mikegyver-studio.si`
- Port: `21`
- Remote folder: `/` (site root — change to e.g. `/my-app` to deploy
  into a subfolder, live at `https://mikegyver-studio.si/my-app/`)

## FTP password — first time, then remembered

The first time you tap Build with no password saved, the app asks for
the FTP password. It is stored in the **iPhone Keychain** (not
UserDefaults, not a file, not the build log), and every later build
uses it without asking.

Re-entry is always available but optional: Settings → FTP password has
**Save password** (replace the saved one), **Forget saved password**,
and a **Remember password** toggle. Turn Remember off and the password
is used once for that build and not stored.

The builder server **never sees the password** — it only returns built
files. The password never leaves the phone.

Do not send the FTP password in chat or email. Enter it in the app,
on the phone, the first time.

## Builder server setup (do once, on your Windows PC)

PowerShell, in `server/`:

```powershell
winget install Rustlang.Rustup
# close and reopen PowerShell, then:
rustup default stable
rustup target add wasm32-unknown-unknown
cargo install trunk
powershell -ExecutionPolicy Bypass -File .\run-server.ps1
```

Then in the iPhone app: Settings → Builder server →
`http://<this-PC-LAN-IP>:8080` (find the IP with `ipconfig`, e.g.
`http://192.168.1.10:8080`). Tap **Test builder connection** — it
should report the trunk version. Windows Firewall will ask the first
time: allow Python on private networks.

Full server docs: `server/README.md`. Docker alternative included
(`server/Dockerfile`).

## Files

| File | What it does |
| --- | --- |
| `YewBuilder/YewBuilderApp.swift` | App entry point |
| `YewBuilder/ContentView.swift` | Files / Build / Settings tabs, Build flow, password sheet |
| `YewBuilder/FileEditorView.swift` | Plain-text editor for one file + Import |
| `YewBuilder/ProjectStore.swift` | The five files (Documents/YewBuilder/), settings, build log |
| `YewBuilder/Templates.swift` | Starter Yew project (all five files) |
| `YewBuilder/KeychainService.swift` | FTP password in the iOS Keychain only |
| `YewBuilder/BuilderService.swift` | POST /build + GET /health to your builder server |
| `YewBuilder/FTPClient.swift` | Plain-FTP uploader (BSD sockets, PASV, binary) |
| `YewBuilder/Info.plist` | Display name, `ITSAppUsesNonExemptEncryption = NO`, local-network HTTP allowed for your builder |
| `YewBuilder.xcodeproj/project.pbxproj` | Hand-written project, single app target (no XcodeGen) |
| `.github/workflows/testflight.yml` | GitHub Actions → fastlane → TestFlight (same proven pipeline as SSTV Studio / PodMix / Voyager) |
| `scripts/push-yewbuilder.ps1` | PowerShell push + tag script |
| `server/server.py` | Builder server (stdlib Python) |
| `server/run-server.ps1` | Windows starter with toolchain checks |
| `server/test-project/` | The starter project as files, for testing the server |

## Building locally

1. Open `YewBuilder.xcodeproj` in Xcode.
2. Select your development team under Signing & Capabilities (signing
   is Automatic; the bundle ID is already
   `studio.mikegyver.yewbuilder`).
3. Build and run on your iPhone — the simulator works for editing and
   for the builder step, but FTP to a real host is best tested on a
   device on the same network as your builder. For TestFlight, use
   `DEPLOYMENT-STEPS.md`.

## What I could not verify here

This was built on a Linux machine with no Xcode, so the iOS project
was **not compiled** here. The project file is internally consistent
(all IDs resolve, braces balanced), the icon set is complete (all 9
sizes + the 1024 marketing icon), and the Swift files are balanced —
but the first Xcode / Actions build is the real test. If it throws a
build error, paste it back and I will fix it the same turn.

The builder server **was** tested here: `GET /health` correctly
reports trunk/cargo missing on a machine without Rust, `POST /build`
with the starter project fails with a clear `command not found: trunk`
log, and a `../evil.rs` path is rejected. On a machine with Rust +
trunk installed, the same request builds and returns `dist/`.

## Changelog

- **v1.0.0** — First build. Five file editors + Import, Keychain FTP
  password (save once, reuse, re-enter or forget any time), Build =
  builder-server Trunk build + on-phone FTP upload, build log, Test
  builder / Test FTP login, TestFlight pipeline.
