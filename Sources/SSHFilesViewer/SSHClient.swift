import Foundation

struct SSHError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct RunResult {
    let status: Int32
    let stdout: Data
    let stderr: Data
    var out: String { String(decoding: stdout, as: UTF8.self) }
    var err: String { String(decoding: stderr, as: UTF8.self) }
}

/// Thin, dependency-free SSH transport that drives the system `ssh` binary.
///
/// Uses OpenSSH connection multiplexing (ControlMaster/ControlPersist) so the
/// first command authenticates and every later command reuses the same socket.
/// This keeps listing, preview and download snappy and avoids re-authenticating.
final class SSHClient: @unchecked Sendable {
    let connection: Connection
    private let password: String?
    private let controlPath: String
    private let sshURL: URL

    init(connection: Connection, password: String?) {
        self.connection = connection
        self.password = password
        let token = String(connection.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(10)).lowercased()
        // Keep the socket path short — UNIX socket paths are capped near 104 bytes.
        self.controlPath = "/tmp/sshfv-\(token).sock"
        self.sshURL = SSHClient.locateSSH()
    }

    private static func locateSSH() -> URL {
        for path in ["/usr/bin/ssh", "/opt/homebrew/bin/ssh", "/usr/local/bin/ssh"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/usr/bin/ssh")
    }

    // MARK: Argument assembly

    private var target: String {
        let user = connection.username.trimmingCharacters(in: .whitespaces)
        return user.isEmpty ? connection.host : "\(user)@\(connection.host)"
    }

    private func baseOptions() -> [String] {
        var o: [String] = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=15",
            "-o", "ServerAliveInterval=20",
            "-o", "ServerAliveCountMax=3",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=180",
        ]
        if let port = connection.port { o += ["-p", "\(port)"] }
        switch connection.authMethod {
        case .agent:
            break
        case .key:
            if let id = connection.identityFile?.trimmingCharacters(in: .whitespaces), !id.isEmpty {
                o += ["-i", (id as NSString).expandingTildeInPath, "-o", "IdentitiesOnly=yes"]
            }
        case .password:
            o += ["-o", "NumberOfPasswordPrompts=1",
                  "-o", "PreferredAuthentications=password,keyboard-interactive",
                  "-o", "PubkeyAuthentication=no"]
        }
        return o
    }

    private func environment() -> [String: String]? {
        guard connection.authMethod == .password, let password else { return nil }
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = AskpassHelper.path()
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["SSHFV_PASSWORD"] = password
        if env["DISPLAY"] == nil { env["DISPLAY"] = ":0" }
        return env
    }

