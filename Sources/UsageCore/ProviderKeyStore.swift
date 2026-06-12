import Foundation
import Security

/// App-OWNED keychain items for user-pasted provider keys. This app creates
/// these items, so reads are always silent — no ACL prompts, no interplay
/// with the signing identity. Entirely unrelated to the READ-ONLY Claude
/// Code credential access. Keys are never logged anywhere.
public struct ProviderKeyStore: Sendable {
    public static let defaultService = "pl.bbi.usage-pill.providers"
    private let service: String
    public init(service: String = ProviderKeyStore.defaultService) { self.service = service }

    public enum KeyStoreError: Error { case writeFailed(OSStatus) }

    /// Upserts. Trims whitespace/newlines — a pasted trailing newline would
    /// otherwise make Foundation drop the auth header silently.
    public func save(key: String, for id: UUID) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        deleteKey(for: id)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
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
