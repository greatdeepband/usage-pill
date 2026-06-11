import Foundation
import Testing
@testable import UsageCore

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
