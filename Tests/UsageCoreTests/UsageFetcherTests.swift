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
    #expect(UsageRequestBuilder.mapStatus(403) == .unauthorized)
    #expect(UsageRequestBuilder.mapStatus(429) == .badResponse(429))
    #expect(UsageRequestBuilder.mapStatus(500) == .badResponse(500))
}
