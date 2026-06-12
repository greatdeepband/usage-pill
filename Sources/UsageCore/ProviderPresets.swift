import Foundation

/// Bundled templates for the "+ Add provider…" catalog. The key is supplied
/// by the user at add time; the id is freshly generated per add. ONLY presets
/// whose live probe confirmed the endpoint shape ship here (plan Task 1) —
/// everything else is reachable through the custom-provider flow, with
/// recipes in the README.
public enum ProviderPresets {
    public struct Preset: Sendable {
        public let name: String
        public let make: @Sendable () -> ProviderSpec
        public init(name: String, make: @escaping @Sendable () -> ProviderSpec) {
            self.name = name
            self.make = make
        }
    }

    public static let all: [Preset] = [
        Preset(name: "DeepSeek balance") {
            ProviderSpec(
                id: UUID(), displayName: "DeepSeek", adapter: .generic,
                url: "https://api.deepseek.com/user/balance",
                headerName: "Authorization", headerTemplate: "Bearer {key}",
                valuePath: "balance_infos.0.total_balance",
                subtractPath: nil, scale: 1,
                valueKind: .currency, currencyCode: "USD", warnBelow: nil,
                visibility: .pinned
            )
        },
        // OpenRouter / MiniMax / OpenAI spend / Anthropic spend: deferred
        // per the 2026-06-12 probe (no keys to verify against). Add here
        // only with a fresh probe — see ProviderFixtures.swift.
    ]
}
