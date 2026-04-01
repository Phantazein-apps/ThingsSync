import SwiftUI

struct SettingsView: View {
    @ObservedObject var syncEngine: SyncEngine
    @State private var apiKey = ""
    @State private var databaseId = ""
    @State private var saveError: String?
    @State private var availableProjects: [ThingsProject] = []
    @State private var availableAreas: [ThingsArea] = []
    @State private var filterLoadError: String?

    var body: some View {
        Form {
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

            Section("Things 3 Filter") {
                Toggle("Exclude recurring tasks", isOn: $syncEngine.excludeRecurring)

                Picker("Sync", selection: $syncEngine.syncFilterMode) {
                    Text("Everything").tag(SyncFilterMode.all)
                    Text("By Project").tag(SyncFilterMode.byProject)
                    Text("By Area").tag(SyncFilterMode.byArea)
                }
                .onChange(of: syncEngine.syncFilterMode) { _, _ in
                    syncEngine.selectedFilterIDs = []
                }

                if let error = filterLoadError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if syncEngine.syncFilterMode == .byProject {
                    if availableProjects.isEmpty {
                        Text("No projects found")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(availableProjects) { project in
                            Toggle(project.name, isOn: Binding(
                                get: { syncEngine.selectedFilterIDs.contains(project.id) },
                                set: { enabled in
                                    if enabled {
                                        syncEngine.selectedFilterIDs.insert(project.id)
                                    } else {
                                        syncEngine.selectedFilterIDs.remove(project.id)
                                    }
                                }
                            ))
                        }
                    }
                }

                if syncEngine.syncFilterMode == .byArea {
                    if availableAreas.isEmpty {
                        Text("No areas found")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(availableAreas) { area in
                            Toggle(area.name, isOn: Binding(
                                get: { syncEngine.selectedFilterIDs.contains(area.id) },
                                set: { enabled in
                                    if enabled {
                                        syncEngine.selectedFilterIDs.insert(area.id)
                                    } else {
                                        syncEngine.selectedFilterIDs.remove(area.id)
                                    }
                                }
                            ))
                        }
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
        .frame(width: 500, height: 700)
        .onAppear {
            apiKey = KeychainHelper.load(account: "notion-api-key") ?? ""
            databaseId = KeychainHelper.load(account: "notion-database-id") ?? ""
            loadThingsData()
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

    private func loadThingsData() {
        Task {
            let reader = ThingsReader()
            do {
                availableProjects = try await reader.fetchProjects()
                availableAreas = try await reader.fetchAreas()
            } catch {
                filterLoadError = error.localizedDescription
            }
        }
    }

    private func saveAndConnect() {
        saveError = nil
        do {
            try KeychainHelper.save(account: "notion-api-key", value: apiKey)
            try KeychainHelper.save(account: "notion-database-id", value: databaseId)
            syncEngine.start(apiKey: apiKey, databaseId: databaseId)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
