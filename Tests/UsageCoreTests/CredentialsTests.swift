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
