import SwiftUI
import AppKit

/// File descriptor for the single-instance lock — held for the process lifetime.
private var lockFD: Int32 = -1

@main
struct ThingsSyncApp: App {
    @StateObject private var syncEngine = SyncEngine()

    init() {
        if CommandLine.arguments.contains("--test") {
            Task {
                await CLITest.run()
                exit(0)
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 30))
            exit(0)
        }

        // Single-instance guard using POSIX file lock.
        // Unlike NSRunningApplication, this has no race condition — the kernel
        // guarantees only one process can hold an exclusive lock.
        let lockPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".things3-notion-sync/thingssync.lock").path
        lockFD = open(lockPath, O_WRONLY | O_CREAT, 0o600)
        if lockFD == -1 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
            // Another instance holds the lock — exit immediately
            exit(0)
        }

        // Disable state restoration to prevent macOS from relaunching the app
        // alongside SMAppService (launch-at-login), which causes duplicates
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(syncEngine: syncEngine)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: syncEngine.isConnected) { _, _ in
            // Show onboarding on first launch after the app scene is ready
            showOnboardingIfNeeded()
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

    private func showOnboardingIfNeeded() {
        if KeychainHelper.load(account: "onboarding-complete") == nil && !syncEngine.isConnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                OnboardingWindowController.shared.show(syncEngine: syncEngine)
            }
        }
    }
}
