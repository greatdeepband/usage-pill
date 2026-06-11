import Foundation
import CoreFoundation
import Security

public struct OAuthCredentials: Equatable, Sendable {
    public let accessToken: String
    public let expiresAt: Date?
}

public enum CredentialsError: Error, Equatable {
    case notFound   // no keychain item and no fallback file
    case unreadable // present but not in the expected shape
}

public enum CredentialsParser {
    public static func parse(_ data: Data) throws -> OAuthCredentials {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let root = any as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            throw CredentialsError.unreadable
        }
        // expiresAt is kept for diagnostics only; expiry is enforced by the
        // server (401 → stale state), never checked locally.
        let expiresAt: Date?
        if let number = oauth["expiresAt"] as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID() {
            expiresAt = Date(timeIntervalSince1970: number.doubleValue / 1000)
        } else {
            expiresAt = nil
        }
        return OAuthCredentials(accessToken: token, expiresAt: expiresAt)
    }
}

/// Read-only access to Claude Code's stored login. NEVER writes or refreshes:
/// Claude Code rotates refresh tokens; a second refresher would corrupt its login.
public struct KeychainCredentialsProvider: Sendable {
    public init() {}

    public func load() throws -> OAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            do {
                return try CredentialsParser.parse(data)
            } catch {
                // Keychain item is present but unreadable (corrupt or wrong shape).
                // Fall through to the file store; if that is also absent, rethrow
                // the original .unreadable error — not .notFound — so the caller
                // knows something was found but could not be parsed.
                if let fileData = fileCredentialsData() {
                    return try CredentialsParser.parse(fileData)
                }
                throw error
            }
        }
        // Any non-success status (not-found, but also user-canceled or ACL-denied)
        // falls through to the file store; if that is absent too, the caller sees
        // .notFound and the UI shows the sign-in hint.
        guard let data = fileCredentialsData() else {
            throw CredentialsError.notFound
        }
        return try CredentialsParser.parse(data)
    }

    /// Contents of the file-based credential store used on some setups, if present.
    private func fileCredentialsData() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(components: ".claude", ".credentials.json")
        return try? Data(contentsOf: url)
    }
}
