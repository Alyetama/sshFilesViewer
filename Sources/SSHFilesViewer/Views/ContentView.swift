import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 360)
        } detail: {
            Group {
                if let connection = model.selectedConnection {
                    BrowserContainer(session: model.session(for: connection)) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            columnVisibility = .detailOnly
                        }
                    }
                    .id(connection.id)
                } else {
                    WelcomeView()
                }
            }
        }
        // Enforce the window minimum at the AppKit level — SwiftUI's
        // windowResizability isn't reliably honored with NavigationSplitView, and
        // a too-small window makes the columns overflow (clipping the preview's
        // footer buttons).
        .background(WindowMinSizeSetter(width: 960, height: 600))
        // Collapse the sidebar once a connection is chosen so the browser gets
        // the full window; reveal it again when nothing is selected.
        .onChange(of: model.selection) { newValue in
            withAnimation(.easeInOut(duration: 0.25)) {
                columnVisibility = newValue == nil ? .all : .detailOnly
            }
        }
        .sheet(isPresented: $model.isPresentingEditor) {
            ConnectionEditorView(existing: model.editingConnection)
                .environmentObject(model)
        }
    }
}

// MARK: - Window minimum size (AppKit-enforced)

/// Sets the host NSWindow's `minSize` so it can't be resized below the size the
/// three columns need, and grows the window if it's currently smaller.
private struct WindowMinSizeSetter: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(from: nsView) }
    }

    private func apply(from view: NSView) {
        guard let window = view.window else { return }
        window.minSize = NSSize(width: width, height: height)

        var frame = window.frame
        let topY = frame.maxY // keep the top edge fixed while growing downward
        frame.size.width = max(frame.width, width)
        frame.size.height = max(frame.height, height)
        frame.origin.y = topY - frame.height

        // Keep the whole window within the screen's visible area so right-aligned
        // controls (like the preview footer) never fall off an edge.
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }

        if frame != window.frame {
            window.setFrame(frame, display: true, animate: false)
        }
    }
}

// MARK: - Welcome / empty state

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: .appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
            VStack(spacing: 6) {
                Text("SSH Files Viewer")
                    .font(.system(size: 26, weight: .bold))
                Text("Browse, preview, and download files on your remote machines.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                model.beginAddConnection()
            } label: {
                Label(model.connections.isEmpty ? "Add Your First Connection" : "New Connection",
                      systemImage: "plus")
                    .frame(minWidth: 200)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)

            if !model.connections.isEmpty {
                Text("…or pick a connection from the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
