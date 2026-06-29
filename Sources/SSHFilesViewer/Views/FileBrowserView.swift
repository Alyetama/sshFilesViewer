import SwiftUI
import AppKit

// MARK: - Container (handles connect / connecting / failed states)

struct BrowserContainer: View {
    @ObservedObject var session: BrowserSession
    var onConnected: () -> Void = {}

    var body: some View {
        Group {
            switch session.status {
            case .connected:
                FileBrowserView(session: session)
            case .connecting:
                CenteredMessage(
                    systemImage: "antenna.radiowaves.left.and.right",
                    title: "Connecting…",
                    subtitle: session.connection.displayDestination,
                    showsProgress: true
                )
            case .failed(let message):
                ConnectionFailedView(session: session, message: message)
            case .disconnected:
                CenteredMessage(
                    systemImage: "bolt.horizontal.circle",
                    title: "Not connected",
                    subtitle: session.connection.displayDestination,
                    showsProgress: false,
                    actionTitle: "Connect"
                ) { Task { await session.connect() } }
            }
        }
        .task(id: session.connection.id) {
            if session.status == .disconnected { await session.connect() }
        }
        // Collapse the sidebar once the connection is established.
        .onChange(of: session.status) { status in
            if status == .connected { onConnected() }
        }
    }
}

