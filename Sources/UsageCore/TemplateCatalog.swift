import Foundation

/// The Add Provider catalog: every known provider as a fill-in-the-blank
/// template. Adding is ALWAYS live-verified (full templates by the add-time
/// fetch, guided ones by the probe → pick-a-number flow), so an imperfect
/// template can never create a broken row — worst case is a plain-language
/// error and nothing saved.
public struct ProviderTemplate: Sendable {
    public enum Group: Sendable { case plans, balances }
    public enum Kind: Sendable {
        case full(@Sendable () -> ProviderSpec)  // complete spec; name+key step only
        case guided(GuidedPrefill)               // custom flow, pre-filled
        case claudePlan                          // path-A facade (app layer implements)
        case openAISpend                         // native adapter add path
    }
    public struct GuidedPrefill: Sendable {
        public let url: String
        public let headerName: String
        public let headerTemplate: String
        public let suggestedName: String
        public let valueKind: ProviderSpec.ValueKind
        public let currencyCode: String?
        public init(url: String, headerName: String = "Authorization",
                    headerTemplate: String = "Bearer {key}", suggestedName: String,
                    valueKind: ProviderSpec.ValueKind, currencyCode: String? = nil) {
            self.url = url; self.headerName = headerName
            self.headerTemplate = headerTemplate; self.suggestedName = suggestedName
            self.valueKind = valueKind; self.currencyCode = currencyCode
        }
    }
    public let name: String
    public let subtitle: String
    public let keyURL: URL?
    public let group: Group
    public let kind: Kind
    public init(name: String, subtitle: String, keyURL: URL?, group: Group, kind: Kind) {
        self.name = name; self.subtitle = subtitle; self.keyURL = keyURL
        self.group = group; self.kind = kind
    }
}

public enum TemplateCatalog {
    public static func template(named name: String) -> ProviderTemplate? {
        all.first { $0.name == name }
    }

    public static let all: [ProviderTemplate] = [
        ProviderTemplate(
            name: "Claude plan",
            subtitle: "via Claude Code — uses your existing sign-in",
            keyURL: nil, group: .plans, kind: .claudePlan),
        ProviderTemplate(
            name: "z.ai GLM — 5-hour quota",
            subtitle: "coding-plan quota; raw token auth pre-set",
            keyURL: URL(string: "https://z.ai/manage-apikey/apikey-list"),
            group: .plans,
            kind: .guided(.init(url: "https://api.z.ai/api/monitor/usage/quota/limit",
                                headerTemplate: "{key}", suggestedName: "GLM 5h",
                                valueKind: .number))),
        ProviderTemplate(
            name: "z.ai GLM — weekly quota",
            subtitle: "same endpoint — pick the weekly number",
            keyURL: URL(string: "https://z.ai/manage-apikey/apikey-list"),
            group: .plans,
            kind: .guided(.init(url: "https://api.z.ai/api/monitor/usage/quota/limit",
                                headerTemplate: "{key}", suggestedName: "GLM week",
                                valueKind: .number))),
        ProviderTemplate(
            name: "MiniMax token plan",
            subtitle: "coding-plan remaining quota",
            keyURL: URL(string: "https://platform.minimax.io/user-center/basic-information/interface-key"),
            group: .plans,
            kind: .guided(.init(url: "https://api.minimax.io/v1/token_plan/remains",
                                suggestedName: "MiniMax plan", valueKind: .number))),
        ProviderTemplate(
            name: "DeepSeek balance",
            subtitle: "verified preset — just needs your key",
            keyURL: URL(string: "https://platform.deepseek.com/api_keys"),
            group: .balances,
            kind: .full({
                ProviderSpec(
                    id: UUID(), displayName: "DeepSeek", adapter: .generic,
                    url: "https://api.deepseek.com/user/balance",
                    headerName: "Authorization", headerTemplate: "Bearer {key}",
                    valuePath: "balance_infos.0.total_balance",
                    subtractPath: nil, scale: 1,
                    valueKind: .currency, currencyCode: "USD", warnBelow: nil,
                    visibility: .pinned)
            })),
        ProviderTemplate(
            name: "OpenRouter credits",
            subtitle: "true remaining credits (purchased − used)",
            keyURL: URL(string: "https://openrouter.ai/settings/keys"),
            group: .balances,
            kind: .full({
                ProviderSpec(
                    id: UUID(), displayName: "OpenRouter", adapter: .generic,
                    url: "https://openrouter.ai/api/v1/credits",
                    headerName: "Authorization", headerTemplate: "Bearer {key}",
                    valuePath: "data.total_credits",
                    subtractPath: "data.total_usage", scale: 1,
                    valueKind: .currency, currencyCode: "USD", warnBelow: nil,
                    visibility: .pinned)
            })),
        ProviderTemplate(
            name: "MiniMax balance",
            subtitle: "account balance",
            keyURL: URL(string: "https://platform.minimax.io/user-center/basic-information/interface-key"),
            group: .balances,
            kind: .guided(.init(url: "https://api.minimax.io/v1/user/balance",
                                suggestedName: "MiniMax", valueKind: .currency,
                                currencyCode: "USD"))),
        ProviderTemplate(
            name: "OpenAI spend (this month)",
            subtitle: "month-to-date API spend — needs an org ADMIN key",
            keyURL: URL(string: "https://platform.openai.com/settings/organization/admin-keys"),
            group: .balances, kind: .openAISpend),
    ]
}
