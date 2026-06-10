import Foundation
import os

public enum FetchError: Error, Equatable {
    case unauthorized
    case badResponse(Int)
    case network
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
    let loadCredentials: @Sendable () throws -> OAuthCredentials

    public init(loadCredentials: @escaping @Sendable () throws -> OAuthCredentials) {
        self.loadCredentials = loadCredentials
    }

    public func fetch() async throws -> UsageSnapshot {
        let creds = try loadCredentials()
        let req = UsageRequestBuilder.request(token: creds.accessToken)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            Self.log.warning("network error: \(error.localizedDescription)")
            throw FetchError.network
        }
        if let http = response as? HTTPURLResponse,
           let err = UsageRequestBuilder.mapStatus(http.statusCode) {
            Self.log.warning("usage endpoint HTTP \(http.statusCode)")
            throw err
        }
        do {
            return try UsageSnapshot.decode(from: data)
        } catch {
            Self.log.error("undecodable body: \(String(data: data.prefix(500), encoding: .utf8) ?? "<binary>")")
            throw FetchError.badResponse(200)
        }
    }
}
