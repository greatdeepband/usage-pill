import Foundation
import os

public enum FetchError: Error, Equatable {
    case unauthorized
    case badResponse(Int)
    case network
    case undecodable
}

public enum UsageRequestBuilder {
    public static func request(token: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    public static func mapStatus(_ code: Int) -> FetchError? {
        switch code {
        case 200..<300: return nil
        case 401, 403: return .unauthorized
        default: return .badResponse(code)
        }
    }
}

public struct UsageFetcher: Sendable {
    private static let log = Logger(subsystem: "pl.bbi.claude-usage-pill", category: "fetch")
    private let loadCredentials: @Sendable () throws -> OAuthCredentials
    private let session: URLSession

    public init(
        loadCredentials: @escaping @Sendable () throws -> OAuthCredentials,
        session: URLSession = .shared
    ) {
        self.loadCredentials = loadCredentials
        self.session = session
    }

    public func fetch() async throws -> UsageSnapshot {
        let creds = try loadCredentials()
        let req = UsageRequestBuilder.request(token: creds.accessToken)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            // Preserve task cancellation so callers can handle it correctly.
            if error is CancellationError { throw error }
            Self.log.warning("network error: \(error.localizedDescription)")
            throw FetchError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw FetchError.network
        }
        if let err = UsageRequestBuilder.mapStatus(http.statusCode) {
            Self.log.warning("usage endpoint HTTP \(http.statusCode)")
            throw err
        }
        do {
            return try UsageSnapshot.decode(from: data)
        } catch {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            Self.log.error("undecodable body: \(body, privacy: .public)")
            throw FetchError.undecodable
        }
    }
}
