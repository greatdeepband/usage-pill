import Testing
@testable import UsageCore

@Test func derivesBadgeText() {
    #expect(PlanBadge.text(subscriptionType: "max", rateLimitTier: "default_max_20x") == "MAX 20×")
    #expect(PlanBadge.text(subscriptionType: "max", rateLimitTier: "default_max_5x") == "MAX 5×")
    #expect(PlanBadge.text(subscriptionType: "max", rateLimitTier: nil) == "MAX")
    #expect(PlanBadge.text(subscriptionType: "pro", rateLimitTier: "default") == "PRO")
    #expect(PlanBadge.text(subscriptionType: nil, rateLimitTier: "default_max_20x") == nil)
    #expect(PlanBadge.text(subscriptionType: "  ", rateLimitTier: nil) == nil)
    #expect(PlanBadge.text(subscriptionType: "max", rateLimitTier: "default_max_xx") == "MAX")
}

@Test func serverPlanNameWinsOverTheCredentialTier() {
    // Live 2026-10-30: the Max 20x → Ultra rename reached only the profile;
    // the subscription and tier still read "max" + "default_claude_max_20x".
    #expect(PlanBadge.text(subscriptionType: "max", rateLimitTier: "default_claude_max_20x",
                           planName: "Ultra") == "ULTRA")
    #expect(PlanBadge.text(subscriptionType: "max", rateLimitTier: "default_claude_max_5x",
                           planName: "Max") == "MAX")
    #expect(PlanBadge.text(subscriptionType: nil, rateLimitTier: nil, planName: "Pro") == "PRO")
}

@Test func blankPlanNameFallsBackToTheTier() {
    #expect(PlanBadge.text(subscriptionType: "max", rateLimitTier: "default_max_20x",
                           planName: nil) == "MAX 20×")
    #expect(PlanBadge.text(subscriptionType: "max", rateLimitTier: "default_max_20x",
                           planName: "  ") == "MAX 20×")
}
