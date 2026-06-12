import Foundation

/// Month-to-date OpenAI API spend via the Costs API (org ADMIN key).
/// Native adapter: needs date math + bucket summing the generic engine
/// doesn't do. No logging — the request carries the user's admin key.
public struct OpenAISpendAdapter: ProviderFetching {
    private static let nonPersistingSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    private let session: URLSession
    private let now: @Sendable () -> Date

    public init(session: URLSession? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session ?? Self.nonPersistingSession
        self.now = now
    }

    public func fetchValue(spec: ProviderSpec, key: String) async throws -> Double {
        var comps = Calendar(identifier: .gregorian)
            .dateComponents(in: TimeZone(identifier: "UTC")!, from: now())
        comps.day = 1; comps.hour = 0; comps.minute = 0; comps.second = 0; comps.nanosecond = 0
        guard let monthStart = comps.date,
              var url = URLComponents(string: "https://api.openai.com/v1/organization/costs")
        else { throw FetchError.network }
        url.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(monthStart.timeIntervalSince1970))),
            URLQueryItem(name: "limit", value: "31"),
        ]
        guard let requestURL = url.url else { throw FetchError.network }
        var req = URLRequest(url: requestURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
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
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = root["data"] as? [[String: Any]] else { throw FetchError.undecodable }
        var total = 0.0
        for bucket in buckets {
            for result in (bucket["results"] as? [[String: Any]]) ?? [] {
                if let amount = result["amount"] as? [String: Any],
                   let v = DotPath.resolve("value", in: amount) { total += v }
            }
        }
        guard total.isFinite else { throw FetchError.undecodable }
        return total
    }
}
