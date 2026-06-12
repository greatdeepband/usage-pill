import Foundation

public protocol ProviderFetching: Sendable {
    func fetchValue(spec: ProviderSpec, key: String) async throws -> Double
}

/// Generic GET-JSON provider fetcher. Requests carry the user's API key —
/// nothing in this file logs, ever.
public struct ProviderEngine: ProviderFetching {
    private static let nonPersistingSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    private let session: URLSession
    public init(session: URLSession? = nil) { self.session = session ?? Self.nonPersistingSession }

    public func fetchValue(spec: ProviderSpec, key: String) async throws -> Double {
        guard let url = URL(string: spec.url), let scheme = url.scheme,
              scheme == "https" || scheme == "http" else {
            throw FetchError.network
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        req.setValue(spec.headerTemplate.replacingOccurrences(of: "{key}", with: key),
                     forHTTPHeaderField: spec.headerName)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            if error is CancellationError { throw error }
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw FetchError.network
        }
        guard let http = response as? HTTPURLResponse else { throw FetchError.network }
        if let err = UsageRequestBuilder.mapStatus(http.statusCode) {
            if case .rateLimited = err {
                throw FetchError.rateLimited(retryAfter: UsageRequestBuilder.retryAfterSeconds(
                    from: http.value(forHTTPHeaderField: "Retry-After")))
            }
            throw err
        }
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let primary = DotPath.resolve(spec.valuePath, in: json) else {
            throw FetchError.undecodable
        }
        var value = primary
        if let sub = spec.subtractPath {
            guard let subtrahend = DotPath.resolve(sub, in: json) else { throw FetchError.undecodable }
            value -= subtrahend
        }
        value *= spec.scale
        guard value.isFinite else { throw FetchError.undecodable }
        return value
    }
}
