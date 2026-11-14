import SwiftUI

/// YewBuilder — enter five files, tap Build, ship a Yew/WASM site to FTP.
///
/// Flow (see README.md for the why):
///   1. The five source files go to your builder server, which runs
///      `trunk build --release` and sends the finished dist/ files back.
///      An iPhone cannot run cargo/trunk, so there is no on-device build.
///   2. This phone uploads dist/ to ftp.mikegyver-studio.si over FTP.
///      The password comes from the Keychain and never leaves the phone.
struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore

    @State private var showPasswordSheet = false
    @State private var sheetPassword = ""
    @State private var sheetRemember = true
    @State private var showSiteConfirm = false

    var body: some View {
        TabView {
            filesTab
                .tabItem { Label("Files", systemImage: "doc.text") }
            buildTab
                .tabItem { Label("Build", systemImage: "hammer") }
            settingsTab
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .sheet(isPresented: $showPasswordSheet) {
            passwordSheet
        }
    }

    // MARK: - Files tab

    private var filesTab: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ProjectFile.allCases) { file in
                        NavigationLink(destination: FileEditorView(file: file)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.rawValue).font(.headline)
                                Text(file.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                Text("\(store.content(for: file).count) characters")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Project files — tap one to edit")
                } footer: {
                    Text("Files save as you type, and stay on this phone. Import pastes a whole file from the Files app; Load starter restores the working example.")
                }
                Section {
                    Button("Reset all five files to the starter") {
                        store.resetAll()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("YewBuilder")
        }
    }

    // MARK: - Build tab

    private var buildTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Build & deploy")
                            .font(.title2).bold()
                        Text("Builds the five files with Trunk, then uploads the finished site to FTP.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            row("Builder", store.builderURL.isEmpty ? "Not set — see Settings" : store.builderURL)
                            row("FTP", "\(store.ftpUsername) @ \(store.ftpHost):\(store.ftpPort)")
                            row("Password", store.hasSavedPassword ? "Saved on this phone" : "Not saved yet")
                            row("Live site", store.siteURL)
                        }
                        .font(.subheadline)
                    }

                    // Deploy folder — editable here, per build, not just in
                    // Settings. Whatever is entered here is the folder THIS
                    // build goes to; it is saved as the default for next
                    // time. Nothing is hardcoded: the first build went to
                    // /public_html/yew-builder only because that is what
                    // was typed in. Missing folders are created on the
                    // server automatically, and a leading public_html is
                    // dropped from the Live site link (it is the web root).
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deploy folder (FTP)")
                            .font(.subheadline).bold()
                        TextField("/public_html/my-app", text: $store.remotePath)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 15, design: .monospaced))
                        Text("Each build uses whatever is entered here. / = site root. Folders that do not exist yet are created for you.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Button(action: startBuild) {
                        HStack {
                            Image(systemName: "hammer.fill")
                            Text(store.buildPhase == .building ? "Building…" : store.buildPhase == .uploading ? "Uploading…" : "Build & Deploy")
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(store.buildPhase == .building || store.buildPhase == .uploading ? Color.gray : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(store.buildPhase == .building || store.buildPhase == .uploading)

                    Text(store.buildStatus)
                        .font(.subheadline)
                        .foregroundStyle(store.buildPhase == .failed ? .red : .secondary)

                    if store.buildPhase == .done {
                        Button("Open live site") {
                            if let url = URL(string: store.siteURL) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    GroupBox("Build log") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                if store.logLines.isEmpty {
                                    Text("No builds yet. The log shows each step here.")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    ForEach(store.logLines.indices, id: \.self) { i in
                                        Text(store.logLines[i])
                                            .font(.system(size: 12, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 180)
                    }

                    Button("Clear log") { store.clearLog() }
                        .font(.footnote)
                }
                .padding()
            }
            .navigationTitle("Build")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Settings tab

    private var settingsTab: some View {
        NavigationStack {
            Form {
                Section("Builder server") {
                    TextField("http://192.168.1.10:8080", text: $store.builderURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                    Text("The machine that runs server.py (your Windows PC or a VPS). It needs Rust + trunk. See the README in the zip.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Test builder connection") { Task { await testBuilder() } }
                        .disabled(store.builderURL.isEmpty)
                }

                Section("FTP — Hostek") {
                    TextField("Host", text: $store.ftpHost)
                        .autocapitalization(.none).disableAutocorrection(true)
                    TextField("Username", text: $store.ftpUsername)
                        .autocapitalization(.none).disableAutocorrection(true)
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("21", value: $store.ftpPort, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Remote folder (/ = site root)", text: $store.remotePath)
                        .autocapitalization(.none).disableAutocorrection(true)
                    Text("Example: /my-app deploys to mikegyver-studio.si/my-app/. On Hostek, /public_html is the web root, so /public_html/my-app links to the same place — the app drops public_html from the link, but still uploads there.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("FTP password") {
                    Text(store.hasSavedPassword
                         ? "Saved on this phone (Keychain). Builds use it without asking."
                         : "Not saved yet. Enter it once below, or tap Build and you will be asked.")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField("FTP password", text: $sheetPassword)
                    Toggle("Remember password on this phone", isOn: $store.rememberPassword)
                    HStack {
                        Button("Save password") { savePasswordFromSettings() }
                            .disabled(sheetPassword.isEmpty)
                        Spacer()
                        Button("Forget saved password", role: .destructive) {
                            KeychainService.delete(account: store.ftpUsername)
                            store.log("Saved FTP password removed from Keychain.")
                            store.objectWillChange.send()
                        }
                        .disabled(!store.hasSavedPassword)
                    }
                    Button("Test FTP login") { Task { await testFTP() } }
                        .disabled(!store.hasSavedPassword)
                }

                Section("About") {
                    Text("YewBuilder v1.0.0 · MikeGyver Studio\nBuilds Yew/WASM with Trunk on your builder server, then uploads over FTP. The FTP password stays in the iPhone Keychain and is never sent to the builder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Password sheet (first build, or password never saved)

    private var passwordSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter the FTP password for \(store.ftpUsername). It is saved in the iPhone Keychain, and future builds will use it without asking. Re-entry stays available in Settings any time.")
                        .font(.subheadline)
                    SecureField("FTP password", text: $sheetPassword)
                    Toggle("Remember on this phone", isOn: $sheetRemember)
                }
                Section {
                    Button("Build & Deploy") {
                        let password = sheetPassword
                        let remember = sheetRemember
                        sheetPassword = ""
                        showPasswordSheet = false
                        Task { await performBuild(password: password, savePassword: remember) }
                    }
                    .disabled(sheetPassword.isEmpty)
                    Button("Cancel", role: .cancel) { showPasswordSheet = false }
                }
            }
            .navigationTitle("FTP password")
        }
    }

    // MARK: - Build flow

    private func startBuild() {
        guard let builderURL = BuilderService.normalisedURL(store.builderURL) else {
            store.buildStatus = "Set the builder server address in Settings first."
            store.log("Build stopped: no builder URL.")
            return
        }
        _ = builderURL
        if let saved = KeychainService.load(account: store.ftpUsername) {
            Task { await performBuild(password: saved, savePassword: false) }
        } else {
            sheetRemember = store.rememberPassword
            showPasswordSheet = true
        }
    }

    private func performBuild(password: String, savePassword: Bool) async {
        guard let builderURL = BuilderService.normalisedURL(store.builderURL) else { return }
        store.buildPhase = .building
        store.buildStatus = "Sending files to the builder…"
        store.clearLog()
        store.log("Build started. Builder: \(builderURL.absoluteString)")
        store.log("Deploy target: \(store.ftpUsername) @ \(store.ftpHost):\(store.ftpPort)\(store.remotePath)")

        if savePassword && store.rememberPassword {
            if KeychainService.save(password: password, account: store.ftpUsername) {
                store.log("FTP password saved in Keychain.")
            } else {
                store.log("Warning: could not save the FTP password — this build still uses it once.")
            }
        } else if savePassword {
            store.log("Password used once (Remember is off).")
        }

        do {
            // Step 1 — build on the server. The deploy folder goes with
            // the request: the server validates and normalises it and
            // echoes it back, and this build uploads to exactly that
            // echoed folder — whatever was entered on the Build tab.
            let response = try await BuilderService.build(
                baseURL: builderURL, files: store.buildFiles,
                deployPath: store.remotePath)
            store.log("Build succeeded. Server log:")
            for line in response.log.split(separator: "\n") { store.log(String(line)) }
            store.log("Built \(response.files.count) files.")
            if let echoed = response.deployPath, !echoed.isEmpty, echoed != store.remotePath {
                store.remotePath = echoed
                store.log("Deploy folder normalised to \(echoed).")
            }
            store.log("Deploying to \(store.remotePath) — folders that do not exist yet will be created.")

            // Step 2 — upload from this phone over FTP.
            store.buildPhase = .uploading
            store.buildStatus = "Uploading to FTP…"
            let built: [(path: String, data: Data)] = response.files.compactMap { file in
                guard let data = file.data else { return nil }
                return (file.path, data)
            }
            guard !built.isEmpty else { throw BuildFlowError.emptyBuild }
            let client = FTPClient(host: store.ftpHost, port: store.ftpPort,
                                   username: store.ftpUsername, password: password)
            let remoteDir = store.remotePath
            let uploaded = try await Task.detached(priority: .userInitiated) {
                try client.upload(files: built, remoteDir: remoteDir) { progress in
                    Task { @MainActor in
                        store.buildStatus = "Uploading \(progress.currentFile) (\(progress.done)/\(progress.total))…"
                    }
                }
            }.value
            for line in uploaded { store.log(line) }

            store.buildPhase = .done
            store.buildStatus = "Deployed. Live at \(store.siteURL)"
            store.lastDeployURL = store.siteURL
            store.log("Done. Live at \(store.siteURL)")
        } catch {
            store.buildPhase = .failed
            store.buildStatus = error.localizedDescription
            store.log("FAILED: \(error.localizedDescription)")
        }
    }

    private func savePasswordFromSettings() {
        guard !sheetPassword.isEmpty else { return }
        if KeychainService.save(password: sheetPassword, account: store.ftpUsername) {
            store.log("FTP password saved in Keychain.")
            store.buildStatus = "Password saved."
        } else {
            store.log("Could not save the FTP password.")
        }
        sheetPassword = ""
        store.objectWillChange.send()
    }

    private func testBuilder() async {
        guard let url = BuilderService.normalisedURL(store.builderURL) else {
            store.buildStatus = "Enter a builder URL first."
            return
        }
        store.buildStatus = "Checking builder…"
        do {
            let health = try await BuilderService.checkHealth(baseURL: url)
            store.buildStatus = health.ok
                ? "Builder OK (\(health.trunk ?? "trunk version unknown"))."
                : "Builder answered but reported: \(health.error ?? "unknown error")"
            store.log("Builder check: \(store.buildStatus)")
        } catch {
            store.buildStatus = "Builder check failed: \(error.localizedDescription)"
            store.log("Builder check failed: \(error.localizedDescription)")
        }
    }

    private func testFTP() async {
        guard let password = KeychainService.load(account: store.ftpUsername) else {
            store.buildStatus = "Save the FTP password first."
            return
        }
        store.buildStatus = "Testing FTP login…"
        let client = FTPClient(host: store.ftpHost, port: store.ftpPort,
                               username: store.ftpUsername, password: password)
        do {
            try await Task.detached(priority: .userInitiated) { try client.testLogin() }.value
            store.buildStatus = "FTP login OK."
            store.log("FTP login test OK.")
        } catch {
            store.buildStatus = "FTP login failed: \(error.localizedDescription)"
            store.log("FTP login test failed: \(error.localizedDescription)")
        }
    }

    enum BuildFlowError: LocalizedError {
        case emptyBuild
        var errorDescription: String? {
            "The builder returned no files. Check the build log above."
        }
    }
}
