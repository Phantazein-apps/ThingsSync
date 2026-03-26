import Foundation
import Combine
import AppKit
import ServiceManagement

/// Orchestrates bidirectional sync between Things 3 and Notion.
/// Runs on a configurable timer. Replaces the bash script + LaunchAgent.
@MainActor
class SyncEngine: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var lastError: String?
    @Published var syncLog: [SyncLogEntry] = []
    @Published var isPaused = false
    @Published var isConnected = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    /// Sync interval in seconds (default 60)
    @Published var syncInterval: TimeInterval = 60 {
        didSet { if isConnected { restartTimer() } }
    }

    private var timer: Timer?
    private var thingsReader = ThingsReader()
    private var notionClient: NotionClient?
    private var state: SyncState = .empty

    private let stateURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".things3-notion-sync")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    // MARK: - Lifecycle

    init() {
        // Auto-connect on launch if credentials exist
        autoConnect()
    }

    private func autoConnect() {
        guard let apiKey = KeychainHelper.load(account: "notion-api-key"),
              let databaseId = KeychainHelper.load(account: "notion-database-id"),
              !apiKey.isEmpty, !databaseId.isEmpty else {
            log("No saved credentials")
            // Show onboarding on first launch
            if KeychainHelper.load(account: "onboarding-complete") == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    OnboardingWindowController.shared.show(syncEngine: self)
                }
            }
            return
        }
        start(apiKey: apiKey, databaseId: databaseId)
    }

    func start(apiKey: String, databaseId: String) {
        notionClient = NotionClient(apiKey: apiKey, databaseId: databaseId)
        isConnected = true
        loadState()
        restartTimer()
        log("Connected — syncing every \(Int(syncInterval))s")
        // Run immediately on start
        Task { await sync() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isConnected = false
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            log("Launch at login failed: \(error.localizedDescription)")
        }
    }

    func pause() {
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        isPaused = false
        restartTimer()
    }

    // MARK: - Sync

    func sync() async {
        guard !isSyncing, !isPaused, let notionClient else { return }

        isSyncing = true
        lastError = nil

        do {
            // Step 1: Read Things 3
            let thingsItems = try await thingsReader.fetchTodayItems()

            // Step 2: Read Notion
            let notionPages = try await notionClient.queryDatabase()

            // First run: just snapshot state, don't execute any actions
            let isFirstRun = state.lastSync == nil

            // Step 3: Diff and resolve
            let actions: [SyncAction]
            if isFirstRun {
                actions = []
                log("First run — building initial state snapshot (no writes)")
            } else {
                actions = DiffResolver.resolve(
                    thingsItems: thingsItems,
                    notionPages: notionPages,
                    previousState: state
                )
            }

            // Step 4: Execute actions
            for action in actions {
                try await execute(action: action, notionClient: notionClient)
            }

            // Step 5: Save state
            state = buildState(things: thingsItems, notion: notionPages)
            saveState()

            lastSyncTime = Date()

            if isFirstRun {
                log("State snapshot saved — \(thingsItems.count) Things items, \(notionPages.count) Notion pages")
            } else if actions.isEmpty {
                log("Sync complete — no changes")
            } else {
                log("Synced \(actions.count) change(s)")
            }
        } catch {
            lastError = error.localizedDescription
            log("Error: \(error.localizedDescription)")
        }

        isSyncing = false
    }

    // MARK: - Actions

    private func execute(action: SyncAction, notionClient: NotionClient) async throws {
        switch action {
        case .createInNotion(let item):
            let props = NotionPropertyBuilder.build(from: item)
            try await notionClient.createPage(properties: props)
            log("→ Notion: Created '\(item.name)'")

        case .updateNotion(let pageId, let item):
            let props = NotionPropertyBuilder.build(from: item)
            try await notionClient.updatePage(pageId: pageId, properties: props)
            log("→ Notion: Updated '\(item.name)'")

        case .updateThings(let thingsId, let page):
            try await thingsReader.updateItem(
                id: thingsId,
                title: page.title,
                notes: page.notes,
                completed: page.status == "Done"
            )
            log("← Things: Updated '\(page.title)'")

        case .createInThings(let page):
            try await thingsReader.createItem(title: page.title, notes: page.notes)
            log("← Things: Created '\(page.title)'")

        case .archiveNotion(let pageId, let title):
            try await notionClient.archivePage(pageId: pageId)
            log("→ Notion: Archived '\(title)'")
        }
    }

    // MARK: - State persistence

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let loaded = try? JSONDecoder().decode(SyncState.self, from: data) else {
            state = .empty
            return
        }
        state = loaded
        lastSyncTime = loaded.lastSync
    }

    private func saveState() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: stateURL)
    }

    private func buildState(things: [ThingsItem], notion: [NotionPage]) -> SyncState {
        var thingsSnap: [String: ThingsSnapshot] = [:]
        for item in things {
            thingsSnap[item.id] = ThingsSnapshot(name: item.name, status: item.status, notes: item.notes)
        }

        var notionSnap: [String: NotionSnapshot] = [:]
        var pages: [String: String] = [:]
        for page in notion {
            if !page.thingsId.isEmpty {
                notionSnap[page.thingsId] = NotionSnapshot(
                    pageId: page.id, title: page.title, status: page.status,
                    notes: page.notes, lastEdited: page.lastEdited
                )
            }
            pages[page.id] = page.thingsId
        }

        return SyncState(lastSync: Date(), things: thingsSnap, notion: notionSnap, notionPages: pages)
    }

    // MARK: - Timer

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sync()
            }
        }
    }

    // MARK: - Logging

    private func log(_ message: String) {
        let entry = SyncLogEntry(timestamp: Date(), message: message)
        syncLog.insert(entry, at: 0)
        // Keep last 100 entries
        if syncLog.count > 100 { syncLog.removeLast() }
    }
}

struct SyncLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
}
