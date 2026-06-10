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
            return try CredentialsParser.parse(data)
        }
        // Fallback: file-based credential store used on some setups.
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else {
            throw CredentialsError.notFound
        }
        return try CredentialsParser.parse(data)
    }
}
