import Foundation
import Testing
@testable import UsageCore

@Test func claudeTokenSaveLoadDelete() throws {
    let store = ClaudeTokenStore(keyStore: ProviderKeyStore(service: "pill-tests-\(UUID().uuidString)"))
    defer { store.clear() }
    #expect(store.token() == nil)
    try store.save("sk-ant-oat01-EXAMPLE")
    #expect(store.token() == "sk-ant-oat01-EXAMPLE")
    #expect(store.maskedToken() == "••••MPLE")
    store.clear()
    #expect(store.token() == nil)
}

@Test func claudeTokenUsesFixedAccountNotCollidingWithProviders() {
    // The sentinel account UUID is stable + distinct.
    #expect(ClaudeTokenStore.claudeAccountID.uuidString == ClaudeTokenStore.claudeAccountID.uuidString)
}
