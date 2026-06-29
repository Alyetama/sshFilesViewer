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
                    BrowserContainer(session: model.session(for: connection))
                        .id(connection.id)
                } else {
                    WelcomeView()
                }
            }
        }
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
