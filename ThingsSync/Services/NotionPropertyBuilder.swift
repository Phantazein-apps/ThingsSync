import Foundation

/// Builds Notion API property payloads from Things 3 items.
enum NotionPropertyBuilder {

    /// Maps Things 3 project names to Notion project select options.
    static func mapProject(_ project: String?) -> String {
        guard let project else { return "No project" }
        switch project {
        case "Phantazein": return "Phantazein"
        case "Claude projects": return "Claude projects"
        case let p where p.lowercased().contains("urgent"): return "Urgent"
        default: return "No project"
        }
    }

    /// Builds a Notion properties dictionary for creating/updating a page.
    static func build(from item: ThingsItem) -> [String: Any] {
        let mappedProject = mapProject(item.project)

        var props: [String: Any] = [
            "Task": ["title": [["text": ["content": item.name]]]],
            "Status": ["select": ["name": item.status]],
            "Project": ["select": ["name": mappedProject]],
            "Notes": ["rich_text": [["text": ["content": item.notes]]]],
            "Things ID": ["rich_text": [["text": ["content": item.id]]]],
        ]

        if let due = item.dueDate, !due.isEmpty {
            props["Due Date"] = ["date": ["start": due]]
        }

        if let act = item.activationDate, !act.isEmpty {
            props["Activation Date"] = ["date": ["start": act]]
        }

        return props
    }
}
