import AppKit
import Foundation

/// Reads and writes Things 3 items via AppleScript/JXA.
/// No auth token needed — AppleScript has full access.
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

    // MARK: - Read

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
        return try runJXA(script)
    }

    // MARK: - Write

    /// Creates a new Things 3 to-do in Today via AppleScript.
    /// Returns the new todo's ID.
    @discardableResult
    func createItem(title: String, notes: String = "") throws -> String {
        let escapedTitle = escapeAppleScript(title)
        let escapedNotes = escapeAppleScript(notes)

        let script = """
        tell application "Things3"
            set newTodo to make new to do with properties {name:"\(escapedTitle)", notes:"\(escapedNotes)"}
            move newTodo to list "Today"
            get id of newTodo
        end tell
        """
        return try runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Updates an existing Things 3 to-do via AppleScript.
    func updateItem(id: String, title: String? = nil, notes: String? = nil, completed: Bool = false) throws {
        var commands: [String] = []
        commands.append("set theTodo to to do id \"\(id)\"")

        if let title {
            commands.append("set name of theTodo to \"\(escapeAppleScript(title))\"")
        }
        if let notes {
            commands.append("set notes of theTodo to \"\(escapeAppleScript(notes))\"")
        }
        if completed {
            commands.append("set status of theTodo to completed")
        }

        let script = """
        tell application "Things3"
            \(commands.joined(separator: "\n            "))
        end tell
        """
        _ = try runAppleScript(script)
    }

    // MARK: - Script execution

    private func runJXA<T: Decodable>(_ script: String) throws -> T {
        let output = try runProcess(args: ["-l", "JavaScript", "-e", script])

        guard let jsonString = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty,
              let jsonData = jsonString.data(using: .utf8) else {
            throw ThingsError.decodingFailed
        }

        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    private func runAppleScript(_ script: String) throws -> String {
        return try runProcess(args: ["-e", script])
    }

    private func runProcess(args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = args

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

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func escapeAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
