import SwiftUI
import AppKit

// MARK: - File icon styling

enum FileIcon {
    static let directoryColor = Color(red: 0.27, green: 0.53, blue: 0.98)

    /// Media / archive categories shown as SF Symbols (symbol, color).
    /// Returns nil for everything else, which is drawn as a colored extension badge.
    static func mediaSymbol(forExtension ext: String) -> (symbol: String, color: Color)? {
        if imageExts.contains(ext) { return ("photo.fill", .purple) }
        if audioExts.contains(ext) { return ("music.note", .pink) }
        if videoExts.contains(ext) { return ("film.fill", .indigo) }
        if archiveExts.contains(ext) { return ("archivebox.fill", .orange) }
        if ext == "pdf" { return ("doc.richtext.fill", .red) }
        return nil
    }

    /// Brand color (as a hex) for a file-type badge. Unknown extensions get a
    /// neutral gray so every file type still gets a distinct, readable chip.
    static func badgeHex(forExtension ext: String) -> UInt32 {
        switch ext {
        case "py", "pyw", "pyi":               return 0x3776AB // python blue
        case "js", "mjs", "cjs":               return 0xF7DF1E // js yellow
        case "jsx":                            return 0x61DAFB // react cyan
        case "ts":                             return 0x3178C6 // ts blue
        case "tsx":                            return 0x3178C6
        case "swift":                          return 0xF05138 // swift orange
        case "rb", "gemfile", "erb":           return 0xCC342D // ruby red
        case "go":                             return 0x00ADD8 // go cyan
        case "rs":                             return 0xB7410E // rust
        case "java", "jar":                    return 0xE76F00 // java orange
        case "kt", "kts":                      return 0x7F52FF // kotlin purple
        case "c", "h":                         return 0x5C6BC0
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx", "m", "mm": return 0x00599C // c++ blue
        case "cs":                             return 0x68217A // c# purple
        case "php":                            return 0x777BB4 // php purple
        case "sh", "bash", "zsh", "fish":      return 0x4EAA25 // shell green
        case "sql":                            return 0x336791 // postgres blue
        case "json", "jsonc":                  return 0xCBCB41
        case "yaml", "yml":                    return 0xCB171E
        case "toml", "ini", "cfg", "conf", "env": return 0x6E6E6E
        case "html", "htm", "xhtml":           return 0xE34F26 // html orange
        case "xml", "svg", "plist":            return 0x0060AC
        case "vue":                            return 0x41B883
        case "css":                            return 0x1572B6
        case "scss", "sass":                   return 0xCC6699
        case "less":                           return 0x1D365D
        case "md", "markdown", "rst":          return 0x4A7EBB
        case "lua":                            return 0x000080
        case "r":                              return 0x198CE7
        case "pl", "pm":                       return 0x0298C3
        case "dart":                           return 0x00B4AB
        case "scala":                          return 0xC22D40
        case "clj", "cljs", "edn":             return 0x5881D8
        case "ex", "exs":                      return 0x6E4A7E // elixir purple
        case "csv", "tsv":                     return 0x217346 // sheet green
        case "txt", "log", "text":             return 0x8E8E93
        default:                               return 0x6B7280 // neutral gray
        }
    }

    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "webp", "icns", "ico"]
    static let archiveExts: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst", "lz", "z"]
    static let audioExts: Set<String> = ["mp3", "wav", "flac", "aac", "ogg", "m4a", "aiff", "wma"]
    static let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "webm", "m4v", "wmv", "flv", "mpg", "mpeg"]
}

// MARK: - Language logos (devicon, MIT)

/// Loads bundled language logo SVGs from Contents/Resources/lang-icons and maps
/// file extensions to them. Returns nil for extensions without a logo so the
/// caller can fall back to a colored badge.
enum LanguageLogo {
    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func image(for ext: String) -> NSImage? {
        guard let name = assetName(for: ext) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "lang-icons"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }

