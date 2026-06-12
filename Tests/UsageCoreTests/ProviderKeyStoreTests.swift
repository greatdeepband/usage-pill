import Foundation
import Testing
@testable import UsageCore

@Test func savesLoadsUpdatesAndDeletes() throws {
    let store = ProviderKeyStore(service: "pill-tests-\(UUID().uuidString)")
    let id = UUID()
    defer { store.deleteKey(for: id) }
    #expect(store.loadKey(for: id) == nil)
    try store.save(key: "sk-test-1", for: id)
    #expect(store.loadKey(for: id) == "sk-test-1")
    try store.save(key: "sk-test-2", for: id)          // upsert
    #expect(store.loadKey(for: id) == "sk-test-2")
    store.deleteKey(for: id)
    #expect(store.loadKey(for: id) == nil)
}

@Test func keysAreTrimmedOnSave() throws {
    // A pasted trailing-newline key would silently break the auth header
    // (Foundation drops CRLF-containing header values) — trim at the edge.
    let store = ProviderKeyStore(service: "pill-tests-\(UUID().uuidString)")
    let id = UUID()
    defer { store.deleteKey(for: id) }
    try store.save(key: "  sk-test-3\n", for: id)
    #expect(store.loadKey(for: id) == "sk-test-3")
}

@Test func last4MasksCorrectly() {
    #expect(ProviderKeyStore.masked("sk-abcd1234") == "••••1234")
    #expect(ProviderKeyStore.masked("abc") == "••••")
    #expect(ProviderKeyStore.masked("") == "••••")
}
