import Foundation
import SwiftUI

/// The five project files, in the order the user enters them.
enum ProjectFile: String, CaseIterable, Identifiable {
    case indexHtml = "index.html"
    case stylesCss = "styles.css"
    case cargoToml = "Cargo.toml"
    case trunkToml = "Trunk.toml"
    case mainRs = "src/main.rs"

    var id: String { rawValue }

    /// Short description shown in the file list.
    var subtitle: String {
        switch self {
        case .indexHtml: return "The page Trunk builds"
        case .stylesCss: return "The look"
        case .cargoToml: return "What to build with"
        case .trunkToml: return "Build settings"
        case .mainRs: return "The app"
        }
    }
}

/// Owns the five files, the deploy settings, and the build log.
///
/// Files persist as plain text in Documents/YewBuilder/ so they survive
/// app restarts and can be inspected in the Files app. Settings live in
/// UserDefaults. The FTP password is NOT here — see KeychainService.
/// Build progress, owned by the store (a class) so a background FTP
/// progress callback can update it — a SwiftUI View struct copy cannot.
enum BuildPhase: Equatable {
    case idle, building, uploading, done, failed
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published var contents: [ProjectFile: String] = [:]
    @Published var logLines: [String] = []
    @Published var buildPhase: BuildPhase = .idle
    @Published var buildStatus = "Ready."

    // MARK: - Settings (UserDefaults; no secrets here)

    @AppStorage("yewbuilder.builderURL") var builderURL = ""
    @AppStorage("yewbuilder.ftpHost") var ftpHost = "ftp.mikegyver-studio.si"
    @AppStorage("yewbuilder.ftpUsername") var ftpUsername = "itsmikeg@mikegyver-studio.si"
    @AppStorage("yewbuilder.ftpPort") var ftpPort = 21
    @AppStorage("yewbuilder.remotePath") var remotePath = "/"
    @AppStorage("yewbuilder.rememberPassword") var rememberPassword = true
    @AppStorage("yewbuilder.lastDeployURL") var lastDeployURL = ""

    var hasSavedPassword: Bool {
        KeychainService.hasPassword(account: ftpUsername)
    }

    var siteURL: String {
        // Remote path "/electron-lab" -> https://mikegyver-studio.si/electron-lab/
        let path = remotePath.trimmingCharacters(in: .whitespaces)
        if path.isEmpty || path == "/" { return "https://mikegyver-studio.si/" }
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return "https://mikegyver-studio.si/\(clean)/"
    }

    private var projectDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("YewBuilder", isDirectory: true)
    }

    init() {
        loadAll()
    }

    // MARK: - Files

    func content(for file: ProjectFile) -> String {
        contents[file] ?? Templates.content(for: file.rawValue)
    }

    func setContent(_ text: String, for file: ProjectFile) {
        contents[file] = text
        save(file: file)
    }

    func loadAll() {
        for file in ProjectFile.allCases {
            let url = projectDir.appendingPathComponent(file.rawValue)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                contents[file] = text
            } else {
                contents[file] = Templates.content(for: file.rawValue)
            }
        }
    }

    private func save(file: ProjectFile) {
        let url = projectDir.appendingPathComponent(file.rawValue)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try (contents[file] ?? "").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            log("Could not save \(file.rawValue): \(error.localizedDescription)")
        }
    }

    func resetFile(_ file: ProjectFile) {
        contents[file] = Templates.content(for: file.rawValue)
        save(file: file)
        log("Reset \(file.rawValue) to the starter template.")
    }

    func resetAll() {
        for file in ProjectFile.allCases { resetFile(file) }
    }

    /// The five files as the builder API expects them, in a fixed order.
    var buildFiles: [BuilderService.BuildFile] {
        ProjectFile.allCases.map {
            BuilderService.BuildFile(path: $0.rawValue, content: content(for: $0))
        }
    }

    // MARK: - Log

    func log(_ line: String) {
        let stamp = DateFormatter.logTime.string(from: Date())
        logLines.append("[\(stamp)] \(line)")
    }

    func clearLog() { logLines.removeAll() }
}

private extension DateFormatter {
    static let logTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
