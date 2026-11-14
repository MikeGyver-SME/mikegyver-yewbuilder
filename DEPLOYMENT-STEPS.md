# YewBuilder — deployment steps (v1.0.0)

Same proven pipeline as SSTV Studio / PodMix / Voyager Light-Day.
Do each step once, in order.

## 1. Apple — App ID and App Store Connect record first

The workflow fails without these, even with everything else in place.

1. developer.apple.com → Certificates, Identifiers & Profiles →
   Identifiers → App IDs → App, Explicit bundle ID
   `studio.mikegyver.yewbuilder`, no capabilities, Register.
2. appstoreconnect.apple.com → Apps → New App → iOS, name `YewBuilder`,
   SKU `yewbuilder`, bundle ID `studio.mikegyver.yewbuilder`.
   Full App Store listing details (screenshots, description, privacy,
   pricing) are NOT needed for TestFlight internal testing.

## 2. GitHub — repo and secrets

1. Create the repo `MikeGyver-SME/mikegyver-yewbuilder` on GitHub
   (empty, no README — the push script fills it).
2. Repo → Settings → Secrets and variables → Actions → New repository
   secret, four secrets (same ones the other apps use):
   - `ASC_KEY_ID` — App Store Connect API key ID
   - `ASC_ISSUER_ID` — Issuer ID (UUID from the API key page)
   - `ASC_KEY_P8` — Full contents of the downloaded `AuthKey_XXXX.p8` file
   - `TEAM_ID` — Apple Developer Team ID

## 3. Push + tag (PowerShell on Windows)

```powershell
# Extract yewbuilder-v1.0.0.zip first (E:\Downloads is the default).
powershell -ExecutionPolicy Bypass -File .\scripts\push-yewbuilder.ps1
# uses defaults, tags v1.0.0
```

The tag push starts the "Build and upload YewBuilder to TestFlight"
workflow automatically. Watch it at
`https://github.com/MikeGyver-SME/mikegyver-yewbuilder/actions`.

Per the iOS pre-flight checklist: the push script uses `git status`
(never a failing probe) and `git tag --list` to check for the tag, and
tags only after the push lands. If a run fails, check the workflow log
for the step name before changing code — a missing step means the push
did not trigger the pipeline you think it did.

## 4. TestFlight

1. When the workflow is green, App Store Connect → TestFlight → iOS —
   the build appears within minutes. If it sits at Missing Compliance,
   answer "None of the algorithms mentioned above" (the app implements
   no encryption of its own; it only uses standard HTTPS + Keychain).
2. Install from TestFlight on your iPhone, accept the invite if needed.

## 5. First launch on the phone (the part only you can do)

1. Start the builder server on your Windows PC first:
   `server/run-server.ps1` (see `server/README.md`). Note the PC's LAN IP.
2. In the app: Settings → Builder server →
   `http://<PC-LAN-IP>:8080` → **Test builder connection** (should show
   the trunk version).
3. Settings → FTP: host, username and port are pre-filled. Set Remote
   folder to `/` for the site root, or e.g. `/my-app` for a subfolder.
4. Tap the **Build** tab → **Build & Deploy**. The first time, it asks
   for the FTP password — enter it there, on the phone. It saves to the
   Keychain, so later builds do not ask again.
5. Watch the build log. On success it prints the live URL — tap
   **Open live site** to check it in Safari.

If the build step fails, the log shows the trunk output from the
server — paste that back and the fix is usually in the five files
(Cargo.toml / main.rs) or in the server setup, not in the app.
