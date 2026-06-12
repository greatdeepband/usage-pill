import Foundation
import Testing
@testable import UsageCore

@Test func deepSeekPresetExtractsFromVerifiedFixture() throws {
    let spec = ProviderPresets.all.first { $0.name == "DeepSeek balance" }!.make()
    let json = try JSONSerialization.jsonObject(with: Data(ProviderFixtures.deepSeekBalance.utf8))
    let primary = DotPath.resolve(spec.valuePath, in: json)
    #expect(primary == 110.53)
    #expect(spec.subtractPath == nil)
    #expect(spec.scale == 1)
    #expect(spec.adapter == .generic)
    #expect(spec.visibility == .pinned)
}

@Test func everyPresetMakesFreshIds() {
    for preset in ProviderPresets.all {
        #expect(preset.make().id != preset.make().id) // new UUID per add
    }
}
