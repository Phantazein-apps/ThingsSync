import Foundation

/// Handles all Notion API communication.
/// Supports both internal integration tokens and OAuth tokens.
actor NotionClient {
    private let apiBase = URL(string: "https://api.notion.com/v1")!
    private let apiVersion = "2022-06-28"
    private var apiKey: String
    private let databaseId: String
    private let session = URLSession.shared

    init(apiKey: String, databaseId: String) {
        self.apiKey = apiKey
        self.databaseId = databaseId
    }

    func updateApiKey(_ key: String) {
        self.apiKey = key
    }

    // MARK: - Query Database

    /// Fetches all pages from the configured Notion database (handles pagination).
    func queryDatabase() async throws -> [NotionPage] {
        var allPages: [NotionPage] = []
        var hasMore = true
        var startCursor: String? = nil

        while hasMore {
            var body: [String: Any] = ["page_size": 100]
            if let cursor = startCursor {
                body["start_cursor"] = cursor
            }

            let data = try await post(path: "/databases/\(databaseId)/query", body: body)
            let response = try JSONDecoder().decode(NotionQueryResponse.self, from: data)

            let pages = response.results.compactMap { raw -> NotionPage? in
                mapRawPage(raw)
            }

            allPages.append(contentsOf: pages)
            hasMore = response.hasMore
            startCursor = response.nextCursor
        }

        return allPages.filter { !$0.archived }
    }

    // MARK: - Create Page

    func createPage(properties: [String: Any]) async throws {
        let body: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": properties,
        ]
        _ = try await post(path: "/pages", body: body)
    }

    // MARK: - Update Page

    func updatePage(pageId: String, properties: [String: Any]) async throws {
        let body: [String: Any] = ["properties": properties]
        _ = try await patch(path: "/pages/\(pageId)", body: body)
    }

    // MARK: - Archive Page

    func archivePage(pageId: String) async throws {
        let body: [String: Any] = ["archived": true]
        _ = try await patch(path: "/pages/\(pageId)", body: body)
    }

    // MARK: - Networking

    private func post(path: String, body: [String: Any]) async throws -> Data {
        var request = makeRequest(path: path, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: request)
        return data
    }

    private func patch(path: String, body: [String: Any]) async throws -> Data {
        var request = makeRequest(path: path, method: "PATCH")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: request)
        return data
    }

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: apiBase.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    // MARK: - Mapping

    private func mapRawPage(_ raw: NotionPageRaw) -> NotionPage? {
        let props = raw.properties

        let title = props["Task"]?.title?.first?.text?.content ?? ""
        let thingsId = props["Things ID"]?.richText?.first?.text?.content ?? ""
        let status = props["Status"]?.select?.name ?? "Open"
        let project = props["Project"]?.select?.name ?? "No project"
        let notes = props["Notes"]?.richText?.first?.text?.content ?? ""
        let dueDate = props["Due Date"]?.date?.start
        let activationDate = props["Activation Date"]?.date?.start

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lastEdited = formatter.date(from: raw.lastEditedTime) ?? Date()

        return NotionPage(
            id: raw.id,
            thingsId: thingsId,
            title: title,
            status: status,
            project: project,
            notes: notes,
            dueDate: dueDate,
            activationDate: activationDate,
            lastEdited: lastEdited,
            archived: raw.archived
        )
    }
}
