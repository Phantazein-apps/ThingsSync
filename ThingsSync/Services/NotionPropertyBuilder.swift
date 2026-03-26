import Foundation

/// Builds Notion API property payloads from Things 3 items.
enum NotionPropertyBuilder {

    /// Builds a Notion properties dictionary for creating/updating a page.
    /// When `previousStatus` is provided, Status is only included if it changed
    /// in Things — this preserves custom Notion statuses like "App Projects".
    static func build(from item: ThingsItem, previousStatus: String? = nil) -> [String: Any] {
        var props: [String: Any] = [
            "Task": ["title": [["text": ["content": item.name]]]],
            "Notes": ["rich_text": [["text": ["content": String(item.notes.prefix(2000))]]]],
            "Things ID": ["rich_text": [["text": ["content": item.id]]]],
        ]

        // Only push Status to Notion if it actually changed in Things
        // This preserves custom Notion statuses (e.g. "App Projects", "In Progress")
        if let prev = previousStatus {
            if item.status != prev {
                props["Status"] = ["select": ["name": item.status]]
            }
        } else {
            // New item — always set status
            props["Status"] = ["select": ["name": item.status]]
        }

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
