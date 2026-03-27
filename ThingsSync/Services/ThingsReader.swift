import AppKit
import Foundation

/// Reads and writes Things 3 items via SQLite (fast) with AppleScript fallback.
/// SQLite reads avoid Apple event contention with other Things 3 clients (MCP, etc).
actor ThingsReader {

    enum ThingsError: Error, LocalizedError {
        case scriptFailed(String)
        case scriptTimedOut
        case todoNotFound(String)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .scriptFailed(let msg): return "Things 3 script failed: \(msg)"
            case .scriptTimedOut: return "Things 3 script timed out"
            case .todoNotFound(let id): return "Things 3 to-do not found: \(id)"
            case .decodingFailed: return "Failed to decode Things 3 response"
            }
        }

        var isTodoNotFound: Bool {
            if case .todoNotFound = self { return true }
            return false
        }
    }

    /// Throttle delay between consecutive AppleScript writes (seconds)
    private static let writeThrottleDelay: TimeInterval = 0.3

    /// Timeout for osascript processes (seconds)
    private static let processTimeout: TimeInterval = 30

    private var lastWriteTime: Date = .distantPast

    // MARK: - Read

    /// Fetches all to-dos from the Things 3 Today list.
    /// Uses SQLite for speed and to avoid Apple event contention.
    /// Falls back to JXA if the database file is inaccessible.
    func fetchTodayItems() throws -> [ThingsItem] {
        if let items = try? fetchTodayViaSQLite() {
            return items
        }
        return try fetchTodayViaJXA()
    }

    /// Direct SQLite read — fast, no Apple events, no contention.
    private func fetchTodayViaSQLite() throws -> [ThingsItem] {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac/ThingsData-RXWG2/Things Database.thingsdatabase/main.sqlite")
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw ThingsError.scriptFailed("Things 3 database not found")
        }

        let query = """
        SELECT
          TASK.uuid AS id,
          TASK.title AS name,
          CASE WHEN TASK.status = 3 THEN 'Done' ELSE 'Open' END AS status,
          COALESCE(TASK.notes, '') AS notes,
          PROJECT.title AS project,
          CASE WHEN TASK.deadline IS NOT NULL THEN date(TASK.deadline, 'unixepoch') ELSE NULL END AS dueDate,
          CASE WHEN TASK.startDate IS NOT NULL THEN date(TASK.startDate, 'unixepoch') ELSE NULL END AS activationDate
        FROM TMTask AS TASK
        LEFT JOIN TMTask AS PROJECT ON TASK.project = PROJECT.uuid
        WHERE TASK.trashed = 0
          AND TASK.status = 0
          AND TASK.type = 0
          AND TASK.start = 1
          AND TASK.startDate IS NOT NULL
        ORDER BY TASK.todayIndex
        """

        let output = try runProcess(
            executable: "/usr/bin/sqlite3",
            args: ["-json", "file:\(dbPath)?mode=ro", query],
            timeout: 10
        )

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return []
        }

        return try JSONDecoder().decode([ThingsItem].self, from: data)
    }

    /// JXA fallback — works without Full Disk Access but susceptible to timeouts.
    private func fetchTodayViaJXA() throws -> [ThingsItem] {
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
        try throttleWrite()
        let escapedTitle = escapeAppleScript(title)
        let escapedNotes = escapeAppleScript(notes)

        let script = """
        tell application "Things3"
            with timeout of 30 seconds
                set newTodo to make new to do with properties {name:"\(escapedTitle)", notes:"\(escapedNotes)"}
                move newTodo to list "Today"
                get id of newTodo
            end timeout
        end tell
        """
        return try runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Updates an existing Things 3 to-do via AppleScript.
    /// Throws `todoNotFound` if the to-do no longer exists in Things 3.
    func updateItem(id: String, title: String? = nil, notes: String? = nil, completed: Bool = false) throws {
        try throttleWrite()
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
            with timeout of 30 seconds
                \(commands.joined(separator: "\n                "))
            end timeout
        end tell
        """
        do {
            _ = try runAppleScript(script)
        } catch ThingsError.scriptFailed(let msg) where msg.contains("-1728") {
            throw ThingsError.todoNotFound(id)
        }
    }

    // MARK: - Throttling

    /// Ensures a minimum delay between AppleScript write operations
    /// to prevent overwhelming Things 3 with rapid-fire Apple events.
    private func throttleWrite() throws {
        let elapsed = Date().timeIntervalSince(lastWriteTime)
        if elapsed < Self.writeThrottleDelay {
            Thread.sleep(forTimeInterval: Self.writeThrottleDelay - elapsed)
        }
        lastWriteTime = Date()
    }

    // MARK: - Script execution

    private func runJXA<T: Decodable>(_ script: String) throws -> T {
        let output = try runProcess(
            executable: "/usr/bin/osascript",
            args: ["-l", "JavaScript", "-e", script],
            timeout: Self.processTimeout
        )

        guard let jsonString = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty,
              let jsonData = jsonString.data(using: .utf8) else {
            throw ThingsError.decodingFailed
        }

        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    private func runAppleScript(_ script: String) throws -> String {
        return try runProcess(
            executable: "/usr/bin/osascript",
            args: ["-e", script],
            timeout: Self.processTimeout
        )
    }

    private func runProcess(executable: String, args: [String], timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        try process.run()

        // Kill the process if it exceeds the timeout
        let deadline = DispatchTime.now() + timeout
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()

        // Check for timeout (SIGTERM exit = 15)
        if process.terminationReason == .uncaughtSignal {
            throw ThingsError.scriptTimedOut
        }

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
