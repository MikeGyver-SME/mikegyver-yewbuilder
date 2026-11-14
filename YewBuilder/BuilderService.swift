import Foundation

/// Talks to the YewBuilder builder server (see server/server.py).
///
/// Why a server at all: an iPhone cannot run cargo or trunk — there is no
/// Rust toolchain on iOS. So the phone sends the five source files to a
/// small server you run yourself (your Windows PC, a VPS, any machine with
/// Rust + trunk), the server runs `trunk build --release`, and it sends
/// the finished dist/ files back as base64. The phone then uploads those
/// files to FTP itself, so the FTP password never leaves the phone.
///
/// API:
///   GET  /health            -> {"ok": true, "trunk": "trunk 0.22.1"}
///   POST /build             -> {"files": [{"path","content"}]}
///                            <- {"success": bool, "log": "...",
///                                "files": [{"path","content_base64"}]}
enum BuilderService {
    struct BuildFile: Codable {
        let path: String
        let content: String
    }

    struct BuildRequest: Codable {
        let files: [BuildFile]
    }

    struct BuiltFile: Codable {
        let path: String
        let content_base64: String

        var data: Data? { Data(base64Encoded: content_base64) }
    }

    struct BuildResponse: Codable {
        let success: Bool
        let log: String
        let files: [BuiltFile]
    }

    struct HealthResponse: Codable {
        let ok: Bool
        let trunk: String?
        let error: String?
    }

    enum BuilderError: LocalizedError {
        case badURL(String)
        case httpStatus(Int, String)
        case noData
        case buildFailed(String)

        var errorDescription: String? {
            switch self {
            case .badURL(let u): return "Builder URL is not a valid http(s) URL: \(u)"
            case .httpStatus(let code, let body):
                return "Builder returned HTTP \(code). \(body.prefix(300))"
            case .noData: return "Builder returned no data."
            case .buildFailed(let log): return "Build failed:\n\(log)"
            }
        }
    }

    /// Normalise a user-typed builder address: add http:// when no scheme,
    /// strip a trailing slash.
    static func normalisedURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "http://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text)
    }

    static func checkHealth(baseURL: URL) async throws -> HealthResponse {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BuilderError.noData }
        guard (200..<300).contains(http.statusCode) else {
            throw BuilderError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    /// Send the five files, wait for the build (first builds can take a
    /// couple of minutes while cargo fetches crates), return dist/ files.
    static func build(baseURL: URL, files: [BuildFile]) async throws -> BuildResponse {
        let url = baseURL.appendingPathComponent("build")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300
        request.httpBody = try JSONEncoder().encode(BuildRequest(files: files))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BuilderError.noData }
        guard (200..<300).contains(http.statusCode) else {
            throw BuilderError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(BuildResponse.self, from: data)
        guard decoded.success else { throw BuilderError.buildFailed(decoded.log) }
        return decoded
    }
}
