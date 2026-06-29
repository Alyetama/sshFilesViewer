import SwiftUI

/// Identifier for the dedicated Settings window scene.
let settingsWindowID = "settings"

/// Where file previews open.
enum PreviewMode: String, CaseIterable, Identifiable {
    case pane
    case window

    var id: String { rawValue }
    var label: String {
        switch self {
        case .pane: return "Side Panel"
        case .window: return "Separate Window"
        }
    }
    var systemImage: String {
        switch self {
        case .pane: return "sidebar.right"
        case .window: return "macwindow"
        }
    }
}

/// UserDefaults keys + defaults, kept in one place so every view stays in sync.
enum SettingsKeys {
    static let previewMode = "previewMode"
    static let highlightTheme = "highlightTheme"
    static let editorFontSize = "editorFontSize"
    static let previewWrap = "previewWrap"
    static let showHidden = "showHiddenFiles"
    static let downloadDirectory = "downloadDirectory"

    static let defaultPreviewMode = PreviewMode.pane.rawValue
    static let defaultTheme = HighlightTheme.oneDark.id
    static let defaultFontSize = 12.5
}