private struct ConnectionFailedView: View {
    @ObservedObject var session: BrowserSession
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 46))
                .foregroundStyle(.orange)
            Text("Couldn’t connect")
                .font(.title2.weight(.semibold))
            Text(session.connection.displayDestination)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(message)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxWidth: 460, maxHeight: 140)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            Button {
                Task { await session.connect() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CenteredMessage: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var showsProgress: Bool = false
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
            if showsProgress {
                ProgressView().controlSize(.small).padding(.top, 4)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File browser

struct FileBrowserView: View {
    @ObservedObject var session: BrowserSession
    @Environment(\.openWindow) private var openWindow

    @State private var selectedID: RemoteFile.ID?
    @State private var search = ""
    @State private var previewFile: RemoteFile?
    @State private var pathEditing = false
    @State private var pathInput = ""
    @State private var showDownloads = false
    @AppStorage("showHiddenFiles") private var showHidden = false
    @AppStorage(SettingsKeys.previewMode) private var previewModeRaw = SettingsKeys.defaultPreviewMode

    private var previewMode: PreviewMode { PreviewMode(rawValue: previewModeRaw) ?? .pane }
    private var showsPreviewPane: Bool { previewMode == .pane && previewFile != nil }

    private var filtered: [RemoteFile] {
        var items = session.entries
        if !showHidden {
            items = items.filter { !$0.name.hasPrefix(".") }
        }
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                navBar
                Divider()
                breadcrumb
                Divider()
                fileList
                statusBar
            }
            // Cap the file list when a preview is open so the preview gets a
            // comfortable share and grows with the window; fill otherwise.
            .frame(minWidth: 300, maxWidth: showsPreviewPane ? 560 : .infinity)

            if previewMode == .pane, let file = previewFile {
                PreviewView(session: session, file: file, onClose: { previewFile = nil })
                    .frame(minWidth: 360, idealWidth: 600, maxWidth: .infinity)
                    .id(file.id)
            }
        }
        .navigationTitle(session.connection.name.isEmpty ? session.connection.host : session.connection.name)
        .navigationSubtitle(session.connection.displayDestination)
        .toolbar { toolbarContent }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter files")
        .sheet(isPresented: windowPreviewPresented) {
            if let file = previewFile {
                PreviewView(session: session, file: file, onClose: { previewFile = nil })
                    .frame(width: 820, height: 600)
                    .id(file.id)
            }
        }
    }

    private var windowPreviewPresented: Binding<Bool> {
        Binding(
            get: { previewMode == .window && previewFile != nil },
            set: { presented in if !presented { previewFile = nil } }
        )
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { Task { await session.goBack() } } label: { Image(systemName: "chevron.left") }
                .disabled(!session.canGoBack)
                .help("Back")
            Button { Task { await session.goForward() } } label: { Image(systemName: "chevron.right") }
                .disabled(!session.canGoForward)
                .help("Forward")
        }
        ToolbarItemGroup {
            if !session.downloads.isEmpty {
                Button { showDownloads.toggle() } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .help("Downloads")
                .popover(isPresented: $showDownloads, arrowEdge: .bottom) {
                    DownloadsPopover(session: session)
                }
            }
            Button { showHidden.toggle() } label: {
                Image(systemName: showHidden ? "eye" : "eye.slash")
            }
            .help(showHidden ? "Hide hidden files (⇧⌘.)" : "Show hidden files (⇧⌘.)")
            .keyboardShortcut(".", modifiers: [.command, .shift])
            Button { Task { await session.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh")
            Menu {
                Toggle("Show Hidden Files", isOn: $showHidden)
                Button("Settings…") {
                    openWindow(id: settingsWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider()
                Button("Reveal Downloads Folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([BrowserSession.downloadDirectory()])
                }
                Divider()
                Button("Disconnect") { Task { await session.disconnect() } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: Nav bar (up / home / etc.)

    private var navBar: some View {
        HStack(spacing: 8) {
            iconButton("arrow.up", help: "Parent folder", shortcut: .upArrow) {
                Task { await session.goUp() }
            }
            iconButton("house", help: "Home folder") {
                Task { await session.goHome() }
            }
            Spacer()
            if session.isLoading {
                ProgressView().controlSize(.small)
            }
            Text("\(filtered.count) item\(filtered.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func iconButton(_ symbol: String, help: String, shortcut: KeyEquivalent? = nil,
                            action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Image(systemName: symbol).frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
        if let shortcut {
            return AnyView(button.keyboardShortcut(shortcut, modifiers: .command))
        }
        return AnyView(button)
    }

    // MARK: Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: 0) {
            if pathEditing {
                TextField("Path", text: $pathInput, onCommit: {
                    let target = pathInput.trimmingCharacters(in: .whitespaces)
                    pathEditing = false
                    if !target.isEmpty { Task { await session.navigate(to: target) } }
                })
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onExitCommand { pathEditing = false }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        let segments = RemotePath.segments(session.path)
                        ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                            if idx > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 3)
                            }
                            let isLast = idx == segments.count - 1
                            Button {
                                Task { await session.navigate(to: seg.path) }
                            } label: {
                                if idx == 0 {
                                    Image(systemName: "externaldrive")
                                        .font(.system(size: 12))
                                        .padding(.trailing, 1)
                                } else {
                                    Text(seg.label)
                                        .font(.system(size: 12, weight: isLast ? .semibold : .regular))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(isLast ? .primary : .secondary)
                            .help(idx == 0 ? "Root" : seg.path)
                        }
                    }
                }
                Spacer(minLength: 8)
                Button {
                    pathInput = session.path
                    pathEditing = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Edit path")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.025))
    }

    // MARK: File list

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                columnHeader
                if filtered.isEmpty {
                    emptyState
                } else {
                    ForEach(filtered) { file in
                        FileRowView(
                            file: file,
                            isSelected: selectedID == file.id,
                            onSelect: { selectedID = file.id },
                            onActivate: { activate(file) },
                            onView: { previewFile = file },
                            onDownload: { Task { await session.download(file); showDownloads = true } },
                            onDownloadAs: { downloadAs(file) },
                            onCopyPath: { copyToPasteboard(file.path) }
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.background)
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Size")
                .frame(width: 90, alignment: .trailing)
            Text("Modified")
                .frame(width: 140, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: search.isEmpty ? "folder" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(search.isEmpty ? "This folder is empty" : "No matches")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: Status bar

    private var statusBar: some View {
        Group {
            if let error = session.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Dismiss") { session.errorMessage = nil }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.12))
            }
        }
    }

    // MARK: Actions

    private func activate(_ file: RemoteFile) {
        Task {
            let result = await session.activate(file)
            if case .preview(let f) = result { previewFile = f }
        }
    }

    private func downloadAs(_ file: RemoteFile) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task { await session.download(file, saveTo: url); showDownloads = true }
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

// MARK: - File row

private struct FileRowView: View {
    let file: RemoteFile
    let isSelected: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onView: () -> Void
    let onDownload: () -> Void
    let onDownloadAs: () -> Void
    let onCopyPath: () -> Void

    @State private var hovering = false

    private var isOpenable: Bool { file.kind != .directory }

    var body: some View {
        HStack(spacing: 10) {
            FileTypeIcon(file: file)

            Text(file.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)

            if file.kind == .symlink, let target = file.symlinkTarget {
                Text("→ \(target)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Always reserve the action area so hovering only fades the buttons
            // in/out — inserting them would reflow the row and make it "shake".
            HStack(spacing: 2) {
                if isOpenable {
                    rowButton("eye", help: "View", action: onView)
                }
                rowButton("arrow.down.circle", help: "Download", action: onDownload)
            }
            .frame(width: 54, alignment: .trailing)
            .opacity(hovering || isSelected ? 1 : 0)
            .allowsHitTesting(hovering || isSelected)

            Text(Format.size(file))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            Text(file.modified)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onActivate)
        .onTapGesture(perform: onSelect)
        .contextMenu {
            if file.isDirectory {
                Button("Open") { onActivate() }
            } else {
                Button("View") { onView() }
                Button("Open in Default App") { onActivate() }
            }
            Divider()
            Button("Download") { onDownload() }
            if !file.isDirectory {
                Button("Download As…") { onDownloadAs() }
            }
            Divider()
            Button("Copy Path") { onCopyPath() }
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if hovering { return Color.primary.opacity(0.05) }
        return .clear
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

// MARK: - Downloads popover

private struct DownloadsPopover: View {
    @ObservedObject var session: BrowserSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Button("Clear") {
                    session.downloads.removeAll { $0.state != .running }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(session.downloads) { item in
                        DownloadRow(item: item)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .frame(width: 320)
    }
}

private struct DownloadRow: View {
    @ObservedObject var item: DownloadItem

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                switch item.state {
                case .running:
                    ProgressView(value: item.progress)
                        .controlSize(.small)
                case .completed:
                    Text("Completed").font(.caption).foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(1).help(message)
                }
            }
            Spacer(minLength: 4)
            if item.state == .completed {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.destination])
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.state {
        case .running:
            Image(systemName: "arrow.down.circle").foregroundStyle(.tint)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
