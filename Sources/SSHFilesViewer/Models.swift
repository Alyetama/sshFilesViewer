import Foundation

// MARK: - Connection

enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case agent
    case key
    case password

    var id: String { rawValue }
    var label: String {
        switch self {
        case .agent: return "SSH Agent"
        case .key: return "Private Key"
        case .password: return "Password"
        }
    }
}

/// A saved remote machine. Passwords are *not* stored here — they live in the
/// Keychain keyed by `id`.
struct Connection: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int? = nil
    var username: String = ""
    var authMethod: AuthMethod = .agent
    var identityFile: String? = nil
    var initialPath: String? = nil

    /// A user-friendly subtitle, e.g. "alice@example.com:2222".
    var displayDestination: String {
        var s = username.trimmingCharacters(in: .whitespaces).isEmpty ? host : "\(username)@\(host)"
        if let port { s += ":\(port)" }
        return s
    }

    var isValid: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty }
}

// MARK: - Remote files

struct RemoteFile: Identifiable, Hashable {
    enum Kind: Hashable {
        case directory
        case file
        case symlink
        case other
    }

    var name: String
    var path: String
    var kind: Kind
    var size: Int64
    var modified: String
    var permissions: String
    var symlinkTarget: String?

    var id: String { path }
    var isDirectory: Bool { kind == .directory }
}

// MARK: - Connection state

enum ConnState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

// MARK: - Remote path helpers

enum RemotePath {
    static func join(_ base: String, _ name: String) -> String {
        if base.isEmpty { return name }
        if base == "/" { return "/" + name }
        if base.hasSuffix("/") { return base + name }
        return base + "/" + name
    }

    static func parent(_ path: String) -> String {
        if path == "/" || path.isEmpty { return "/" }
        var p = path
        if p.hasSuffix("/") { p.removeLast() }
        guard let idx = p.lastIndex(of: "/") else { return "/" }
        if idx == p.startIndex { return "/" }
        return String(p[p.startIndex..<idx])
    }

    /// Breadcrumb segments as (label, absolutePath) pairs, always starting at root.
    static func segments(_ path: String) -> [(label: String, path: String)] {
        var result: [(String, String)] = [("/", "/")]
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var acc = ""
        for part in parts {
            acc += "/" + part
            result.append((part, acc))
        }
        return result
    }
}
