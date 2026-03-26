import SwiftUI

struct SettingsView: View {
    @ObservedObject var syncEngine: SyncEngine
    @AppStorage("notionDatabaseId") private var databaseId = ""
    @State private var apiKey = ""
    @State private var showingKey = false

    var body: some View {
        Form {
            Section("Notion Connection") {
                SecureField("API Key", text: $apiKey)
                    .onAppear {
                        apiKey = KeychainHelper.load() ?? ""
                    }

                TextField("Database ID", text: $databaseId)
                    .font(.system(.body, design: .monospaced))

                Button("Save & Connect") {
                    try? KeychainHelper.save(apiKey: apiKey)
                    syncEngine.start(apiKey: apiKey, databaseId: databaseId)
                }
                .disabled(apiKey.isEmpty || databaseId.isEmpty)
            }

            Section("Sync") {
                Picker("Interval", selection: $syncEngine.syncInterval) {
                    Text("30 seconds").tag(TimeInterval(30))
                    Text("1 minute").tag(TimeInterval(60))
                    Text("5 minutes").tag(TimeInterval(300))
                }

                LabeledContent("Status") {
                    Text(syncEngine.isPaused ? "Paused" : "Active")
                        .foregroundStyle(syncEngine.isPaused ? .orange : .green)
                }

                if let lastSync = syncEngine.lastSyncTime {
                    LabeledContent("Last Sync") {
                        Text(lastSync, format: .dateTime)
                    }
                }
            }

            Section("Log") {
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
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
    }
}
