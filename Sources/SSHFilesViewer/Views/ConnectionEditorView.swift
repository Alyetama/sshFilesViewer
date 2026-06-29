import SwiftUI
import AppKit

struct ConnectionEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let existing: Connection?

    @State private var name = ""
    @State private var host = ""
    @State private var portText = ""
    @State private var username = ""
    @State private var authMethod: AuthMethod = .agent
    @State private var identityFile = ""
    @State private var password = ""
    @State private var initialPath = ""

    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                Section("Identity") {
                    TextField("Name", text: $name, prompt: Text("My Server"))
                }

                Section("Server") {
                    TextField("Host", text: $host, prompt: Text("example.com or an ssh config alias"))
                    TextField("Port", text: $portText, prompt: Text("22"))
                    TextField("Username", text: $username, prompt: Text("optional — defaults to ssh config"))
                }

                Section("Authentication") {
                    Picker("Method", selection: $authMethod) {
                        ForEach(AuthMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch authMethod {
                    case .agent:
                        Label("Uses keys loaded in your SSH agent.", systemImage: "key.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .key:
                        HStack {
                            TextField("Private key", text: $identityFile, prompt: Text("~/.ssh/id_ed25519"))
                            Button("Browse…") { chooseKeyFile() }
                        }
                    case .password:
                        SecureField("Password", text: $password)
                        Label("Stored securely in your macOS Keychain.", systemImage: "lock.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Options") {
                    TextField("Start folder", text: $initialPath, prompt: Text("optional — defaults to home"))
                }
            }
            .formStyle(.grouped)

            footer
        }
        .frame(width: 480, height: 580)
        .onAppear(perform: populate)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(isEditing ? "Edit Connection" : "New Connection")
                    .font(.headline)
                Text("Connect to a remote machine over SSH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            testStatusView
            Spacer()
            Button("Test") { runTest() }
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty || testState == .testing)
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isEditing ? "Save" : "Add") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Testing…").foregroundStyle(.secondary)
            }
            .font(.callout)
        case .success:
            Label("Connection succeeded", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(2)
                .help(message)
        }
    }

    // MARK: Actions

    private func populate() {
        guard let c = existing else { return }
        name = c.name
        host = c.host
        portText = c.port.map(String.init) ?? ""
        username = c.username
        authMethod = c.authMethod
        identityFile = c.identityFile ?? ""
        initialPath = c.initialPath ?? ""
        if c.authMethod == .password {
            password = Keychain.get(account: c.id.uuidString) ?? ""
        }
    }

    private func buildConnection() -> Connection {
        var c = existing ?? Connection()
        c.name = name.trimmingCharacters(in: .whitespaces)
        c.host = host.trimmingCharacters(in: .whitespaces)
        c.port = Int(portText.trimmingCharacters(in: .whitespaces))
        c.username = username.trimmingCharacters(in: .whitespaces)
        c.authMethod = authMethod
        let key = identityFile.trimmingCharacters(in: .whitespaces)
        c.identityFile = (authMethod == .key && !key.isEmpty) ? key : nil
        let start = initialPath.trimmingCharacters(in: .whitespaces)
        c.initialPath = start.isEmpty ? nil : start
        if c.name.isEmpty { c.name = c.host }
        return c
    }

    private func save() {
        let c = buildConnection()
        model.save(c, password: authMethod == .password ? password : nil)
        dismiss()
    }

    private func chooseKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if FileManager.default.fileExists(atPath: sshDir.path) {
            panel.directoryURL = sshDir
        }
        if panel.runModal() == .OK, let url = panel.url {
            identityFile = url.path
        }
    }

    private func runTest() {
        testState = .testing
        let connection = buildConnection()
        let pw = authMethod == .password ? password : nil
        Task {
            let client = SSHClient(connection: connection, password: pw)
            do {
                _ = try await client.homeDirectory()
                await client.disconnect()
                await MainActor.run { testState = .success }
            } catch {
                await MainActor.run { testState = .failure(error.localizedDescription) }
            }
        }
    }
}