    /// Maps a file extension to a devicon asset basename.
    static func assetName(for ext: String) -> String? {
        switch ext {
        case "py", "pyw", "pyi":               return "python"
        case "js", "mjs", "cjs":               return "javascript"
        case "ts":                             return "typescript"
        case "jsx", "tsx":                     return "react"
        case "swift":                          return "swift"
        case "rb", "erb", "gemfile":           return "ruby"
        case "go":                             return "go"
        case "rs":                             return "rust"
        case "java", "jar":                    return "java"
        case "kt", "kts":                      return "kotlin"
        case "c", "h":                         return "c"
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx": return "cplusplus"
        case "cs":                             return "csharp"
        case "php":                            return "php"
        case "sh", "bash", "zsh", "fish":      return "bash"
        case "sql":                            return "postgresql"
        case "html", "htm", "xhtml":           return "html5"
        case "vue":                            return "vuejs"
        case "css":                            return "css3"
        case "scss", "sass":                   return "sass"
        case "md", "markdown":                 return "markdown"
        case "lua":                            return "lua"
        case "r":                              return "r"
        case "pl", "pm":                       return "perl"
        case "dart":                           return "dart"
        case "scala", "sc":                    return "scala"
        case "clj", "cljs", "cljc", "edn":     return "clojure"
        case "ex", "exs":                      return "elixir"
        default:                               return nil
        }
    }
}

// MARK: - File-type icon view

/// Renders a file's icon: SF Symbols for folders / symlinks / media, and a
/// brand-colored extension badge (e.g. `py`, `js`, `go`) for everything with an
/// extension, so each file type is visually distinct.
struct FileTypeIcon: View {
    let file: RemoteFile
    var scale: CGFloat = 1

    var body: some View {
        content
            .frame(width: 22 * scale, height: 22 * scale)
    }

    @ViewBuilder
    private var content: some View {
        switch file.kind {
        case .directory:
            symbol("folder.fill", FileIcon.directoryColor)
        case .symlink:
            symbol("arrowshape.turn.up.right.fill", .teal)
        case .other:
            symbol("doc.badge.gearshape", .secondary)
        case .file:
            fileContent
        }
    }

    @ViewBuilder
    private var fileContent: some View {
        let ext = (file.name as NSString).pathExtension.lowercased()
        if let logo = LanguageLogo.image(for: ext) {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18 * scale, height: 18 * scale)
        } else if let media = FileIcon.mediaSymbol(forExtension: ext) {
            symbol(media.symbol, media.color)
        } else if ext.isEmpty {
            symbol("doc.fill", .secondary)
        } else {
            ExtensionBadge(label: ext, hex: FileIcon.badgeHex(forExtension: ext),
                           width: 21 * scale, height: 15 * scale, fontSize: 8.5 * scale)
        }
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 14 * scale))
            .foregroundStyle(color)
    }
}

/// A small rounded chip showing a file extension in its brand color, with a
/// contrast-aware label color.
struct ExtensionBadge: View {
    let label: String
    let hex: UInt32
    var width: CGFloat = 21
    var height: CGFloat = 15
    var fontSize: CGFloat = 8.5

    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(labelColor)
            .padding(.horizontal, 2)
            .frame(width: width, height: height)
            .background(Color(hex: hex), in: RoundedRectangle(cornerRadius: 3.5 * (width / 21)))
    }

    private var labelColor: Color {
        let r = Double((hex >> 16) & 0xFF)
        let g = Double((hex >> 8) & 0xFF)
        let b = Double(hex & 0xFF)
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        return luminance > 0.62 ? Color.black.opacity(0.78) : .white
    }
}

// MARK: - Formatting helpers

enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func size(_ file: RemoteFile) -> String {
        guard !file.isDirectory else { return "—" }
        return byteFormatter.string(fromByteCount: file.size)
    }

    static func size(bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }
}

// MARK: - Reusable status dot

struct StatusDot: View {
    let state: ConnState

    private var color: Color {
        switch state {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .disconnected: return Color.secondary.opacity(0.5)
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(color.opacity(0.35), lineWidth: 3).scaleEffect(1.6))
    }
}
