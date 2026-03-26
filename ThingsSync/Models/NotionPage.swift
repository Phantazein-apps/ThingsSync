import Foundation

/// A page from the Notion "Things 3 Today" database.
struct NotionPage: Codable, Identifiable {
    let id: String          // Notion page ID
    let thingsId: String
    let title: String
    let status: String
    let project: String
    let notes: String
    let dueDate: String?
    let activationDate: String?
    let lastEdited: Date
    let archived: Bool
}

/// Wrapper for Notion API query responses.
struct NotionQueryResponse: Codable {
    let results: [NotionPageRaw]
    let hasMore: Bool
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

/// Raw Notion API page representation (before mapping to NotionPage).
struct NotionPageRaw: Codable {
    let id: String
    let archived: Bool
    let lastEditedTime: String
    let properties: [String: NotionProperty]

    enum CodingKeys: String, CodingKey {
        case id, archived, properties
        case lastEditedTime = "last_edited_time"
    }
}

/// Minimal Notion property representation for the fields we care about.
struct NotionProperty: Codable {
    let title: [NotionRichText]?
    let richText: [NotionRichText]?
    let select: NotionSelect?
    let date: NotionDate?

    enum CodingKeys: String, CodingKey {
        case title
        case richText = "rich_text"
        case select, date
    }
}

struct NotionRichText: Codable {
    let text: NotionTextContent?
}

struct NotionTextContent: Codable {
    let content: String
}

struct NotionSelect: Codable {
    let name: String
}

struct NotionDate: Codable {
    let start: String?
}
