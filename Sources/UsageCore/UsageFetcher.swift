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
        // 401 = expired/rotated token → reload keychain and retry once.
        // 403 = scope/policy refusal — reloading the keychain cannot fix it;
        //       treating it as unauthorized would re-prompt every 10 min forever.
        case 401: return .unauthorized
        default: return .badResponse(code)
        }
    }
}

public struct UsageFetcher: Sendable {
    private static let log = Logger(subsystem: "pl.bbi.claude-usage-pill", category: "fetch")
    private let cache: CredentialsCache
    private let session: URLSession

    public init(cache: CredentialsCache, session: URLSession = .shared) {
        self.cache = cache
        self.session = session
    }

    public func fetch() async throws -> UsageSnapshot {
        let creds = try await cache.credentials()
        do {
            return try await fetchOnce(token: creds.accessToken)
        } catch FetchError.unauthorized {
            // Token may have rotated; ask the cache to reload (throttled).
            if let fresh = try await cache.reloadAfterUnauthorized() {
                return try await fetchOnce(token: fresh.accessToken)
            }
            throw FetchError.unauthorized
        }
    }

    // MARK: - Private

    private func fetchOnce(token: String) async throws -> UsageSnapshot {
        let req = UsageRequestBuilder.request(token: token)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            // Real-world cancellation surfaces as URLError(.cancelled); normalize it
            // so callers (UsageModel) can leave state untouched on teardown.
            if error is CancellationError { throw error }
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
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
