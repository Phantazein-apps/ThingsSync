import AppKit
import Foundation

/// Reads Things 3 "Today" items via the AppleScript/JXA bridge.
/// Uses `lists.byId("TMTodayListSource")` which is locale-independent.
actor ThingsReader {

    enum ThingsError: Error, LocalizedError {
        case scriptFailed(String)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .scriptFailed(let msg): return "Things 3 script failed: \(msg)"
            case .decodingFailed: return "Failed to decode Things 3 response"
            }
        }
    }

    /// Fetches all to-dos from the Things 3 Today list.
    func fetchTodayItems() throws -> [ThingsItem] {
        let script = """
        var things = Application("Things3");
        var todayList = things.lists.byId("TMTodayListSource");
        var todos = todayList.toDos();
        if (!todos || todos.length === 0) { JSON.stringify([]); } else {
          var results = [];
          for (var i = 0; i < todos.length; i++) {
            var t = todos[i];
            var projName = null;
            try { var p = t.project(); if (p) projName = p.name(); } catch(e) {}
            var dd = null;
            try { var d = t.dueDate(); if (d) { dd = d.toISOString().slice(0,10); } } catch(e) {}
            var ad = null;
            try { var a = t.activationDate(); if (a) { ad = a.toISOString().slice(0,10); } } catch(e) {}
            results.push({
              id: t.id(),
              name: t.name(),
              status: t.status() === "completed" ? "Done" : "Open",
              notes: t.notes() || "",
              project: projName,
              dueDate: dd,
              activationDate: ad
            });
          }
          JSON.stringify(results);
        }
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw ThingsError.scriptFailed(errMsg)
        }

        // osascript output includes a trailing newline; trim it
        guard let jsonString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let jsonData = jsonString.data(using: .utf8) else {
            throw ThingsError.decodingFailed
        }

        return try JSONDecoder().decode([ThingsItem].self, from: jsonData)
    }

    /// Updates a Things 3 to-do via the `things:///update` URL scheme.
    func updateItem(id: String, title: String? = nil, notes: String? = nil, completed: Bool = false) {
        var components = URLComponents(string: "things:///update")!
        var queryItems = [URLQueryItem(name: "id", value: id)]
        if let title { queryItems.append(URLQueryItem(name: "title", value: title)) }
        if let notes { queryItems.append(URLQueryItem(name: "notes", value: notes)) }
        if completed { queryItems.append(URLQueryItem(name: "completed", value: "true")) }
        components.queryItems = queryItems

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Creates a new Things 3 to-do in Today via the `things:///add` URL scheme.
    func createItem(title: String, notes: String = "") {
        var components = URLComponents(string: "things:///add")!
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "notes", value: notes),
            URLQueryItem(name: "when", value: "today"),
            URLQueryItem(name: "reveal", value: "false"),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
}
