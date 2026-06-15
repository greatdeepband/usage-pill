import Foundation
import Testing
@testable import UsageCore

// ---------------------------------------------------------------------------
// CredentialsParser.isUsable — pure expiry check, no keychain or filesystem
// ---------------------------------------------------------------------------

@Test func isUsableWhenNoExpiry() {
    let creds = OAuthCredentials(accessToken: "tok", expiresAt: nil)
    #expect(CredentialsParser.isUsable(creds, now: Date()) == true)
}

@Test func isUsableWhenExpiryIsFuture() {
    let future = Date(timeIntervalSinceNow: 3600)
    let creds = OAuthCredentials(accessToken: "tok", expiresAt: future)
    #expect(CredentialsParser.isUsable(creds, now: Date()) == true)
}

@Test func isUsableWhenExpiryIsPast() {
    let past = Date(timeIntervalSinceNow: -1)
    let creds = OAuthCredentials(accessToken: "tok", expiresAt: past)
    #expect(CredentialsParser.isUsable(creds, now: Date()) == false)
}

// ---------------------------------------------------------------------------
// Existing parser tests
// ---------------------------------------------------------------------------

@Test func parsesClaudeCodeCredentialJSON() throws {
    let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"sk-ant-ort01-x","expiresAt":1781200000000,"scopes":["user:inference"],"subscriptionType":"max"}}"#
    let creds = try CredentialsParser.parse(Data(json.utf8))
    #expect(creds.accessToken == "sk-ant-oat01-abc")
    #expect(creds.expiresAt == Date(timeIntervalSince1970: 1_781_200_000))
}

@Test func missingExpiryIsTolerated() throws {
    let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc"}}"#
    let creds = try CredentialsParser.parse(Data(json.utf8))
    #expect(creds.expiresAt == nil)
}

@Test func rejectsEmptyOrMissingToken() {
    for bad in [
        #"{"claudeAiOauth":{"accessToken":""}}"#,
        #"{"claudeAiOauth":{}}"#,
        #"{"somethingElse":true}"#,
        "garbage",
    ] {
        #expect(throws: CredentialsError.unreadable) {
            _ = try CredentialsParser.parse(Data(bad.utf8))
        }
    }
}

@Test func parsesPlanFields() throws {
    let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","subscriptionType":"max","rateLimitTier":"default_max_20x"}}"#
    let creds = try CredentialsParser.parse(Data(json.utf8))
    #expect(creds.subscriptionType == "max")
    #expect(creds.rateLimitTier == "default_max_20x")
}

@Test func planFieldsAreOptional() throws {
    let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc"}}"#
    let creds = try CredentialsParser.parse(Data(json.utf8))
    #expect(creds.subscriptionType == nil)
    #expect(creds.rateLimitTier == nil)
}

// ---------------------------------------------------------------------------
// KeychainCredentialsProvider.load() fallback matrix — fake reader + injected
// fileData, fully deterministic (never touches the real ~/.claude store).
// ---------------------------------------------------------------------------

private struct FakeReader: KeychainItemReading {
    let result: Result<Data, Error>
    func read(service: String) throws -> Data { try result.get() }
}
private let kcBlob   = Data(#"{"claudeAiOauth":{"accessToken":"sk-kc","expiresAt":99999999999999}}"#.utf8)
private let fileBlob = Data(#"{"claudeAiOauth":{"accessToken":"sk-file","expiresAt":99999999999999}}"#.utf8)
private let expired  = Data(#"{"claudeAiOauth":{"accessToken":"sk-old","expiresAt":1}}"#.utf8)

@Test func readerBytesParsedDirectly() throws {
    let p = KeychainCredentialsProvider(reader: FakeReader(result: .success(kcBlob)), fileData: { nil })
    #expect(try p.load().accessToken == "sk-kc")
}
@Test func unparseableReaderFallsToFileThenUnreadable() throws {
    let bad = Data("not json".utf8)
    #expect(throws: CredentialsError.unreadable) {
        try KeychainCredentialsProvider(reader: FakeReader(result: .success(bad)), fileData: { nil }).load()
    }
    let withFile = KeychainCredentialsProvider(reader: FakeReader(result: .success(bad)), fileData: { fileBlob })
    #expect(try withFile.load().accessToken == "sk-file")
}
@Test func emptyButPresentMapsToUnreadable() {   // old SecItemCopyMatching behavior
    #expect(throws: CredentialsError.unreadable) {
        try KeychainCredentialsProvider(reader: FakeReader(result: .success(Data())), fileData: { nil }).load()
    }
}
@Test func readerFailureFallsToFileThenNotFound() throws {
    #expect(throws: CredentialsError.notFound) {
        try KeychainCredentialsProvider(reader: FakeReader(result: .failure(KeychainReadError.notFound)), fileData: { nil }).load()
    }
    let withFile = KeychainCredentialsProvider(reader: FakeReader(result: .failure(KeychainReadError.toolFailed(1))), fileData: { fileBlob })
    #expect(try withFile.load().accessToken == "sk-file")
}
@Test func expiredFileTreatedAsNotFound() {
    #expect(throws: CredentialsError.notFound) {
        try KeychainCredentialsProvider(reader: FakeReader(result: .failure(KeychainReadError.notFound)), fileData: { expired }).load()
    }
}
