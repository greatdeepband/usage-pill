import Foundation
import Testing
@testable import UsageCore

@Test func buildsAuthorizedRequest() {
    let req = UsageRequestBuilder.request(token: "tok123")
    #expect(req.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
    #expect(req.httpMethod == "GET")
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer tok123")
    #expect(req.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(req.timeoutInterval == 10)
}

@Test func mapsStatusCodes() {
    #expect(UsageRequestBuilder.mapStatus(200) == nil)
    #expect(UsageRequestBuilder.mapStatus(204) == nil)
    #expect(UsageRequestBuilder.mapStatus(401) == .unauthorized)
    #expect(UsageRequestBuilder.mapStatus(403) == .badResponse(403))
    #expect(UsageRequestBuilder.mapStatus(429) == .rateLimited(retryAfter: nil))
    #expect(UsageRequestBuilder.mapStatus(500) == .badResponse(500))
}

@Test func retryAfterSecondsFromValidInt() {
    #expect(UsageRequestBuilder.retryAfterSeconds(from: "120") == 120)
    #expect(UsageRequestBuilder.retryAfterSeconds(from: "60") == 60)
    #expect(UsageRequestBuilder.retryAfterSeconds(from: "1") == 1)
}

@Test func retryAfterSecondsRejectsInvalid() {
    #expect(UsageRequestBuilder.retryAfterSeconds(from: "0") == nil)
    #expect(UsageRequestBuilder.retryAfterSeconds(from: "-5") == nil)
    #expect(UsageRequestBuilder.retryAfterSeconds(from: "Wed, 21 Oct 2015 07:28:00 GMT") == nil)
    #expect(UsageRequestBuilder.retryAfterSeconds(from: nil) == nil)
    #expect(UsageRequestBuilder.retryAfterSeconds(from: "abc") == nil)
}
