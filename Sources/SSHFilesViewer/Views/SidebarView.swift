import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Section("Connections") {
                ForEach(model.connections) { connection in
                    ConnectionRow(connection: connection,
                                  session: model.session(for: connection))
                        .tag(connection.id)
                        .contextMenu {
                            Button("Edit…") { model.beginEdit(connection) }
                            Button("Delete", role: .destructive) { model.delete(connection) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.connections.isEmpty {
                ContentUnavailablePlaceholder()
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    model.beginAddConnection()
                } label: {
                    Label("Add Connection", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                if let connection = model.selectedConnection {
                    Button {
                        model.beginEdit(connection)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Edit connection")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Remotes")
    }
}

// MARK: - Connection row

private struct ConnectionRow: View {
    let connection: Connection
    @ObservedObject var session: BrowserSession

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "server.rack")
                .font(.system(size: 15))
                .foregroundStyle(.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name.isEmpty ? connection.host : connection.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(connection.displayDestination)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            StatusDot(state: session.status)
                .padding(.trailing, 6)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Empty placeholder

private struct ContentUnavailablePlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("No connections yet")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
