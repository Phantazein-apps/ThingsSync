import Foundation

/// Persisted state used to detect changes between sync cycles.
struct SyncState: Codable {
    var lastSync: Date?
    var things: [String: ThingsSnapshot]     // keyed by Things ID
    var notion: [String: NotionSnapshot]     // keyed by Things ID
    var notionPages: [String: String]        // page_id -> things_id

    static let empty = SyncState(lastSync: nil, things: [:], notion: [:], notionPages: [:])
}

struct ThingsSnapshot: Codable {
    let name: String
    let status: String
    let notes: String
}

struct NotionSnapshot: Codable {
    let pageId: String
    let title: String
    let status: String
    let notes: String
    let lastEdited: Date
}
