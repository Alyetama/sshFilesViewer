import SwiftUI
import AppKit

struct PreviewView: View {
    @ObservedObject var session: BrowserSession
    let file: RemoteFile
    var onClose: () -> Void = {}

    @AppStorage(SettingsKeys.highlightTheme) private var themeID = SettingsKeys.defaultTheme
    @AppStorage(SettingsKeys.editorFontSize) private var fontSize = SettingsKeys.defaultFontSize
    @AppStorage(SettingsKeys.previewWrap) private var wrap = false

    @State private var content: Content = .loading
    @State private var source: TextSource?
    @State private var csvData: CSVData?
    @State private var csvAsText = false
    @State private var busy = false

    // Editing
    @State private var editing = false
    @State private var editedText: String?
    @State private var dirty = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var showCloseConfirm = false

    private struct TextSource { let string: String; let ext: String; let truncated: Bool }

    private enum Content {
        case loading
        case text(NSAttributedString, truncated: Bool)
        case table(CSVData)
        case image(NSImage)
        case binary
        case error(String)
    }

    private var theme: HighlightTheme { HighlightTheme.named(themeID) }

    // Cap inline reads so a giant file can't blow up memory.
    private let textByteCap = 1_000_000
    private let imageByteCap = 25_000_000

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            body(for: content)
            Divider()
            footer
        }
        .frame(minWidth: 320, minHeight: 240)
        .task { await load() }
        .onChange(of: themeID) { _ in rehighlight() }
        .onChange(of: fontSize) { _ in rehighlight() }
        .confirmationDialog("Save changes to “\(file.name)”?",
                            isPresented: $showCloseConfirm, titleVisibility: .visible) {
            Button("Save") { Task { if await save() { onClose() } } }
            Button("Discard Changes", role: .destructive) { onClose() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your edits will be lost if you don’t save them.")
        }
        .alert("Couldn’t Save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: Editing

    private var currentText: String { editedText ?? source?.string ?? "" }

    private var canEdit: Bool {
        guard let s = source, !s.truncated else { return false }
        if case .text = content { return true }
        return false
    }

    private func rebuildTextContent() {
        guard let s = source else { return }
        content = .text(
            SyntaxHighlighter.highlight(currentText, ext: s.ext, theme: theme, fontSize: fontSize),
            truncated: s.truncated
        )
    }

    private func rehighlight() {
        guard source != nil, case .text = content else { return }
        rebuildTextContent()
    }

    private func toggleEdit() {
        if editing {
            editing = false
        } else {
            editing = true
            if editedText == nil { editedText = source?.string }
        }
        rebuildTextContent()
    }

    private func handleEdit(_ text: String) {
        editedText = text
        dirty = (text != source?.string)
    }

    @discardableResult
    private func save() async -> Bool {
        guard dirty, let s = source else { return true }
        saving = true
        saveError = nil
        do {
            try await session.save(file, contents: currentText)
            // New baseline; refresh highlighting from saved text.
            source = TextSource(string: currentText, ext: s.ext, truncated: s.truncated)
            dirty = false
            rebuildTextContent()
            saving = false
            return true
        } catch {
            saveError = error.localizedDescription
            saving = false
            return false
        }
    }

    private func requestClose() {
        if dirty { showCloseConfirm = true } else { onClose() }
    }

    /// Toggles a CSV between table and raw-text rendering.
    private func setCSV(asText: Bool) {
        csvAsText = asText
        guard let s = source else { return }
        if asText {
            content = .text(
                SyntaxHighlighter.highlight(s.string, ext: s.ext, theme: theme, fontSize: fontSize),
                truncated: s.truncated
            )
        } else if let csv = csvData {
            content = .table(csv)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            FileTypeIcon(file: file, scale: 1.6)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if dirty {
                        Circle()
                            .fill(.orange)
                            .frame(width: 7, height: 7)
                            .help("Unsaved changes")
                    }
                }
                Text("\(Format.size(file)) · \(file.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button { requestClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close preview")
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    // MARK: Body

    @ViewBuilder
    private func body(for content: Content) -> some View {
        switch content {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .text(let attributed, let truncated):
            VStack(spacing: 0) {
                if truncated {
                    banner("Showing the first \(Format.size(bytes: Int64(textByteCap))) of this file.",
                           systemImage: "scissors")
                }
                CodeTextView(attributedText: attributed,
                             background: theme.nsBackground,
                             font: SyntaxHighlighter.monospacedFont(fontSize),
                             wrap: wrap,
                             editable: editing,
                             defaultColor: theme.nsForeground,
                             onTextChange: handleEdit)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)

        case .table(let data):
            VStack(spacing: 0) {
                if data.truncated || file.size > Int64(textByteCap) {
                    banner("Showing the first \(data.rows.count) rows.", systemImage: "scissors")
                }
                CSVTableView(data: data, theme: theme, fontSize: fontSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)

        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(checkerboard)

        case .binary:
            unavailable(
                systemImage: "doc.questionmark",
                title: "No inline preview",
                subtitle: "This looks like a binary file. Open it with the default app or download it."
            )

        case .error(let message):
            unavailable(
                systemImage: "exclamationmark.triangle.fill",
                title: "Couldn’t load preview",
                subtitle: message
            )
        }
    }

    private func banner(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(theme.commentColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(theme.fg.opacity(0.08))
    }

    private func unavailable(systemImage: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var checkerboard: some View {
        Color(nsColor: .windowBackgroundColor)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if busy { ProgressView().controlSize(.small) }
            if csvData != nil {
                Button {
                    setCSV(asText: !csvAsText)
                } label: {
                    Label(csvAsText ? "Table" : "Text",
                          systemImage: csvAsText ? "tablecells" : "text.alignleft")
                }
                .help(csvAsText ? "View as a table" : "View as raw text")
            }
            if saving { ProgressView().controlSize(.small) }
            if canEdit || editing {
                Button { toggleEdit() } label: {
                    Label(editing ? "Done" : "Edit",
                          systemImage: editing ? "checkmark.circle" : "pencil")
                }
                .help(editing ? "Stop editing" : "Edit this file")
            }
            if editing {
                Button { Task { await save() } } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!dirty || saving)
                .keyboardShortcut("s", modifiers: .command)
                .help("Save (⌘S)")
            }
            Spacer(minLength: 8)
            // Full labels when there's room; icon-only buttons when the pane is narrow.
            ViewThatFits(in: .horizontal) {
                footerActions(compact: false)
                footerActions(compact: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func footerActions(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button { openExternally() } label: {
                if compact {
                    Image(systemName: "arrow.up.forward.app")
                } else {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
            }
            .disabled(busy)
            .help("Open in the default app")

            Button { Task { await session.download(file) } } label: {
                if compact {
                    Image(systemName: "arrow.down.circle")
                } else {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .help("Download")
        }
        .fixedSize()
    }

    // MARK: Loading logic

    private func load() async {
        guard let client = session.activeClient else {
            content = .error("Not connected.")
            return
        }
        let ext = (file.name as NSString).pathExtension.lowercased()

        // Images first.
        if FileIcon.imageExts.contains(ext), file.size <= imageByteCap {
            do {
                let data = try await client.readFile(file.path, maxBytes: imageByteCap)
                if let image = NSImage(data: data) {
                    content = .image(image)
                    return
                }
            } catch {
                content = .error(error.localizedDescription)
                return
            }
        }

        // Otherwise attempt a text preview.
        do {
            let data = try await client.readFile(file.path, maxBytes: textByteCap)
            if looksBinary(data) {
                content = .binary
            } else {
                let string = String(decoding: data, as: UTF8.self)
                let truncated = file.size > Int64(textByteCap)
                source = TextSource(string: string, ext: ext, truncated: truncated)

                // Render CSV/TSV as a table by default.
                if ext == "csv" || ext == "tsv" {
                    let delimiter: Character = ext == "tsv" ? "\t" : ","
                    let parsed = CSVParser.parse(string, delimiter: delimiter, maxRows: 2000)
                    if !parsed.isEmpty {
                        csvData = parsed
                        content = .table(parsed)
                        return
                    }
                }

                // Cheap: tokenizing is capped at 120K chars and large files
                // become a single styled run, so this won't block the UI.
                content = .text(
                    SyntaxHighlighter.highlight(string, ext: ext, theme: theme, fontSize: fontSize),
                    truncated: truncated
                )
            }
        } catch {
            content = .error(error.localizedDescription)
        }
    }

    private func looksBinary(_ data: Data) -> Bool {
        // A NUL byte in the sampled prefix is a reliable binary signal.
        data.prefix(8000).contains(0)
    }

    private func openExternally() {
        busy = true
        Task {
            let url = await session.download(file, openAfter: true)
            await MainActor.run {
                busy = false
                if let url { NSWorkspace.shared.open(url) }
            }
        }
    }
}

// MARK: - AppKit-backed code view

/// NSTextView lays out large documents lazily (TextKit, non-contiguous layout),
/// so multi-megabyte files scroll smoothly. A SwiftUI `Text`, by contrast, lays
/// out the whole string up front and freezes the UI on large files.
struct CodeTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    var background: NSColor
    var font: NSFont
    var wrap: Bool
    var editable: Bool = false
    var defaultColor: NSColor = .textColor
    var onTextChange: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onTextChange: onTextChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let textView = NSTextView()
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true

        scrollView.documentView = textView
        apply(to: scrollView, textView: textView, context: context, force: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        apply(to: scrollView, textView: textView, context: context, force: false)
    }

    private func apply(to scrollView: NSScrollView, textView: NSTextView, context: Context, force: Bool) {
        let coord = context.coordinator

        if force || coord.lastBackground != background {
            scrollView.backgroundColor = background
            textView.backgroundColor = background
            coord.lastBackground = background
        }
        if force || coord.lastFont != font {
            textView.font = font
            coord.lastFont = font
        }
        if force || coord.lastWrap != wrap {
            configureWrapping(textView: textView, scrollView: scrollView)
            coord.lastWrap = wrap
        }
        if force || coord.lastEditable != editable {
            textView.isEditable = editable
            coord.lastEditable = editable
        }
        // Newly typed text uses the default color/font (it isn't re-tokenized
        // until the next highlight pass).
        textView.typingAttributes = [.foregroundColor: defaultColor, .font: font]

        // Resetting the text storage of a large document is expensive, so only
        // do it when the attributed content object actually changed. Guard the
        // delegate (programmatic) and preserve the caret/selection.
        if force || coord.lastText !== attributedText {
            coord.isProgrammatic = true
            let selected = textView.selectedRanges
            textView.textStorage?.setAttributedString(attributedText)
            let length = textView.string.utf16.count
            let clamped = selected.compactMap { value -> NSValue? in
                let r = value.rangeValue
                guard r.location <= length else { return nil }
                return NSValue(range: NSRange(location: r.location, length: min(r.length, length - r.location)))
            }
            if !clamped.isEmpty { textView.selectedRanges = clamped }
            coord.isProgrammatic = false
            coord.lastText = attributedText
        }
    }

    private func configureWrapping(textView: NSTextView, scrollView: NSScrollView) {
        guard let container = textView.textContainer else { return }
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if wrap {
            // Soft-wrap to the visible width: let the container track the text
            // view, which tracks the clip view via the autoresizing mask. Never
            // pin the width to a measured size — a transient 0 would make every
            // character wrap onto its own line and stall layout.
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            container.widthTracksTextView = true
            container.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        } else {
            // No wrapping: long lines extend and scroll horizontally.
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            container.widthTracksTextView = false
            container.heightTracksTextView = false
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let onTextChange: ((String) -> Void)?
        var isProgrammatic = false
        var lastText: NSAttributedString?
        var lastBackground: NSColor?
        var lastFont: NSFont?
        var lastWrap: Bool?
        var lastEditable: Bool?

        init(onTextChange: ((String) -> Void)?) {
            self.onTextChange = onTextChange
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammatic, let textView = notification.object as? NSTextView else { return }
            onTextChange?(textView.string)
        }
    }
}
