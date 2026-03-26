import SwiftUI

/// First-launch setup wizard that walks the user through connecting
/// Things 3 and Notion step by step.
struct OnboardingView: View {
    @ObservedObject var syncEngine: SyncEngine
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var thingsConnected = false
    @State private var thingsError: String?
    @State private var notionConnected = false
    @State private var notionError: String?
    @State private var notionWorkspace: String?
    @State private var notionAccessToken: String?
    @State private var notionDatabaseId: String = ""
    @State private var availableDatabases: [(id: String, title: String)] = []
    @State private var isLoadingDatabases = false
    @State private var databaseVerified = false
    @State private var isTesting = false
    @StateObject private var oauth = NotionOAuth()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title)
                    .foregroundStyle(.blue)
                Text("ThingsSync Setup")
                    .font(.title2.bold())
            }
            .padding(.top, 24)
            .padding(.bottom, 8)

            Text("Connect Things 3 and Notion in 2 steps")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)

            // Progress
            HStack(spacing: 12) {
                StepIndicator(number: 1, title: "Things 3", isActive: currentStep == 0, isComplete: thingsConnected)
                Rectangle()
                    .fill(thingsConnected ? Color.green : Color.secondary.opacity(0.3))
                    .frame(height: 2)
                    .frame(maxWidth: 40)
                StepIndicator(number: 2, title: "Notion", isActive: currentStep == 1, isComplete: notionConnected)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)

            Divider()

            // Step content
            Group {
                if currentStep == 0 {
                    thingsStep
                } else {
                    notionStep
                }
            }
            .padding(24)

            Spacer()

            Divider()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                }
                Spacer()
                if currentStep == 0 {
                    Button("Next") {
                        currentStep = 1
                    }
                    .disabled(!thingsConnected)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Start Syncing") {
                        saveAndStart()
                    }
                    .disabled(!notionConnected || notionDatabaseId.isEmpty || notionAccessToken == nil || !databaseVerified)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
        .frame(width: 520, height: 480)
    }

    // MARK: - Step 1: Things 3

    private var thingsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect Things 3")
                .font(.headline)

            Text("ThingsSync reads your Today list and syncs it to Notion. Click the button below to verify Things 3 access.")
                .font(.body)
                .foregroundStyle(.secondary)

            if thingsConnected {
                Label("Things 3 connected — access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body.bold())
            } else {
                HStack(spacing: 12) {
                    Button {
                        testThingsConnection()
                    } label: {
                        Label("Test Connection", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTesting)

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                if let error = thingsError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("If prompted:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("• Click **OK** to allow ThingsSync to control Things 3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("• If denied, go to **System Settings → Privacy & Security → Automation** and enable Things 3 for ThingsSync")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Step 2: Notion

    private var notionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect Notion")
                .font(.headline)

            if notionConnected {
                Label("Connected to \(notionWorkspace ?? "Notion")", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body.bold())

                if isLoadingDatabases {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Finding your databases…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if availableDatabases.isEmpty {
                    Text("No databases found. Make sure you selected at least one page or database during authorization.")
                        .font(.callout)
                        .foregroundStyle(.orange)

                    Button {
                        notionConnected = false
                        notionAccessToken = nil
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                } else if !databaseVerified {
                    Text("Select the database to sync your tasks to:")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Picker("Database", selection: $notionDatabaseId) {
                        Text("Choose a database…").tag("")
                        ForEach(availableDatabases, id: \.id) { db in
                            Text(db.title).tag(db.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: notionDatabaseId) { _, newValue in
                        if !newValue.isEmpty {
                            databaseVerified = true
                        }
                    }
                } else {
                    Label("Database selected: \(availableDatabases.first(where: { $0.id == notionDatabaseId })?.title ?? notionDatabaseId)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.body.bold())
                }
            } else {
                Text("Click below to sign in with Notion. You'll choose which workspace and pages to share with ThingsSync.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        startOAuth()
                    } label: {
                        Label("Connect to Notion", systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(oauth.isAuthorizing)

                    if oauth.isAuthorizing {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Waiting for browser…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = notionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Actions

    private func testThingsConnection() {
        isTesting = true
        thingsError = nil
        Task {
            do {
                let reader = ThingsReader()
                _ = try await reader.fetchTodayItems()
                await MainActor.run {
                    thingsConnected = true
                    thingsError = nil
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    thingsError = error.localizedDescription
                    isTesting = false
                }
            }
        }
    }

    private func startOAuth() {
        notionError = nil
        Task {
            do {
                let result = try await oauth.authorize()
                await MainActor.run {
                    notionAccessToken = result.accessToken
                    notionWorkspace = result.workspaceName
                    notionConnected = true
                    notionError = nil
                    // If a template was duplicated, use it as the database
                    if let templateId = result.duplicatedTemplateId {
                        notionDatabaseId = templateId
                        databaseVerified = true
                    }
                }
                // Auto-fetch available databases
                await fetchDatabases(token: result.accessToken)
            } catch {
                await MainActor.run {
                    notionError = error.localizedDescription
                }
            }
        }
    }

    private func fetchDatabases(token: String) async {
        await MainActor.run { isLoadingDatabases = true }

        do {
            var url = URL(string: "https://api.notion.com/v1/search")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "filter": ["value": "database", "property": "object"]
            ])

            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]] {
                let databases: [(id: String, title: String)] = results.compactMap { db in
                    guard let id = db["id"] as? String,
                          let titleArray = (db["title"] as? [[String: Any]]),
                          let plainText = titleArray.first?["plain_text"] as? String else {
                        return nil
                    }
                    return (id: id, title: plainText)
                }

                await MainActor.run {
                    availableDatabases = databases
                    isLoadingDatabases = false
                    // Auto-select if there's only one
                    if databases.count == 1 {
                        notionDatabaseId = databases[0].id
                        databaseVerified = true
                    }
                }
            }
        } catch {
            await MainActor.run {
                isLoadingDatabases = false
                notionError = "Failed to load databases: \(error.localizedDescription)"
            }
        }
    }

    private func saveAndStart() {
        guard let token = notionAccessToken else { return }
        try? KeychainHelper.save(account: "notion-api-key", value: token)
        try? KeychainHelper.save(account: "notion-database-id", value: notionDatabaseId)
        try? KeychainHelper.save(account: "onboarding-complete", value: "true")
        syncEngine.start(apiKey: token, databaseId: notionDatabaseId)
        onComplete()
    }
}

// MARK: - Supporting Views

struct StepIndicator: View {
    let number: Int
    let title: String
    let isActive: Bool
    let isComplete: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green : isActive ? Color.blue : Color.secondary.opacity(0.3))
                    .frame(width: 28, height: 28)
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundStyle(isActive ? .white : .secondary)
                }
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(isActive || isComplete ? .primary : .secondary)
        }
    }
}

struct StepInstruction: View {
    let number: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.bold().monospaced())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue.opacity(0.8))
                .clipShape(Circle())
            Text(text)
                .font(.callout)
        }
    }
}
