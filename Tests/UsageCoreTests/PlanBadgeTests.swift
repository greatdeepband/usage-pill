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
