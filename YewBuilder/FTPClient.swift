import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Minimal plain-FTP client (PASV mode, binary) over BSD sockets.
///
/// Plain FTP on port 21 is what Hostek serves at ftp.mikegyver-studio.si,
/// and iOS ships no built-in FTP uploader, so this file is the uploader:
/// control connection for commands, one fresh data connection per file.
///
/// Only the phone ever holds the password: it is passed in from the
/// Keychain at Build time, used for this one session, and never logged
/// (log lines below never include the password).
///
/// Behaviour notes:
/// - Remote folders are created as needed (CWD, falling back to MKD).
/// - Every file goes up in binary mode (TYPE I) — a text-mode upload
///   would corrupt the .wasm file.
/// - Uploads are sequential on a background thread; the caller reports
///   progress after each file.
final class FTPClient {
    struct UploadProgress {
        let done: Int
        let total: Int
        let currentFile: String
    }

    enum FTPError: LocalizedError {
        case cannotResolve(String)
        case cannotConnect(String, Int)
        case timeout
        case unexpectedReply(String)
        case loginFailed(String)
        case uploadFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .cannotResolve(let h): return "Could not resolve FTP host \(h)."
            case .cannotConnect(let h, let p): return "Could not connect to \(h):\(p). Check the host and port, and that you are online."
            case .timeout: return "FTP timed out waiting for the server."
            case .unexpectedReply(let r): return "Unexpected FTP reply: \(r)"
            case .loginFailed(let r): return "FTP login failed: \(r) Check the username and password in Settings."
            case .uploadFailed(let f, let r): return "Upload of \(f) failed: \(r)"
            }
        }
    }

    let host: String
    let port: Int
    let username: String
    let password: String

    init(host: String, port: Int, username: String, password: String) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    // MARK: - Public API (blocking; call from a background task)

    /// Log in and immediately log out — proves host/user/password work
    /// without uploading anything.
    func testLogin() throws {
        let fd = try connectSocket(host: host, port: port)
        defer { close(fd) }
        let reader = SocketReader(fd: fd)
        let greeting = try reader.readResponse()
        guard greeting.code == 220 else { throw FTPError.unexpectedReply(greeting.text) }
        try login(reader: reader, fd: fd)
    }

    /// Upload files to `remoteDir` ("/" = site root, "/my-app" = subfolder).
    /// `files` are (path inside dist, data) pairs, e.g. ("index.html", ...).
    /// Calls `onProgress` after each file. Returns one log line per file.
    func upload(
        files: [(path: String, data: Data)],
        remoteDir: String,
        onProgress: ((UploadProgress) -> Void)? = nil
    ) throws -> [String] {
        let fd = try connectSocket(host: host, port: port)
        defer { close(fd) }
        let reader = SocketReader(fd: fd)
        let greeting = try reader.readResponse()
        guard greeting.code == 220 else { throw FTPError.unexpectedReply(greeting.text) }
        try login(reader: reader, fd: fd)

        let typeReply = try sendCommand(fd: fd, reader: reader, "TYPE I")
        guard typeReply.code == 200 else { throw FTPError.unexpectedReply(typeReply.text) }

        try ensureDirectory(fd: fd, reader: reader, remoteDir)

        var lines: [String] = []
        for (index, file) in files.enumerated() {
            onProgress?(UploadProgress(done: index, total: files.count, currentFile: file.path))
            try uploadOne(fd: fd, reader: reader, remotePath: file.path, data: file.data)
            lines.append("Uploaded \(file.path) (\(file.data.count) bytes)")
            onProgress?(UploadProgress(done: index + 1, total: files.count, currentFile: file.path))
        }
        _ = try? sendCommand(fd: fd, reader: reader, "QUIT")
        return lines
    }

    // MARK: - Session steps

    private func login(reader: SocketReader, fd: Int32) throws {
        let userReply = try sendCommand(fd: fd, reader: reader, "USER \(username)")
        guard userReply.code == 331 || userReply.code == 230 else {
            throw FTPError.loginFailed(userReply.text)
        }
        if userReply.code == 331 {
            let passReply = try sendCommand(fd: fd, reader: reader, "PASS \(password)")
            guard passReply.code == 230 else { throw FTPError.loginFailed(passReply.text) }
        }
    }

    /// Create the deploy folder if it does not exist yet, then leave the
    /// session sitting inside it, so every STOR after this lands there.
    /// Walks down one level at a time (MKD creates one level only).
    /// Whatever folder was entered is used as-is — no folder name is
    /// ever assumed or hardcoded here.
    private func ensureDirectory(fd: Int32, reader: SocketReader, _ dir: String) throws {
        let clean = dir.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != "/" else { return }
        let parts = clean.split(separator: "/").map(String.init)
        // Start from the account root. The reply is deliberately
        // ignored: if CWD / fails, carry on from wherever login left us
        // (on Hostek that is the account root) — a failed root step must
        // not fail a deploy that would otherwise work.
        _ = try sendCommand(fd: fd, reader: reader, "CWD /")
        for part in parts {
            let reply = try sendCommand(fd: fd, reader: reader, "CWD \(part)")
            if reply.code == 550 {
                // Missing level: create it, then step into it. MKD 550
                // means "already exists" (created between the two
                // commands) — also fine, just step in.
                let mk = try sendCommand(fd: fd, reader: reader, "MKD \(part)")
                guard mk.code == 257 || mk.code == 550 else {
                    throw FTPError.unexpectedReply(mk.text)
                }
                let again = try sendCommand(fd: fd, reader: reader, "CWD \(part)")
                guard again.code == 250 else { throw FTPError.unexpectedReply(again.text) }
            } else if reply.code != 250 {
                throw FTPError.unexpectedReply(reply.text)
            }
        }
    }

    private func uploadOne(fd: Int32, reader: SocketReader, remotePath: String, data: Data) throws {
        let pasv = try sendCommand(fd: fd, reader: reader, "PASV")
        guard pasv.code == 227, let (dataHost, dataPort) = parsePASV(pasv.text) else {
            throw FTPError.unexpectedReply(pasv.text)
        }
        let dataFD = try connectSocket(host: dataHost, port: dataPort)
        let stor = try sendCommand(fd: fd, reader: reader, "STOR \(remotePath)")
        guard stor.code == 150 || stor.code == 125 else {
            close(dataFD)
            throw FTPError.uploadFailed(remotePath, stor.text)
        }
        do {
            try sendAll(fd: dataFD, data: data)
        } catch {
            close(dataFD)
            throw error
        }
        // Close the data socket BEFORE reading the control reply: the
        // server only sends 226 once it sees EOF on the data connection.
        // No defer here — closing twice could close a reused fd number.
        close(dataFD)
        // The data socket is closed; the control socket now reports completion.
        let done = try reader.readResponse()
        guard done.code == 226 || done.code == 250 else {
            throw FTPError.uploadFailed(remotePath, done.text)
        }
    }

    // MARK: - Wire helpers

    private func sendCommand(fd: Int32, reader: SocketReader, _ command: String) throws -> (code: Int, text: String) {
        let line = command + "\r\n"
        guard let bytes = line.data(using: .utf8) else { throw FTPError.unexpectedReply(command) }
        try sendAll(fd: fd, data: bytes)
        return try reader.readResponse()
    }

    private func sendAll(fd: Int32, data: Data) throws {
        var sent = 0
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            while sent < data.count {
                let n = send(fd, base.advanced(by: sent), data.count - sent, 0)
                if n <= 0 { throw FTPError.timeout }
                sent += n
            }
        }
    }

    /// Parse "227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)".
    private func parsePASV(_ text: String) -> (String, Int)? {
        guard let open = text.firstIndex(of: "("),
              let close = text.firstIndex(of: ")") else { return nil }
        let parts = text[text.index(after: open)..<close].split(separator: ",").compactMap { Int($0) }
        guard parts.count == 6 else { return nil }
        let host = parts[0..<4].map(String.init).joined(separator: ".")
        let port = parts[4] * 256 + parts[5]
        return (host, port)
    }

    private func connectSocket(host: String, port: Int) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        let err = getaddrinfo(host, String(port), &hints, &res)
        guard err == 0, let first = res else { throw FTPError.cannotResolve(host) }
        defer { freeaddrinfo(res) }
        var fd: Int32 = -1
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let node = cursor {
            fd = socket(node.pointee.ai_family, node.pointee.ai_socktype, node.pointee.ai_protocol)
            if fd >= 0 {
                setTimeout(fd: fd, seconds: 30)
                if connect(fd, node.pointee.ai_addr, node.pointee.ai_addrlen) == 0 { break }
                close(fd)
                fd = -1
            }
            cursor = node.pointee.ai_next
        }
        guard fd >= 0 else { throw FTPError.cannotConnect(host, port) }
        return fd
    }

    private func setTimeout(fd: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        withUnsafePointer(to: &tv) { ptr in
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
        }
    }
}

/// Buffered line reader for one control socket. Handles multi-line
/// replies ("220-..." followed by "220 ...").
private final class SocketReader {
    private let fd: Int32
    private var buffer = Data()

    init(fd: Int32) { self.fd = fd }

    func readResponse() throws -> (code: Int, text: String) {
        var lines: [String] = []
        var code = 0
        while true {
            let line = try readLine()
            lines.append(line)
            let prefix = String(line.prefix(3))
            code = Int(prefix) ?? 0
            // "123 " ends the reply; "123-" means more lines follow.
            if line.count >= 4, line[line.index(line.startIndex, offsetBy: 3)] == " " { break }
            if line.count < 4 { break }
        }
        return (code, lines.joined(separator: "\n"))
    }

    private func readLine() throws -> String {
        while true {
            if let range = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                var line = String(data: lineData, encoding: .utf8) ?? ""
                if line.hasSuffix("\r") { line.removeLast() }
                return line
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { throw FTPClient.FTPError.timeout }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }
}
