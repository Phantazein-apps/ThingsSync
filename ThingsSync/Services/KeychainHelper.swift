import Foundation

/// Credential storage.
/// During development: uses a JSON config file (~/.things3-notion-sync/credentials.json)
/// For release builds: will use macOS Keychain (requires code signing).
enum KeychainHelper {

    private static let credentialsURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".things3-notion-sync")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("credentials.json")
    }()

    static func save(account: String, value: String) throws {
        var creds = loadAll()
        creds[account] = value
        let data = try JSONSerialization.data(withJSONObject: creds, options: .prettyPrinted)
        try data.write(to: credentialsURL, options: .atomic)
        // Restrict to owner-only read/write
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialsURL.path
        )
    }

    static func load(account: String) -> String? {
        loadAll()[account]
    }

    static func delete(account: String) {
        var creds = loadAll()
        creds.removeValue(forKey: account)
        if let data = try? JSONSerialization.data(withJSONObject: creds, options: .prettyPrinted) {
            try? data.write(to: credentialsURL, options: .atomic)
        }
    }

    private static func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: credentialsURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }

    enum KeychainError: Error, LocalizedError {
        case saveFailed(OSStatus)
        var errorDescription: String? {
            "Credential save failed: \(self)"
        }
    }
}
