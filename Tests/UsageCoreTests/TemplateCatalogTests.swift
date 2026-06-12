import Foundation
import Testing
@testable import UsageCore

@Test func catalogHasAllEightEntriesGrouped() {
    let plans = TemplateCatalog.all.filter { $0.group == .plans }
    let balances = TemplateCatalog.all.filter { $0.group == .balances }
    #expect(plans.map(\.name) == [
        "Claude plan", "z.ai GLM — 5-hour quota", "z.ai GLM — weekly quota", "MiniMax token plan",
    ])
    #expect(balances.map(\.name) == [
        "DeepSeek balance", "OpenRouter credits", "MiniMax balance", "OpenAI spend (this month)",
    ])
}

@Test func fullTemplatesProduceFreshIdsAndVerifiedShapes() throws {
    // DeepSeek: same assertions the 1.0 preset test had.
    let deepSeek = TemplateCatalog.template(named: "DeepSeek balance")!
    guard case .full(let make) = deepSeek.kind else { Issue.record("kind"); return }
    let a = make(), b = make()
    #expect(a.id != b.id)
    let dsJSON = try JSONSerialization.jsonObject(with: Data(ProviderFixtures.deepSeekBalance.utf8))
    #expect(DotPath.resolve(a.valuePath, in: dsJSON) == 110.53)

    // OpenRouter: full template WITH subtractPath → true remaining credits.
    let or = TemplateCatalog.template(named: "OpenRouter credits")!
    guard case .full(let makeOR) = or.kind else { Issue.record("kind"); return }
    let spec = makeOR()
    #expect(spec.valuePath == "data.total_credits")
    #expect(spec.subtractPath == "data.total_usage")
    let orJSON = try JSONSerialization.jsonObject(with: Data(ProviderFixtures.openRouterCredits.utf8))
    let primary = DotPath.resolve(spec.valuePath, in: orJSON)!
    let sub = DotPath.resolve(spec.subtractPath!, in: orJSON)!
    #expect((primary - sub) == 8.75)
}

@Test func guidedPrefillsAreWellFormed() {
    for t in TemplateCatalog.all {
        guard case .guided(let p) = t.kind else { continue }
        #expect(URL(string: p.url)?.scheme == "https")
        #expect(p.headerTemplate.contains("{key}"))
        #expect(!p.suggestedName.isEmpty)
    }
    // z.ai uses the RAW token (no Bearer).
    guard case .guided(let zai) = TemplateCatalog.template(named: "z.ai GLM — 5-hour quota")!.kind
    else { Issue.record("kind"); return }
    #expect(zai.headerTemplate == "{key}")
    #expect(zai.url == "https://api.z.ai/api/monitor/usage/quota/limit")
}

@Test func everyNonClaudeEntryHasAKeyURL() {
    for t in TemplateCatalog.all {
        if case .claudePlan = t.kind { #expect(t.keyURL == nil); continue }
        #expect(t.keyURL != nil, "missing keyURL for \(t.name)")
        #expect(t.keyURL?.scheme == "https")
    }
}
