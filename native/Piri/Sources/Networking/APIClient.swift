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

    init(session: URLSession = .shared) {
        self.session = session
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

    private struct EmptyBody: Encodable {}

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
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: "No HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ServerErrorBody.self, from: data))?.error
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
}

struct EmptyResponse: Decodable {}
