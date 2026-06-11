import Foundation
import CoreFoundation
import Security

public struct OAuthCredentials: Equatable, Sendable {
    public let accessToken: String
    public let expiresAt: Date?
    public let subscriptionType: String?
    public let rateLimitTier: String?

    public init(
        accessToken: String,
        expiresAt: Date?,
        subscriptionType: String? = nil,
        rateLimitTier: String? = nil
    ) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }
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
        // expiresAt is kept for diagnostics and the file-store expiry check
        // (isUsable). Keychain tokens are passed through without expiry checking —
        // Claude Code keeps them fresh; local metadata may be stale. Only file-store
        // tokens have their expiry checked (expired file token → .notFound so the UI
        // shows the sign-in hint rather than spinning on guaranteed-401 requests).
        let expiresAt: Date?
        if let number = oauth["expiresAt"] as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID() {
            expiresAt = Date(timeIntervalSince1970: number.doubleValue / 1000)
        } else {
            expiresAt = nil
        }
        return OAuthCredentials(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
    }

    /// Returns false iff `expiresAt` is set AND is in the past. Used to skip
    /// stale file-store tokens that can only produce 401 loops.
    public static func isUsable(_ creds: OAuthCredentials, now: Date) -> Bool {
        guard let exp = creds.expiresAt else { return true }
        return exp > now
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
                // Keychain-sourced tokens are returned without expiry checking —
                // Claude Code keeps them fresh; local metadata may be stale.
                return try CredentialsParser.parse(data)
            } catch {
                // Keychain item is present but unreadable (corrupt or wrong shape).
                // Fall through to the file store; if that is also absent, rethrow
                // the original .unreadable error — not .notFound — so the caller
                // knows something was found but could not be parsed.
                if let creds = try fileCredentials() {
                    return creds
                }
                throw error
            }
        }
        // Any non-success status (not-found, but also user-canceled or ACL-denied)
        // falls through to the file store; if that is absent too, the caller sees
        // .notFound and the UI shows the sign-in hint.
        guard let creds = try fileCredentials() else {
            throw CredentialsError.notFound
        }
        return creds
    }

    /// Parses the file-based credential store and checks that the token has not
    /// expired. Returns nil when the file is absent; throws when present but
    /// unreadable or expired (expired → .notFound so the UI shows the sign-in
    /// hint rather than spinning on guaranteed-401 requests).
    private func fileCredentials() throws -> OAuthCredentials? {
        guard let data = fileCredentialsData() else { return nil }
        let creds = try CredentialsParser.parse(data)
        guard CredentialsParser.isUsable(creds, now: Date()) else {
            throw CredentialsError.notFound
        }
        return creds
    }

    /// Contents of the file-based credential store used on some setups, if present.
    private func fileCredentialsData() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(components: ".claude", ".credentials.json")
        return try? Data(contentsOf: url)
    }
}
