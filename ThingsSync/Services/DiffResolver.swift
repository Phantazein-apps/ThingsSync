import Foundation

/// Actions the sync engine can take.
enum SyncAction {
    case createInNotion(ThingsItem)
    case updateNotion(pageId: String, ThingsItem)
    case updateThings(thingsId: String, NotionPage)
    case createInThings(NotionPage)
    case archiveNotion(pageId: String, title: String)
}

/// Compares Things 3 and Notion states against the previous snapshot
/// to produce a list of sync actions.
enum DiffResolver {

    static func resolve(
        thingsItems: [ThingsItem],
        notionPages: [NotionPage],
        previousState: SyncState
    ) -> [SyncAction] {
        var actions: [SyncAction] = []

        // Build lookup maps
        let notionByThingsId = Dictionary(
            notionPages.filter { !$0.thingsId.isEmpty }.map { ($0.thingsId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let thingsById = Dictionary(
            thingsItems.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // --- Things items → sync to Notion ---
        for item in thingsItems {
            if let notionPage = notionByThingsId[item.id] {
                // Exists in both — check for changes
                let thingsChanged = hasThingsChanged(item: item, previousState: previousState)
                let notionChanged = hasNotionChanged(thingsId: item.id, page: notionPage, previousState: previousState)
                let statusMismatch = hasStatusMismatch(item: item, page: notionPage)

                if thingsChanged && notionChanged {
                    // Conflict: Things wins
                    actions.append(.updateNotion(pageId: notionPage.id, item))
                } else if thingsChanged {
                    actions.append(.updateNotion(pageId: notionPage.id, item))
                } else if notionChanged || statusMismatch {
                    // Notion changed or status is out of sync (e.g. from first-run snapshot)
                    actions.append(.updateThings(thingsId: item.id, notionPage))
                }
            } else {
                // New in Things → create in Notion
                actions.append(.createInNotion(item))
            }
        }

        // --- Notion pages removed from Things → archive ---
        for page in notionPages where !page.thingsId.isEmpty {
            if thingsById[page.thingsId] == nil,
               previousState.things[page.thingsId] != nil {
                actions.append(.archiveNotion(pageId: page.id, title: page.title))
            }
        }

        // --- New Notion pages (no Things ID) → create in Things ---
        for page in notionPages where page.thingsId.isEmpty {
            if previousState.notionPages[page.id] == nil {
                actions.append(.createInThings(page))
            }
        }

        return actions
    }

    // MARK: - Change detection

    private static func hasThingsChanged(item: ThingsItem, previousState: SyncState) -> Bool {
        guard let prev = previousState.things[item.id] else { return false }
        return item.name != prev.name || item.status != prev.status || item.notes != prev.notes
    }

    private static func hasNotionChanged(thingsId: String, page: NotionPage, previousState: SyncState) -> Bool {
        guard let prev = previousState.notion[thingsId] else { return false }
        return page.lastEdited != prev.lastEdited || page.status != prev.status
    }

    /// Detects items where Notion and Things status are out of sync,
    /// even if neither has "changed" since the last snapshot.
    /// This catches mismatches from first-run snapshots.
    private static func hasStatusMismatch(item: ThingsItem, page: NotionPage) -> Bool {
        let thingsDone = item.status == "Done"
        let notionDone = page.status == "Done"
        return thingsDone != notionDone
    }
}
