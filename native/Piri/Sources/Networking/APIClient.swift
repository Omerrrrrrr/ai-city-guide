import Foundation

enum APIError: Error, LocalizedError {
    case server(status: Int, message: String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .server(let status, let message):
            return message ?? "Request failed (\(status))"
        case .decoding(let error):
            return "Failed to decode response: \(error)"
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

/// Thin URLSession wrapper standing in for the RN app's per-file `fetch`
/// calls (`mobile/src/api/*.ts`). One client, JSON in and out, errors
/// surfaced as `APIError` instead of ad-hoc `Error` throws.
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            // Explicit timeouts instead of URLSession.shared's defaults (60s
            // request / 7 day resource) -- a stalled request used to hang
            // every dependent screen (Scan, Ask Piri, Map) with no visible
            // failure for a full minute before anything could retry.
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: config)
        }
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func get<Response: Decodable>(_ path: String, query: [String: String?] = [:], bearerToken: String? = nil) async throws -> Response {
        try await send(path: path, method: "GET", query: query, body: Optional<EmptyBody>.none, bearerToken: bearerToken)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, bearerToken: String? = nil) async throws -> Response {
        try await send(path: path, method: "POST", query: [:], body: body, bearerToken: bearerToken)
    }

    func post<Response: Decodable>(_ path: String, bearerToken: String? = nil) async throws -> Response {
        try await send(path: path, method: "POST", query: [:], body: Optional<EmptyBody>.none, bearerToken: bearerToken)
    }

    func put<Body: Encodable, Response: Decodable>(_ path: String, body: Body, bearerToken: String? = nil) async throws -> Response {
        try await send(path: path, method: "PUT", query: [:], body: body, bearerToken: bearerToken)
    }

    func patch<Body: Encodable, Response: Decodable>(_ path: String, body: Body, bearerToken: String? = nil) async throws -> Response {
        try await send(path: path, method: "PATCH", query: [:], body: body, bearerToken: bearerToken)
    }

    private struct EmptyBody: Encodable {}

    /// Explicit allowlist of POST paths that are safe to retry even though
    /// POST is normally excluded below -- both are pure read-and-generate
    /// with nothing persisted server-side (no DB write, no side effect to
    /// double), unlike bookmarks/plans/sync POSTs which must stay
    /// single-shot. Matched by path, not a blanket "retry all POST" flag.
    private static let retryableWriteMethodPaths: Set<String> = ["/places/explain-poi", "/places/explain-poi/chat"]

    /// One retry, only for transient transport failures (dropped
    /// connection, timeout) on idempotent methods, plus the specific
    /// side-effect-free POST paths above -- never retries other POST/PUT,
    /// since replaying a write after an ambiguous failure could double it.
    private func performWithSingleRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            let retryableCodes: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .notConnectedToInternet]
            let isIdempotent = request.httpMethod == "GET" || request.httpMethod == nil
            let isRetryableWrite = request.httpMethod == "POST" && Self.retryableWriteMethodPaths.contains(request.url?.path ?? "")
            guard isIdempotent || isRetryableWrite, retryableCodes.contains(error.code) else { throw error }
            return try await session.data(for: request)
        }
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        query: [String: String?],
        body: Body?,
        bearerToken: String? = nil
    ) async throws -> Response {
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty {
            components.queryItems = items
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        if let body, !(body is EmptyBody) {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await performWithSingleRetry(request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: "No HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = try? decoder.decode(ServerErrorBody.self, from: data)
            // Prefer `message` over `error` when both are present — this
            // app's own handlers only ever send `{ error }`, but
            // `@fastify/rate-limit`'s default 429 body sends both, and its
            // `error` is just the generic, unlocalized HTTP reason phrase
            // ("Too Many Requests") while `message` actually states the
            // retry window ("Rate limit exceeded, retry in 1 minute").
            let message = body?.message ?? body?.error
            throw APIError.server(status: http.statusCode, message: message)
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

private struct ServerErrorBody: Decodable {
    var error: String?
    var message: String?
}

struct EmptyResponse: Decodable {}
