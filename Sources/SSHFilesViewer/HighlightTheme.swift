import SwiftUI
import AppKit

/// A syntax-highlighting color scheme. Token colors are stored as RGB hex and
/// exposed as both AppKit (`ns*`) and SwiftUI colors.
struct HighlightTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let isDark: Bool

    let background: UInt32
    let foreground: UInt32
    let comment: UInt32
    let keyword: UInt32
    let string: UInt32
    let number: UInt32
    let function: UInt32
    let type: UInt32

    // AppKit colors (NSTextView).
    var nsBackground: NSColor { NSColor(hex: background) }
    var nsForeground: NSColor { NSColor(hex: foreground) }
    var nsComment: NSColor { NSColor(hex: comment) }
    var nsKeyword: NSColor { NSColor(hex: keyword) }
    var nsString: NSColor { NSColor(hex: string) }
    var nsNumber: NSColor { NSColor(hex: number) }
    var nsFunction: NSColor { NSColor(hex: function) }
    var nsType: NSColor { NSColor(hex: type) }

    // SwiftUI colors (chrome).
    var bg: Color { Color(hex: background) }
    var fg: Color { Color(hex: foreground) }
    var commentColor: Color { Color(hex: comment) }
}

extension HighlightTheme {
    static let all: [HighlightTheme] = [
        oneDark, dracula, nord, monokai, gruvboxDark,
        solarizedDark, solarizedLight, githubLight,
    ]

    static func named(_ id: String) -> HighlightTheme {
        all.first { $0.id == id } ?? oneDark
    }

    static let oneDark = HighlightTheme(
        id: "one-dark", name: "One Dark", isDark: true,
        background: 0x282C34, foreground: 0xABB2BF, comment: 0x5C6370,
        keyword: 0xC678DD, string: 0x98C379, number: 0xD19A66, function: 0x61AFEF, type: 0xE5C07B)

    static let dracula = HighlightTheme(
        id: "dracula", name: "Dracula", isDark: true,
        background: 0x282A36, foreground: 0xF8F8F2, comment: 0x6272A4,
        keyword: 0xFF79C6, string: 0xF1FA8C, number: 0xBD93F9, function: 0x50FA7B, type: 0x8BE9FD)

    static let nord = HighlightTheme(
        id: "nord", name: "Nord", isDark: true,
        background: 0x2E3440, foreground: 0xD8DEE9, comment: 0x616E88,
        keyword: 0x81A1C1, string: 0xA3BE8C, number: 0xB48EAD, function: 0x88C0D0, type: 0x8FBCBB)

    static let monokai = HighlightTheme(
        id: "monokai", name: "Monokai", isDark: true,
        background: 0x272822, foreground: 0xF8F8F2, comment: 0x75715E,
        keyword: 0xF92672, string: 0xE6DB74, number: 0xAE81FF, function: 0xA6E22E, type: 0x66D9EF)

    static let gruvboxDark = HighlightTheme(
        id: "gruvbox-dark", name: "Gruvbox Dark", isDark: true,
        background: 0x282828, foreground: 0xEBDBB2, comment: 0x928374,
        keyword: 0xFB4934, string: 0xB8BB26, number: 0xD3869B, function: 0xFABD2F, type: 0x8EC07C)

    static let solarizedDark = HighlightTheme(
        id: "solarized-dark", name: "Solarized Dark", isDark: true,
        background: 0x002B36, foreground: 0x839496, comment: 0x586E75,
        keyword: 0x859900, string: 0x2AA198, number: 0xD33682, function: 0x268BD2, type: 0xB58900)

    static let solarizedLight = HighlightTheme(
        id: "solarized-light", name: "Solarized Light", isDark: false,
        background: 0xFDF6E3, foreground: 0x657B83, comment: 0x93A1A1,
        keyword: 0x859900, string: 0x2AA198, number: 0xD33682, function: 0x268BD2, type: 0xB58900)

    static let githubLight = HighlightTheme(
        id: "github-light", name: "GitHub Light", isDark: false,
        background: 0xFFFFFF, foreground: 0x24292E, comment: 0x6A737D,
        keyword: 0xD73A49, string: 0x032F62, number: 0x005CC5, function: 0x6F42C1, type: 0x22863A)
}
