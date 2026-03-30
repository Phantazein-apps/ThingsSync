import SwiftUI

struct MenuBarView: View {
    @ObservedObject var syncEngine: SyncEngine
    @Environment(\.dismiss) private var dismiss

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

            Toggle("Launch at login", isOn: Binding(
                get: { syncEngine.launchAtLogin },
                set: { _ in syncEngine.toggleLaunchAtLogin() }
            ))
            .font(.caption)

            Divider()

            // Footer
            Button {
                let engine = syncEngine
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    SettingsWindowController.shared.show(syncEngine: engine)
                }
            } label: {
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

/// Manages the settings window using AppKit directly, since SwiftUI's
/// openWindow/Settings scene doesn't work from MenuBarExtra.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(syncEngine: SyncEngine) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(syncEngine: syncEngine)
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 700)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ThingsSync Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        self.window = window
    }
}
