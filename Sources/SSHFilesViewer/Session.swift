import Foundation
import SwiftUI

// MARK: - Download tracking

@MainActor
final class DownloadItem: ObservableObject, Identifiable {
    enum State: Equatable {
        case running
        case completed
        case failed(String)
    }

    let id = UUID()
    let fileName: String
    let destination: URL
    @Published var progress: Double = 0
    @Published var state: State = .running

    init(fileName: String, destination: URL) {
        self.fileName = fileName
        self.destination = destination
    }
}

// MARK: - Browser session

/// Owns one live connection and its browsing state. One per saved connection,
/// created lazily and cached by `AppModel`.
@MainActor
final class BrowserSession: ObservableObject {
    let connection: Connection

    @Published var status: ConnState = .disconnected
    @Published var path: String = ""
    @Published var entries: [RemoteFile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var downloads: [DownloadItem] = []

    private(set) var homePath: String = "/"
    private var back: [String] = []
    private var forward: [String] = []
    private var client: SSHClient?

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }
    var activeClient: SSHClient? { client }

    init(connection: Connection) {
        self.connection = connection
    }

    // MARK: Connection lifecycle

    func connect() async {
        guard status != .connecting, status != .connected else { return }
        status = .connecting
        errorMessage = nil

        let password = connection.authMethod == .password
            ? Keychain.get(account: connection.id.uuidString)
            : nil
        let c = SSHClient(connection: connection, password: password)
        client = c

        do {
            let start: String
            if let ip = connection.initialPath?.trimmingCharacters(in: .whitespaces), !ip.isEmpty {
                start = ip
            } else {
                start = try await c.homeDirectory()
            }
            let files = try await c.list(start)
            homePath = start
            path = start
            entries = files
            back = []
            forward = []
            status = .connected
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func disconnect() async {
        if let c = client { await c.disconnect() }
        client = nil
        status = .disconnected
        entries = []
        back = []
        forward = []
    }

    // MARK: Navigation

    private func load(_ newPath: String, record: Bool) async {
        guard let c = client else { return }
        isLoading = true
        errorMessage = nil
        do {
            let files = try await c.list(newPath)
            if record, !path.isEmpty, newPath != path {
                back.append(path)
                forward.removeAll()
            }
            path = newPath
            entries = files
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func navigate(to newPath: String) async { await load(newPath, record: true) }
    func refresh() async { await load(path, record: false) }
    func goUp() async { await load(RemotePath.parent(path), record: true) }
    func goHome() async { await load(homePath, record: true) }

    func goBack() async {
        guard let p = back.popLast() else { return }
        forward.append(path)
        await load(p, record: false)
    }

    func goForward() async {
        guard let p = forward.popLast() else { return }
        back.append(path)
        await load(p, record: false)
    }

    enum Activation {
        case entered
        case preview(RemoteFile)
    }

    /// Double-click / open behaviour: enter directories (and dir symlinks),
    /// otherwise hand the file back for preview.
    func activate(_ file: RemoteFile) async -> Activation {
        switch file.kind {
        case .directory:
            await navigate(to: file.path)
            return .entered
        case .symlink:
            if let c = client, (try? await c.isDirectory(file.path)) == true {
                await navigate(to: file.path)
                return .entered
            }
            return .preview(file)
        case .file, .other:
            return .preview(file)
        }
    }

    // MARK: Editing

    /// Writes new contents to a remote file. Throws on failure.
    func save(_ file: RemoteFile, contents: String) async throws {
        guard let c = client else { throw SSHError(message: "Not connected.") }
        try await c.writeFile(file.path, data: Data(contents.utf8))
    }

    // MARK: Downloads

    @discardableResult
    func download(_ file: RemoteFile, openAfter: Bool = false, saveTo: URL? = nil) async -> URL? {
        guard let c = client else { return nil }

        let dest: URL
        if let saveTo {
            dest = saveTo
        } else if openAfter {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("SSHFilesViewer-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            dest = tmp.appendingPathComponent(file.name)
        } else {
            dest = Self.uniqueURL(in: Self.downloadDirectory(), name: file.name)
        }

        let item = DownloadItem(fileName: file.name, destination: dest)
        if !openAfter { downloads.insert(item, at: 0) }

        do {
            try await c.download(file, to: dest) { fraction in
                Task { @MainActor in item.progress = fraction }
            }
            item.progress = 1
            item.state = .completed
            return dest
        } catch {
            item.state = .failed(error.localizedDescription)
            if openAfter { downloads.insert(item, at: 0) } // surface the failure
            return nil
        }
    }

    static func downloadDirectory() -> URL {
        if let s = UserDefaults.standard.string(forKey: "downloadDirectory"), !s.isEmpty {
            return URL(fileURLWithPath: (s as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static func uniqueURL(in dir: URL, name: String) -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var candidate = dir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 1
        while fm.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            i += 1
        }
        return candidate
    }
}

// MARK: - App model

@MainActor
final class AppModel: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var selection: Connection.ID?
    @Published var isPresentingEditor = false
    @Published var editingConnection: Connection?

    private var sessions: [Connection.ID: BrowserSession] = [:]

    init() {
        connections = ConnectionStore.load()
    }

    var selectedConnection: Connection? {
        connections.first { $0.id == selection }
    }

    func session(for connection: Connection) -> BrowserSession {
        if let existing = sessions[connection.id] { return existing }
        let session = BrowserSession(connection: connection)
        sessions[connection.id] = session
        return session
    }

    // MARK: Editing

    func beginAddConnection() {
        editingConnection = nil
        isPresentingEditor = true
    }

    func beginEdit(_ connection: Connection) {
        editingConnection = connection
        isPresentingEditor = true
    }

    func save(_ connection: Connection, password: String?) {
        if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[idx] = connection
            // Reset any live session so changes take effect on next open.
            if let session = sessions[connection.id] {
                Task { await session.disconnect() }
                sessions[connection.id] = nil
            }
        } else {
            connections.append(connection)
        }
        if connection.authMethod == .password {
            if let password, !password.isEmpty {
                Keychain.set(password, account: connection.id.uuidString)
            }
        } else {
            Keychain.delete(account: connection.id.uuidString)
        }
        ConnectionStore.save(connections)
        selection = connection.id
    }

    func delete(_ connection: Connection) {
        connections.removeAll { $0.id == connection.id }
        if let session = sessions[connection.id] {
            Task { await session.disconnect() }
        }
        sessions[connection.id] = nil
        Keychain.delete(account: connection.id.uuidString)
        if selection == connection.id { selection = nil }
        ConnectionStore.save(connections)
    }
}
