import Foundation

/// Quick CLI test harness — run with `--test` flag to exercise the sync pipeline
/// without the GUI. Prints results to stdout and exits.
enum CLITest {
    static func run() async {
        print("🔄 ThingsSync CLI Test")
        print("======================\n")

        // Step 1: Read Things 3
        print("Step 1: Reading Things 3 Today list via JXA...")
        let reader = ThingsReader()
        do {
            let items = try await reader.fetchTodayItems()
            print("  ✅ Found \(items.count) items")
            for item in items.prefix(5) {
                print("    - [\(item.status)] \(item.name)")
                if let proj = item.project { print("      Project: \(proj)") }
            }
            if items.count > 5 { print("    ... and \(items.count - 5) more") }
        } catch {
            print("  ❌ Error: \(error.localizedDescription)")
            return
        }

        // Step 2: Query Notion
        print("\nStep 2: Querying Notion database...")
        let apiKey = KeychainHelper.load(account: "notion-api-key")
            ?? ProcessInfo.processInfo.environment["NOTION_API_KEY"]
            ?? ""
        let dbId = KeychainHelper.load(account: "notion-database-id")
            ?? "27863485bf2c47638d7fad4001d0d9c9"

        guard !apiKey.isEmpty else {
            print("  ❌ No Notion API key found (set NOTION_API_KEY or save in Settings)")
            return
        }

        let client = NotionClient(apiKey: apiKey, databaseId: dbId)
        do {
            let pages = try await client.queryDatabase()
            print("  ✅ Found \(pages.count) pages")
            for page in pages.prefix(5) {
                print("    - [\(page.status)] \(page.title)")
                if !page.thingsId.isEmpty { print("      Things ID: \(page.thingsId)") }
            }
            if pages.count > 5 { print("    ... and \(pages.count - 5) more") }

            // Step 3: Diff
            print("\nStep 3: Computing diff (empty previous state → all items are new)...")
            let items = try await reader.fetchTodayItems()
            let actions = DiffResolver.resolve(
                thingsItems: items,
                notionPages: pages,
                previousState: .empty
            )
            print("  Actions to take: \(actions.count)")
            for action in actions.prefix(10) {
                switch action {
                case .createInNotion(let item):
                    print("    → Create in Notion: '\(item.name)'")
                case .updateNotion(_, let item):
                    print("    → Update in Notion: '\(item.name)'")
                case .updateThings(_, let page):
                    print("    ← Update in Things: '\(page.title)'")
                case .createInThings(let page):
                    print("    ← Create in Things: '\(page.title)'")
                case .archiveNotion(_, let title):
                    print("    → Archive in Notion: '\(title)'")
                }
            }
            if actions.count > 10 { print("    ... and \(actions.count - 10) more") }
        } catch {
            print("  ❌ Error: \(error.localizedDescription)")
        }

        print("\n✅ CLI test complete")
    }
}
