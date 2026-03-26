import SwiftUI

struct MenuBarView: View {
    @ObservedObject var syncEngine: SyncEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("ThingsSync")
                    .font(.headline)
                Spacer()
                if syncEngine.isSyncing {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }

            Divider()

            // Status
            if let lastSync = syncEngine.lastSyncTime {
                Label("Last sync: \(lastSync, format: .relative(presentation: .named))",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            if let error = syncEngine.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(2)
            }

            Divider()

            // Actions
            Button {
                Task { await syncEngine.sync() }
            } label: {
                Label("Sync Now", systemImage: "arrow.clockwise")
            }
            .disabled(syncEngine.isSyncing)

            Button {
                if syncEngine.isPaused {
                    syncEngine.resume()
                } else {
                    syncEngine.pause()
                }
            } label: {
                Label(
                    syncEngine.isPaused ? "Resume" : "Pause",
                    systemImage: syncEngine.isPaused ? "play.fill" : "pause.fill"
                )
            }

            Divider()

            // Recent log
            if !syncEngine.syncLog.isEmpty {
                Text("Recent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(syncEngine.syncLog.prefix(5)) { entry in
                    Text(entry.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Divider()
            }

            // Footer
            SettingsLink {
                Label("Settings…", systemImage: "gear")
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