    /// Single-quote a string for safe interpolation into a remote shell command.
    static func q(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Process execution

    @discardableResult
    func run(_ remoteCommand: String) async throws -> RunResult {
        let args = baseOptions() + ["-T", "--", target, remoteCommand]
        return try await Self.exec(sshURL, args, environment())
    }

    private static func exec(_ url: URL, _ args: [String], _ env: [String: String]?) async throws -> RunResult {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RunResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = url
                p.arguments = args
                if let env { p.environment = env }
                let outPipe = Pipe()
                let errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError = errPipe
                p.standardInput = FileHandle.nullDevice
                do {
                    try p.run()
                } catch {
                    cont.resume(throwing: SSHError(message: "Could not launch ssh: \(error.localizedDescription)"))
                    return
                }
                // Drain both pipes concurrently so a large stream can't deadlock.
                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                group.enter()
                DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                p.waitUntilExit()
                group.wait()
                cont.resume(returning: RunResult(status: p.terminationStatus, stdout: outData, stderr: errData))
            }
        }
    }

    private func check(_ r: RunResult) throws {
        guard r.status != 0 else { return }
        let e = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
        throw SSHError(message: e.isEmpty ? "Remote command failed (exit \(r.status))." : e)
    }

    // MARK: High-level operations

    func homeDirectory() async throws -> String {
        let r = try await run("pwd")
        try check(r)
        let s = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "/" : s
    }

    func list(_ path: String) async throws -> [RemoteFile] {
        let r = try await run("cd -- \(Self.q(path)) && LC_ALL=C ls -la")
        try check(r)
        var files = LSParser.parse(r.out, parent: path)

        // Reclassify symlinks that resolve to directories so they look and
        // behave like regular folders (folder icon, double-click to enter).
        let symlinkNames = files.filter { $0.kind == .symlink }.map(\.name)
        if !symlinkNames.isEmpty {
            let dirLinks = (try? await directorySymlinks(in: path, names: symlinkNames)) ?? []
            if !dirLinks.isEmpty {
                files = files.map { file in
                    guard file.kind == .symlink, dirLinks.contains(file.name) else { return file }
                    var f = file
                    f.kind = .directory
                    return f
                }
                files.sort(by: LSParser.order)
            }
        }
        return files
    }

    /// Returns the subset of `names` (within `dir`) that resolve to directories
    /// — i.e. symlinks whose target is a directory. NUL-delimited for safety
    /// against odd filenames.
    private func directorySymlinks(in dir: String, names: [String]) async throws -> Set<String> {
        let quoted = names.map(Self.q).joined(separator: " ")
        let cmd = "cd -- \(Self.q(dir)) && for n in \(quoted); do "
            + "if [ -d \"./$n\" ]; then printf '%s\\0' \"$n\"; fi; done"
        let r = try await run(cmd)
        guard r.status == 0 else { return [] }
        let parts = r.stdout.split(separator: 0, omittingEmptySubsequences: true)
        return Set(parts.map { String(decoding: $0, as: UTF8.self) })
    }

    func isDirectory(_ path: String) async throws -> Bool {
        let r = try await run("if cd -- \(Self.q(path)) 2>/dev/null; then echo D; else echo F; fi")
        return r.out.contains("D")
    }

    /// Reads up to `maxBytes` of a remote file (used for inline previews).
    func readFile(_ path: String, maxBytes: Int) async throws -> Data {
        let r = try await run("head -c \(maxBytes) -- \(Self.q(path))")
        try check(r)
        return r.stdout
    }

    /// Overwrites a remote file with `data`, streamed over stdin. Writes in place
    /// (`cat > path`) so the file's existing permissions and ownership are kept.
    func writeFile(_ path: String, data: Data) async throws {
        let args = baseOptions() + ["-T", "--", target, "cat > \(Self.q(path))"]
        let r = try await Self.execWithInput(sshURL, args, environment(), stdin: data)
        try check(r)
    }

    private static func execWithInput(_ url: URL, _ args: [String], _ env: [String: String]?,
                                      stdin: Data) async throws -> RunResult {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RunResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = url
                p.arguments = args
                if let env { p.environment = env }
                let inPipe = Pipe()
                let outPipe = Pipe()
                let errPipe = Pipe()
                p.standardInput = inPipe
                p.standardOutput = outPipe
                p.standardError = errPipe
                do {
                    try p.run()
                } catch {
                    cont.resume(throwing: SSHError(message: "Could not launch ssh: \(error.localizedDescription)"))
                    return
                }
                // Feed stdin on a background queue so a full pipe buffer can't deadlock.
                DispatchQueue.global().async {
                    let handle = inPipe.fileHandleForWriting
                    handle.write(stdin)
                    try? handle.close()
                }
                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                group.enter()
                DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                p.waitUntilExit()
                group.wait()
                cont.resume(returning: RunResult(status: p.terminationStatus, stdout: outData, stderr: errData))
            }
        }
    }

    /// Streams a remote file to `localURL`, reporting fractional progress.
    func download(_ file: RemoteFile, to localURL: URL,
                  progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        try? fm.removeItem(at: localURL)
        guard fm.createFile(atPath: localURL.path, contents: nil),
              let fh = try? FileHandle(forWritingTo: localURL) else {
            throw SSHError(message: "Could not create local file at \(localURL.path).")
        }

        let args = baseOptions() + ["-T", "--", target, "cat -- \(Self.q(file.path))"]
        let p = Process()
        p.executableURL = sshURL
        p.arguments = args
        if let env = environment() { p.environment = env }
        p.standardOutput = fh
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice

        do {
            try p.run()
        } catch {
            try? fh.close()
            try? fm.removeItem(at: localURL)
            throw SSHError(message: "Could not launch ssh: \(error.localizedDescription)")
        }

        let total = Double(max(file.size, 1))
        while p.isRunning {
            let attrs = try? fm.attributesOfItem(atPath: localURL.path)
            let written = (attrs?[.size] as? NSNumber)?.doubleValue ?? 0
            progress(min(0.99, written / total))
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        p.waitUntilExit()
        try? fh.close()

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        if p.terminationStatus != 0 {
            try? fm.removeItem(at: localURL)
            let e = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHError(message: e.isEmpty ? "Download failed (exit \(p.terminationStatus))." : e)
        }
        progress(1.0)
    }

    /// Tears down the multiplexed master connection.
    func disconnect() async {
        let args = baseOptions() + ["-O", "exit", "--", target]
        _ = try? await Self.exec(sshURL, args, environment())
    }
}

