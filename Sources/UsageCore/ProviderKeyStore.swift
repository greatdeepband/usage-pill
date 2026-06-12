import Foundation
import Security

/// App-OWNED keychain items for user-pasted provider keys. This app creates
/// these items, so reads are always silent — no ACL prompts, no interplay
/// with the signing identity — for items created by the SAME signing identity.
/// Dev-workflow caveat: an unsigned (debug) binary and the signed .app use
/// different identities and do NOT share items silently; this is expected and
/// only affects local development, not production users.
/// Entirely unrelated to the READ-ONLY Claude Code credential access.
/// Keys are never logged anywhere.
public struct ProviderKeyStore: Sendable {
    public static let defaultService = "pl.bbi.usage-pill.providers"
    private let service: String
    public init(service: String = ProviderKeyStore.defaultService) { self.service = service }

    public enum KeyStoreError: Error { case writeFailed(OSStatus) }

    /// Upserts atomically. Tries SecItemUpdate first so that a failure never
    /// destroys the existing key; only inserts if the item is not yet present.
    /// Trims whitespace/newlines — a pasted trailing newline would otherwise
    /// make Foundation drop the auth header silently.
    public func save(key: String, for id: UUID) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        let update: [String: Any] = [kSecValueData as String: Data(trimmed.utf8)]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attrs = query
            attrs[kSecValueData as String] = Data(trimmed.utf8)
            attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(attrs as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeyStoreError.writeFailed(status) }
    }

    public func loadKey(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func deleteKey(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// "••••1234" — never expose more than the last 4 characters.
    public static func masked(_ key: String) -> String {
        key.count > 4 ? "••••" + key.suffix(4) : "••••"
    }
}
