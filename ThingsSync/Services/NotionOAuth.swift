import AppKit
import Foundation

/// Handles the Notion OAuth PKCE flow using a local HTTP callback server.
/// 1. Opens browser to Notion authorization URL
/// 2. Listens on localhost:21547 for the callback
/// 3. Exchanges the authorization code for an access token
/// 4. Returns the token and workspace info
class NotionOAuth: ObservableObject {
    static let clientId = "32fd872b-594c-8174-8cf6-0037a5c85616"
    // Loaded at build time from Secrets.swift (gitignored)
    private static let clientSecret = NotionSecrets.clientSecret
    private static let redirectURI = "http://localhost:21547/callback"
    private static let port: UInt16 = 21547

    @Published var isAuthorizing = false
    @Published var error: String?

    struct OAuthResult {
        let accessToken: String
        let workspaceName: String
        let workspaceId: String
        let botId: String
        let duplicatedTemplateId: String?
    }

    /// Starts the OAuth flow: opens browser + starts local server to catch callback.
    func authorize() async throws -> OAuthResult {
        await MainActor.run {
            isAuthorizing = true
            error = nil
        }

        defer {
            Task { @MainActor in
                isAuthorizing = false
            }
        }

        // Generate state parameter for CSRF protection
        let state = UUID().uuidString

        // Build authorization URL
        var components = URLComponents(string: "https://api.notion.com/v1/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user"),
            URLQueryItem(name: "state", value: state),
        ]

        guard let authURL = components.url else {
            throw OAuthError.invalidURL
        }

        // Start local HTTP server to catch the callback
        let server = LocalCallbackServer(port: Self.port)
        try server.start()

        // Open browser
        await MainActor.run {
            NSWorkspace.shared.open(authURL)
        }

        // Wait for the callback (timeout after 5 minutes)
        let callbackResult = try await server.waitForCallback(timeout: 300)
        server.stop()

        // Validate state
        guard callbackResult.state == state else {
            throw OAuthError.stateMismatch
        }

        guard let code = callbackResult.code else {
            throw OAuthError.noCode(callbackResult.error ?? "Unknown error")
        }

        // Exchange code for token
        let result = try await exchangeCodeForToken(code: code)
        return result
    }

    /// Exchanges the authorization code for an access token.
    private func exchangeCodeForToken(code: String) async throws -> OAuthResult {
        let url = URL(string: "https://api.notion.com/v1/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Basic auth: client_id:client_secret
        let credentials = "\(Self.clientId):\(Self.clientSecret)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Token exchange failed"
            throw OAuthError.tokenExchangeFailed(errorMsg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw OAuthError.invalidTokenResponse
        }

        let workspace = json["workspace_name"] as? String ?? ""
        let workspaceId = json["workspace_id"] as? String ?? ""
        let botId = json["bot_id"] as? String ?? ""
        let duplicatedTemplateId = json["duplicated_template_id"] as? String

        return OAuthResult(
            accessToken: accessToken,
            workspaceName: workspace,
            workspaceId: workspaceId,
            botId: botId,
            duplicatedTemplateId: duplicatedTemplateId
        )
    }

    enum OAuthError: Error, LocalizedError {
        case invalidURL
        case stateMismatch
        case noCode(String)
        case tokenExchangeFailed(String)
        case invalidTokenResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Failed to build authorization URL"
            case .stateMismatch: return "Security check failed (state mismatch)"
            case .noCode(let msg): return "Authorization denied: \(msg)"
            case .tokenExchangeFailed(let msg): return "Token exchange failed: \(msg)"
            case .invalidTokenResponse: return "Invalid token response from Notion"
            }
        }
    }
}

// MARK: - Local HTTP Callback Server

/// Minimal HTTP server that listens on localhost for the OAuth callback.
private class LocalCallbackServer {
    private let port: UInt16
    private var serverSocket: Int32 = -1
    private var continuation: CheckedContinuation<CallbackResult, Error>?

    struct CallbackResult {
        let code: String?
        let state: String?
        let error: String?
    }

    init(port: UInt16) {
        self.port = port
    }

    func start() throws {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { throw OAuthServerError.socketCreationFailed }

        var reuse: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult >= 0 else { throw OAuthServerError.bindFailed(port) }

        guard listen(serverSocket, 1) >= 0 else { throw OAuthServerError.listenFailed }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> CallbackResult {
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont

            DispatchQueue.global(qos: .userInitiated).async { [self] in
                // Set socket timeout
                var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
                setsockopt(serverSocket, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                let clientSocket = accept(serverSocket, nil, nil)
                guard clientSocket >= 0 else {
                    continuation?.resume(throwing: OAuthServerError.timeout)
                    return
                }

                // Read the HTTP request
                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = read(clientSocket, &buffer, buffer.count)
                let request = bytesRead > 0 ? String(bytes: buffer[..<bytesRead], encoding: .utf8) ?? "" : ""

                // Parse the query parameters from GET /callback?code=...&state=...
                let result = parseCallback(request)

                // Send a nice HTML response
                let html: String
                if result.code != nil {
                    html = """
                    <html><body style="font-family:-apple-system;text-align:center;padding:60px;background:#1a1a2e;color:#fff">
                    <h1>✅ Connected to Notion!</h1>
                    <p>You can close this tab and return to ThingsSync.</p>
                    <script>setTimeout(()=>window.close(),2000)</script>
                    </body></html>
                    """
                } else {
                    html = """
                    <html><body style="font-family:-apple-system;text-align:center;padding:60px;background:#1a1a2e;color:#fff">
                    <h1>❌ Authorization Failed</h1>
                    <p>\(result.error ?? "Unknown error")</p>
                    </body></html>
                    """
                }

                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n\(html)"
                _ = response.withCString { write(clientSocket, $0, strlen($0)) }
                close(clientSocket)

                continuation?.resume(returning: result)
            }
        }
    }

    func stop() {
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }

    private func parseCallback(_ request: String) -> CallbackResult {
        // Extract path from "GET /callback?code=xxx&state=yyy HTTP/1.1"
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              let pathPart = firstLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: String(pathPart)) else {
            return CallbackResult(code: nil, state: nil, error: "Failed to parse callback")
        }

        let items = components.queryItems ?? []
        let code = items.first(where: { $0.name == "code" })?.value
        let state = items.first(where: { $0.name == "state" })?.value
        let error = items.first(where: { $0.name == "error" })?.value

        return CallbackResult(code: code, state: state, error: error)
    }

    enum OAuthServerError: Error, LocalizedError {
        case socketCreationFailed
        case bindFailed(UInt16)
        case listenFailed
        case timeout

        var errorDescription: String? {
            switch self {
            case .socketCreationFailed: return "Failed to create server socket"
            case .bindFailed(let port): return "Failed to bind to port \(port)"
            case .listenFailed: return "Failed to listen on socket"
            case .timeout: return "Authorization timed out — please try again"
            }
        }
    }
}
