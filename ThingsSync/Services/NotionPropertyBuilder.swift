import Foundation

/// Builds Notion API property payloads from Things 3 items.
enum NotionPropertyBuilder {

    /// Builds a Notion properties dictionary for creating/updating a page.
    static func build(from item: ThingsItem) -> [String: Any] {
        var props: [String: Any] = [
            "Task": ["title": [["text": ["content": item.name]]]],
            "Status": ["select": ["name": item.status]],
            "Notes": ["rich_text": [["text": ["content": String(item.notes.prefix(2000))]]]],
            "Things ID": ["rich_text": [["text": ["content": item.id]]]],
        ]

        // Pass through project name from Things 3 directly
        if let project = item.project, !project.isEmpty {
            props["Project"] = ["select": ["name": project]]
        }

        if let due = item.dueDate, !due.isEmpty {
            props["Due Date"] = ["date": ["start": due]]
        }

        if let act = item.activationDate, !act.isEmpty {
            props["Activation Date"] = ["date": ["start": act]]
        }

        return props
    }
}
