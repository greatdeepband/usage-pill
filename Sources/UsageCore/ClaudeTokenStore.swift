import Foundation

/// The user's long-lived Claude token (from `claude setup-token`), stored in
/// OUR app-owned keychain item — silent reads, immune to Claude Code's token
/// rotations (which reset Claude Code's own item's ACL and cause the prompts).
/// A thin wrapper over ProviderKeyStore keyed by a fixed sentinel account.
public struct ClaudeTokenStore: Sendable {
    /// Stable, compile-time account id for the Claude token item. Distinct from
    /// any provider spec id (those are random per-add).
    public static let claudeAccountID = UUID(uuidString: "C1A0DE00-0000-4000-A000-000000000001")!
    private let keyStore: ProviderKeyStore
    public init(keyStore: ProviderKeyStore = ProviderKeyStore()) { self.keyStore = keyStore }

    public func token() -> String? { keyStore.loadKey(for: Self.claudeAccountID) }
    public func save(_ token: String) throws { try keyStore.save(key: token, for: Self.claudeAccountID) }
    public func clear() { keyStore.deleteKey(for: Self.claudeAccountID) }
    public func maskedToken() -> String? { token().map(ProviderKeyStore.masked) }
}
