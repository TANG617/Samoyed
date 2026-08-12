import Foundation

enum RemoteRoutineConfigError: Error, Equatable, Sendable {
    case invalidURL
    case embeddedCredentials
    case insecureTransport
    case invalidResponse
    case unsuccessfulStatus(Int)
    case responseTooLarge(maximumBytes: Int)
    case invalidUTF8
}

extension RemoteRoutineConfigError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The routine URL must include a valid host."
        case .embeddedCredentials:
            return "Routine URLs cannot contain embedded usernames or passwords."
        case .insecureTransport:
            return "Routine imports require HTTPS. Debug builds also allow HTTP from localhost."
        case .invalidResponse:
            return "The routine server returned an invalid response."
        case let .unsuccessfulStatus(statusCode):
            return "The routine server returned HTTP status \(statusCode)."
        case let .responseTooLarge(maximumBytes):
            return "The routine config is larger than \(maximumBytes / 1024) KB."
        case .invalidUTF8:
            return "The routine config must be UTF-8 text."
        }
    }
}

struct SamoyedRemoteRoutineConfigLoader: Sendable {
    static let defaultMaximumBytes = 512 * 1024

    private let maximumBytes: Int
    private let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        session: URLSession? = nil,
        maximumBytes: Int = defaultMaximumBytes
    ) {
        self.maximumBytes = maximumBytes
        let resolvedSession = session ?? Self.makeEphemeralSession()
        dataLoader = { request in
            try await resolvedSession.data(for: request)
        }
    }

    init(
        maximumBytes: Int = defaultMaximumBytes,
        dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.maximumBytes = maximumBytes
        self.dataLoader = dataLoader
    }

    func load(from remoteURL: URL) async throws -> LoadedRemoteRoutineConfig {
        try Self.validate(remoteURL)

        var request = URLRequest(
            url: remoteURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpShouldHandleCookies = false
        request.setValue(
            "application/yaml, application/x-yaml, text/yaml, text/plain;q=0.9",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) = try await dataLoader(request)
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteRoutineConfigError.invalidResponse
        }
        guard let finalURL = httpResponse.url else {
            throw RemoteRoutineConfigError.invalidResponse
        }
        try Self.validate(finalURL)
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw RemoteRoutineConfigError.unsuccessfulStatus(httpResponse.statusCode)
        }
        guard data.count <= maximumBytes else {
            throw RemoteRoutineConfigError.responseTooLarge(maximumBytes: maximumBytes)
        }
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw RemoteRoutineConfigError.invalidUTF8
        }
        return LoadedRemoteRoutineConfig(yaml: yaml, sourceURL: finalURL)
    }

    static func validate(_ remoteURL: URL) throws {
        guard
            let scheme = remoteURL.scheme?.lowercased(),
            let host = remoteURL.host?.lowercased(),
            !host.isEmpty
        else {
            throw RemoteRoutineConfigError.invalidURL
        }
        guard remoteURL.user == nil, remoteURL.password == nil else {
            throw RemoteRoutineConfigError.embeddedCredentials
        }

        if scheme == "https" {
            return
        }

        #if DEBUG
        if scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) {
            return
        }
        #endif

        throw RemoteRoutineConfigError.insecureTransport
    }

    private static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}

struct LoadedRemoteRoutineConfig: Equatable, Sendable {
    let yaml: String
    let sourceURL: URL
}
