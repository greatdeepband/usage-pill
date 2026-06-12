import Foundation

public struct DiscoveredField: Equatable, Sendable {
    public let path: String
    public let value: Double
    public init(path: String, value: Double) { self.path = path; self.value = value }
}

/// One GET, then flatten every numeric leaf (numbers + numeric strings,
/// booleans excluded) with its dot-path. Depth cap 6, field cap 50.
/// No logging — the request carries a user API key.
public struct ProviderProbe {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        self.session = session ?? {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: config)
        }()
    }

    public func discover(url: String, key: String,
                         headerName: String = "Authorization",
                         headerTemplate: String = "Bearer {key}") async throws -> [DiscoveredField] {
        guard let u = URL(string: url), let scheme = u.scheme,
              scheme == "https" || scheme == "http" else {
            throw FetchError.network
        }
        var req = URLRequest(url: u)
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        req.setValue(headerTemplate.replacingOccurrences(of: "{key}", with: key),
                     forHTTPHeaderField: headerName)
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
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw FetchError.undecodable
        }
        var fields: [DiscoveredField] = []
        Self.flatten(json, path: "", depth: 0, into: &fields)
        return fields
    }

    /// Internal for tests. Numeric detection delegates to DotPath so the
    /// probe and the engine agree on what counts as a number.
    static func flatten(_ node: Any, path: String, depth: Int, into out: inout [DiscoveredField]) {
        guard depth <= 6, out.count < 50 else { return }
        if let dict = node as? [String: Any] {
            for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                flatten(v, path: path.isEmpty ? k : "\(path).\(k)", depth: depth + 1, into: &out)
            }
        } else if let arr = node as? [Any] {
            for (i, v) in arr.enumerated() {
                flatten(v, path: path.isEmpty ? "\(i)" : "\(path).\(i)", depth: depth + 1, into: &out)
            }
        } else if let value = DotPath.resolve("v", in: ["v": node]) {
            out.append(DiscoveredField(path: path, value: value))
        }
    }
}
