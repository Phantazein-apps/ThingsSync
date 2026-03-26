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
