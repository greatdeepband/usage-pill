import Foundation
import os

public struct ProviderSpec: Codable, Equatable, Sendable, Identifiable {
    public enum ValueKind: String, Codable, Sendable { case currency, number }
    public enum Visibility: String, Codable, Sendable { case pinned, expandedOnly, hidden }
    /// generic = ProviderEngine; spend adapters are native (plan Task 7).
    public enum AdapterKind: String, Codable, Sendable { case generic, openAISpend, anthropicSpend }

    public var id: UUID
    public var displayName: String
    public var adapter: AdapterKind
    public var url: String
    public var headerName: String      // e.g. "Authorization" or "x-api-key"
    public var headerTemplate: String  // "Bearer {key}" or "{key}"
    public var valuePath: String
    public var subtractPath: String?   // value = valuePath − subtractPath
    public var scale: Double           // multiply after extraction
    public var valueKind: ValueKind
    public var currencyCode: String?
    public var warnBelow: Double?
    public var visibility: Visibility
    /// Optional per-row accent (hex "RRGGBB"); nil → the default sage.
    /// Warn-threshold amber always overrides the accent in the UI.
    public var accentHex: String?

    public init(id: UUID, displayName: String, adapter: AdapterKind, url: String,
                headerName: String, headerTemplate: String, valuePath: String,
                subtractPath: String?, scale: Double, valueKind: ValueKind,
                currencyCode: String?, warnBelow: Double?, visibility: Visibility,
                accentHex: String? = nil) {
        self.id = id; self.displayName = displayName; self.adapter = adapter
        self.url = url; self.headerName = headerName; self.headerTemplate = headerTemplate
        self.valuePath = valuePath; self.subtractPath = subtractPath; self.scale = scale
        self.valueKind = valueKind; self.currencyCode = currencyCode
        self.warnBelow = warnBelow; self.visibility = visibility
        self.accentHex = accentHex
    }
}

/// Persists [ProviderSpec] as a JSON blob in UserDefaults. NEVER contains API
/// keys (keys live in the keychain, keyed by spec id). Corrupt entries are
/// dropped INDIVIDUALLY so one bad record can't take out the rest.
public struct ProviderSpecStore {
    public static let key = "providers.specs"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> [ProviderSpec] {
        guard let blob = defaults.data(forKey: Self.key),
              let raw = (try? JSONSerialization.jsonObject(with: blob)) as? [Any] else { return [] }
        let decoder = JSONDecoder()
        var dropped = 0
        defer {
            if dropped > 0 {
                Logger(subsystem: "pl.bbi.usage-pill", category: "specs")
                    .warning("dropped \(dropped) corrupt provider spec entries")
            }
        }
        return raw.compactMap { element in
            guard let data = try? JSONSerialization.data(withJSONObject: element),
                  let spec = try? decoder.decode(ProviderSpec.self, from: data) else {
                dropped += 1
                return nil
            }
            return spec
        }
    }

    public func save(_ specs: [ProviderSpec]) {
        if let blob = try? JSONEncoder().encode(specs) {
            defaults.set(blob, forKey: Self.key)
        }
    }
}
