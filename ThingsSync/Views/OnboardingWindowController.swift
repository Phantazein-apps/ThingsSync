import SwiftUI
import AppKit

/// Manages the onboarding window using AppKit directly,
/// since SwiftUI Window scenes don't auto-open for menu bar apps.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show(syncEngine: SyncEngine) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView(syncEngine: syncEngine) { [weak self] in
            self?.window?.close()
            self?.window = nil
        }

        let hostingView = NSHostingView(rootView: onboardingView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 480)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ThingsSync Setup"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        self.window = window
    }
}
