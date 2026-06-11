import Foundation

public struct Profile: Equatable, Sendable {
    public let email: String?
    public init(email: String?) { self.email = email }
}

public extension Profile {
    static func decode(from data: Data) throws -> Profile {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let root = any as? [String: Any] else {
            throw UsageDecodingError.invalidJSON
        }
        let account = root["account"] as? [String: Any]
        let raw = (account?["email"] ?? account?["email_address"]
                   ?? root["email_address"] ?? root["email"]) as? String
        let email = raw.flatMap { $0.isEmpty ? nil : $0 }
        return Profile(email: email)
    }
}

public enum ProfileRequestBuilder {
    public static func request(token: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }
}

/// Mirrors UsageFetcher (shared CredentialsCache, one 401-retry). The small
/// duplication between the two fetchers is accepted — two thin structs beat a
/// premature generic transport layer.
public struct ProfileFetcher: Sendable {
    private let cache: CredentialsCache
    private let session: URLSession

    public init(cache: CredentialsCache, session: URLSession = .shared) {
        self.cache = cache
        self.session = session
    }

    public func fetch() async throws -> Profile {
        let creds = try await cache.credentials()
        do {
            return try await fetchOnce(token: creds.accessToken)
        } catch FetchError.unauthorized {
            if let fresh = try await cache.reloadAfterUnauthorized() {
                return try await fetchOnce(token: fresh.accessToken)
            }
            throw FetchError.unauthorized
        }
    }

    private func fetchOnce(token: String) async throws -> Profile {
        let req = ProfileRequestBuilder.request(token: token)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            if error is CancellationError { throw error }
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw FetchError.network
        }
        guard let http = response as? HTTPURLResponse else { throw FetchError.network }
        if let err = UsageRequestBuilder.mapStatus(http.statusCode) { throw err }
        do {
            return try Profile.decode(from: data)
        } catch {
            // Deliberately NO body logging, unlike UsageFetcher — a profile
            // body contains the email; it must never reach the log.
            throw FetchError.undecodable
        }
    }
}
