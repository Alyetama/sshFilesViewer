import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            EditorSettingsView()
                .tabItem { Label("Editor", systemImage: "textformat") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @AppStorage(SettingsKeys.previewMode) private var previewModeRaw = SettingsKeys.defaultPreviewMode
    @AppStorage(SettingsKeys.showHidden) private var showHidden = false
    @AppStorage(SettingsKeys.downloadDirectory) private var downloadDirectory = ""

    private var downloadPath: String {
        if !downloadDirectory.isEmpty { return (downloadDirectory as NSString).abbreviatingWithTildeInPath }
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        return (url?.path as NSString?)?.abbreviatingWithTildeInPath ?? "~/Downloads"
    }

    var body: some View {
        Form {
            Section("Previews") {
                Picker("Open previews in", selection: $previewModeRaw) {
                    ForEach(PreviewMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Files") {
                Toggle("Show hidden files", isOn: $showHidden)
            }

            Section("Downloads") {
                LabeledContent("Save files to") {
                    HStack {
                        Text(downloadPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseFolder() }
                        if !downloadDirectory.isEmpty {
                            Button("Reset") { downloadDirectory = "" }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            downloadDirectory = url.path
        }
    }
}

// MARK: - Editor

private struct EditorSettingsView: View {
    @AppStorage(SettingsKeys.highlightTheme) private var themeID = SettingsKeys.defaultTheme
    @AppStorage(SettingsKeys.editorFontSize) private var fontSize = SettingsKeys.defaultFontSize
    @AppStorage(SettingsKeys.previewWrap) private var wrap = false

    private var theme: HighlightTheme { HighlightTheme.named(themeID) }

    var body: some View {
        Form {
            Section("Syntax Highlighting") {
                Picker("Color scheme", selection: $themeID) {
                    ForEach(HighlightTheme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                LabeledContent("Preview") {
                    ThemeSwatch(theme: theme, fontSize: fontSize)
                }
            }

            Section("Text") {
                LabeledContent("Font size") {
                    HStack(spacing: 10) {
                        Slider(value: $fontSize, in: 9...22, step: 0.5)
                            .frame(width: 200)
                        Text("\(Int(fontSize.rounded())) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                Toggle("Wrap long lines", isOn: $wrap)
            }
        }
        .formStyle(.grouped)
    }
}

/// A live miniature of the selected theme.
private struct ThemeSwatch: View {
    let theme: HighlightTheme
    let fontSize: Double

    private static let sample = """
    // greet the world
    func greet(name) {
        let n = 42
        return "Hello, " + name
    }
    """

    var body: some View {
        CodeTextView(
            attributedText: SyntaxHighlighter.highlight(Self.sample, ext: "swift", theme: theme, fontSize: fontSize),
            background: theme.nsBackground,
            font: SyntaxHighlighter.monospacedFont(fontSize),
            wrap: true
        )
        .frame(width: 320, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
    }
}

// MARK: - About

private struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.connected.to.line.below.fill")
                .font(.system(size: 46))
                .foregroundStyle(
                    LinearGradient(colors: [Color(red: 0.33, green: 0.45, blue: 0.99),
                                            Color(red: 0.52, green: 0.27, blue: 0.95)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("SSH Files Viewer").font(.title2.weight(.bold))
            Text("Version 1.0").foregroundStyle(.secondary)

            Divider().frame(width: 280)

            VStack(spacing: 6) {
                Label("Connections reuse your existing SSH config, keys, and agent.",
                      systemImage: "key.fill")
                Label("Language logos by devicon (MIT License).",
                      systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 380, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
