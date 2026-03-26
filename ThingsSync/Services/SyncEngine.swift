import Foundation
import Combine
import AppKit

/// Orchestrates bidirectional sync between Things 3 and Notion.
/// Runs on a configurable timer. Replaces the bash script + LaunchAgent.
@MainActor
class SyncEngine: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var lastError: String?
    @Published var syncLog: [SyncLogEntry] = []
    @Published var isPaused = false

    /// Sync interval in seconds (default 60)
    @Published var syncInterval: TimeInterval = 60 {
        didSet { restartTimer() }
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

    func start(apiKey: String, databaseId: String) {
        notionClient = NotionClient(apiKey: apiKey, databaseId: databaseId)
        loadState()
        restartTimer()
        // Run immediately on start
        Task { await sync() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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

            // Step 3: Diff and resolve
            let actions = DiffResolver.resolve(
                thingsItems: thingsItems,
                notionPages: notionPages,
                previousState: state
            )

            // Step 4: Execute actions
            for action in actions {
                try await execute(action: action, notionClient: notionClient)
            }

            // Step 5: Save state
            state = buildState(things: thingsItems, notion: notionPages)
            saveState()

            lastSyncTime = Date()

            if !actions.isEmpty {
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
            await thingsReader.updateItem(
                id: thingsId,
                title: page.title,
                notes: page.notes,
                completed: page.status == "Done"
            )
            log("← Things: Updated '\(page.title)'")

        case .createInThings(let page):
            await thingsReader.createItem(title: page.title, notes: page.notes)
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
        guard let data = try? JSONEncoder().encode(state) else { return }
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
