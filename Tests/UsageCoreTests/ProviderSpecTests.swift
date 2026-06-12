import Testing
import Foundation
@testable import UsageCore


private func sampleSpec() -> ProviderSpec {
    ProviderSpec(
        id: UUID(),
        displayName: "DeepSeek",
        adapter: .generic,
        url: "https://api.deepseek.com/user/balance",
        headerName: "Authorization",
        headerTemplate: "Bearer {key}",
        valuePath: "balance_infos.0.total_balance",
        subtractPath: nil,
        scale: 1.0,
        valueKind: .currency,
        currencyCode: "USD",
        warnBelow: 5.0,
        visibility: .pinned
    )
}

@Test func roundTripsThroughStore() {
    TestDefaults.withFresh(prefix: "provider-spec-tests-") { d in
        let spec = sampleSpec()
        let store = ProviderSpecStore(defaults: d)
        store.save([spec])
        let loaded = ProviderSpecStore(defaults: d).load()
        #expect(loaded.count == 1)
        #expect(loaded.first == spec)
    }
}

@Test func corruptEntryIsDroppedOthersSurvive() {
    TestDefaults.withFresh(prefix: "provider-spec-tests-") { d in
        // Build a good spec as a plain dictionary
        let goodSpec = sampleSpec()
        let goodDict: [String: Any] = [
            "id": goodSpec.id.uuidString,
            "displayName": "Good",
            "adapter": "generic",
            "url": goodSpec.url,
            "headerName": goodSpec.headerName,
            "headerTemplate": goodSpec.headerTemplate,
            "valuePath": goodSpec.valuePath,
            "scale": goodSpec.scale,
            "valueKind": "currency",
            "currencyCode": "USD",
            "warnBelow": 5.0,
            "visibility": "pinned"
        ]
        // A corrupt entry: id is not a UUID string, displayName is a number
        let corruptDict: [String: Any] = [
            "id": "not-a-uuid",
            "displayName": 42
        ]
        let rawArray: [Any] = [goodDict, corruptDict]
        let blob = try! JSONSerialization.data(withJSONObject: rawArray)
        d.set(blob, forKey: ProviderSpecStore.key)

        let loaded = ProviderSpecStore(defaults: d).load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.displayName == "Good")
    }
}

@Test func missingOrGarbageBlobYieldsEmpty() {
    TestDefaults.withFresh(prefix: "provider-spec-tests-") { d in
        // No key → empty
        #expect(ProviderSpecStore(defaults: d).load().isEmpty)
    }
    TestDefaults.withFresh(prefix: "provider-spec-tests-") { d in
        // Garbage data → empty
        d.set(Data("garbage".utf8), forKey: ProviderSpecStore.key)
        #expect(ProviderSpecStore(defaults: d).load().isEmpty)
    }
    TestDefaults.withFresh(prefix: "provider-spec-tests-") { d in
        // Object (not an array) blob → empty
        d.set(Data(#"{"key":"value"}"#.utf8), forKey: ProviderSpecStore.key)
        #expect(ProviderSpecStore(defaults: d).load().isEmpty)
    }
}
