import SwiftUI

@main
struct ThingsSyncApp: App {
    @StateObject private var syncEngine = SyncEngine()

    init() {
        // CLI test mode: run pipeline and exit
        if CommandLine.arguments.contains("--test") {
            Task {
                await CLITest.run()
                exit(0)
            }
            // Give the async task time to run
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 30))
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(syncEngine: syncEngine)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(syncEngine: syncEngine)
        }
    }

    private var menuBarIcon: String {
        if syncEngine.lastError != nil {
            return "exclamationmark.triangle"
        } else if syncEngine.isSyncing {
            return "arrow.triangle.2.circlepath"
        } else {
            return "checkmark.circle"
        }
    }
}
