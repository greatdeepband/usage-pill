enum ProviderFixtures {
    /// Structure VERIFIED against the live DeepSeek endpoint on 2026-06-12
    /// (HTTP 200, GET api.deepseek.com/user/balance, Bearer auth).
    /// Amounts are sanitized placeholders — the structure is verbatim,
    /// including the string-typed numbers and the boolean field.
    static let deepSeekBalance = #"""
    {"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"110.53","granted_balance":"0.00","topped_up_balance":"110.53"}]}
    """#

    /// Shape per OpenRouter docs (total credits purchased / total used).
    static let openRouterCredits = #"""
    {"data":{"total_credits":50.0,"total_usage":41.25}}
    """#

    // Probe outcomes 2026-06-12 (plan Task 1):
    //   DeepSeek        — SHIP (verified above)
    //   OpenRouter      — DEFER (no key offered; README recipe + custom flow)
    //   MiniMax         — DEFER (no key offered)
    //   OpenAI spend    — DEFER (no admin key offered; native adapter skipped)
    //   Anthropic spend — DEFER (no admin key offered; native adapter skipped)
}