// MARK: - Askpass helper

/// Writes a tiny askpass script that echoes the password from `$SSHFV_PASSWORD`.
/// Combined with `SSH_ASKPASS_REQUIRE=force` this lets us drive password auth
/// headlessly (no controlling TTY), without ever putting the password on a
/// command line.
enum AskpassHelper {
    static func path() -> String {
        let url = AppPaths.support.appendingPathComponent("askpass.sh")
        let script = "#!/bin/sh\nprintf '%s\\n' \"$SSHFV_PASSWORD\"\n"
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) || (try? String(contentsOf: url, encoding: .utf8)) != script {
            try? script.write(to: url, atomically: true, encoding: .utf8)
        }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }
}

// MARK: - `ls -la` parser

enum LSParser {
    static func parse(_ output: String, parent: String) -> [RemoteFile] {
        var files: [RemoteFile] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.isEmpty || line.hasPrefix("total ") { continue }
            guard let first = line.first, "dlbcps-".contains(first) else { continue }
            guard let entry = parseLine(line, parent: parent) else { continue }
            if entry.name == "." || entry.name == ".." { continue }
            files.append(entry)
        }
        return files.sorted(by: order)
    }

    /// Folders first, then case-insensitive by name.
    static func order(_ a: RemoteFile, _ b: RemoteFile) -> Bool {
        if a.isDirectory != b.isDirectory { return a.isDirectory }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    /// Parses one long-format line. Default `ls -la` produces:
    ///   mode links owner group size month day time/year name[ -> target]
    /// We read the first 8 whitespace fields and treat the remainder as the
    /// (space-preserving) name so filenames with spaces survive intact.
    private static func parseLine(_ line: String, parent: String) -> RemoteFile? {
        let mode0 = line.first!
        // Device files carry "major, minor" instead of a single size field,
        // pushing the name one field further right.
        let isDevice = (mode0 == "b" || mode0 == "c")
        let fieldCount = isDevice ? 9 : 8

        let (fields, rest) = splitFields(line, count: fieldCount)
        guard fields.count >= 5 else { return nil }

        let mode = fields[0]
        let size: Int64 = isDevice ? 0 : (Int64(fields[4]) ?? 0)
        let dateString = fields.count >= 8
            ? [fields[fields.count - 3], fields[fields.count - 2], fields[fields.count - 1]]
                .joined(separator: " ")
            : ""

        var name = rest
        var target: String?
        if mode0 == "l", let range = name.range(of: " -> ") {
            target = String(name[range.upperBound...])
            name = String(name[name.startIndex..<range.lowerBound])
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        if name.isEmpty { return nil }

        let kind: RemoteFile.Kind
        switch mode0 {
        case "d": kind = .directory
        case "l": kind = .symlink
        case "-": kind = .file
        default: kind = .other
        }

        return RemoteFile(
            name: name,
            path: RemotePath.join(parent, name),
            kind: kind,
            size: size,
            modified: dateString,
            permissions: mode,
            symlinkTarget: target
        )
    }

    /// Splits off the first `count` whitespace-delimited fields, returning them
    /// plus the untouched remainder (leading whitespace stripped).
    private static func splitFields(_ line: String, count: Int) -> (fields: [String], rest: String) {
        var fields: [String] = []
        var idx = line.startIndex
        func skipSpaces() {
            while idx < line.endIndex, line[idx] == " " || line[idx] == "\t" {
                idx = line.index(after: idx)
            }
        }
        for _ in 0..<count {
            skipSpaces()
            guard idx < line.endIndex else { break }
            let start = idx
            while idx < line.endIndex, line[idx] != " ", line[idx] != "\t" {
                idx = line.index(after: idx)
            }
            fields.append(String(line[start..<idx]))
        }
        skipSpaces()
        return (fields, String(line[idx...]))
    }
}
