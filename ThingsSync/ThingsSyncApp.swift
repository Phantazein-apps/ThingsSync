import SwiftUI

@main
struct ThingsSyncApp: App {
    @StateObject private var syncEngine = SyncEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(syncEngine: syncEngine)
        } label: {
            Image(systemName: syncEngine.isSyncing ? "arrow.triangle.2.circlepath" : "checkmark.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(syncEngine: syncEngine)
        }
    }
}
