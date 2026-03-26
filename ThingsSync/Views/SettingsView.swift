import SwiftUI

struct SettingsView: View {
    @ObservedObject var syncEngine: SyncEngine
    @State private var apiKey = ""
    @State private var databaseId = ""
    @State private var thingsAuthToken = ""
    @State private var saveError: String?

    var body: some View {
        Form {
            Section("Things 3") {
                SecureField("URL Auth Token", text: $thingsAuthToken)
                    .textFieldStyle(.roundedBorder)
                Text("Things → Settings → General → Enable Things URLs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notion Connection") {
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                TextField("Database ID", text: $databaseId)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save & Connect") {
                        saveAndConnect()
                    }
                    .disabled(apiKey.isEmpty || databaseId.isEmpty)

                    if syncEngine.isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connected")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }

                if let error = saveError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Sync") {
                Picker("Interval", selection: $syncEngine.syncInterval) {
                    Text("30 seconds").tag(TimeInterval(30))
                    Text("1 minute").tag(TimeInterval(60))
                    Text("5 minutes").tag(TimeInterval(300))
                }

                LabeledContent("Status") {
                    Text(statusText)
                        .foregroundStyle(statusColor)
                }

                if let lastSync = syncEngine.lastSyncTime {
                    LabeledContent("Last Sync") {
                        Text(lastSync, format: .dateTime)
                    }
                }

                if let error = syncEngine.lastError {
                    LabeledContent("Last Error") {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            Section("Log") {
                if syncEngine.syncLog.isEmpty {
                    Text("No sync activity yet")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    List(syncEngine.syncLog.prefix(20)) { entry in
                        HStack {
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .font(.caption)
                        }
                    }
                    .frame(height: 200)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 560)
        .onAppear {
            apiKey = KeychainHelper.load(account: "notion-api-key") ?? ""
            databaseId = KeychainHelper.load(account: "notion-database-id") ?? ""
            thingsAuthToken = KeychainHelper.load(account: "things-auth-token") ?? ""
        }
    }

    private var statusText: String {
        if !syncEngine.isConnected { return "Not connected" }
        if syncEngine.isPaused { return "Paused" }
        if syncEngine.isSyncing { return "Syncing…" }
        return "Active"
    }

    private var statusColor: Color {
        if !syncEngine.isConnected { return .secondary }
        if syncEngine.isPaused { return .orange }
        return .green
    }

    private func saveAndConnect() {
        saveError = nil
        do {
            if !thingsAuthToken.isEmpty {
                try KeychainHelper.save(account: "things-auth-token", value: thingsAuthToken)
            }
            try KeychainHelper.save(account: "notion-api-key", value: apiKey)
            try KeychainHelper.save(account: "notion-database-id", value: databaseId)
            syncEngine.start(apiKey: apiKey, databaseId: databaseId)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
