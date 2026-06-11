import Foundation
import Testing
@testable import UsageCore

@Test func decodesAccountEmail() throws {
    // Shape verified by live probe 2026-06-11: email at account.email
    let json = #"{"account":{"uuid":"u","email":"a@b.c","full_name":"X","display_name":"X","has_claude_max":true},"organization":{"name":"Y","rate_limit_tier":"default_max_20x"}}"#
    #expect(try Profile.decode(from: Data(json.utf8)).email == "a@b.c")
}

@Test func toleratesAlternateAndMissingShapes() throws {
    #expect(try Profile.decode(from: Data(#"{"account":{"email_address":"a@b.c"}}"#.utf8)).email == "a@b.c")
    #expect(try Profile.decode(from: Data(#"{"email_address":"a@b.c"}"#.utf8)).email == "a@b.c")
    #expect(try Profile.decode(from: Data(#"{"account":{}}"#.utf8)).email == nil)
    #expect(try Profile.decode(from: Data(#"{"account":{"email":""}}"#.utf8)).email == nil)
}

@Test func throwsOnGarbageProfile() {
    #expect(throws: UsageDecodingError.self) {
        _ = try Profile.decode(from: Data("nope".utf8))
    }
}

@Test func buildsProfileRequest() {
    let req = ProfileRequestBuilder.request(token: "tok123")
    #expect(req.url?.absoluteString == "https://api.anthropic.com/api/oauth/profile")
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer tok123")
    #expect(req.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    #expect(req.timeoutInterval == 10)
}
