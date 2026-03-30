import Foundation

/// A to-do item from Things 3, read via AppleScript bridge.
struct ThingsItem: Codable, Identifiable {
    let id: String
    let name: String
    let status: String      // "Open" or "Done"
    let notes: String
    let project: String?
    let dueDate: String?
    let activationDate: String?
}

/// A project from Things 3.
struct ThingsProject: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

/// An area from Things 3.
struct ThingsArea: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

/// How to filter which Things 3 items to sync.
enum SyncFilterMode: String, Codable, CaseIterable {
    case all = "all"
    case byProject = "byProject"
    case byArea = "byArea"
}
