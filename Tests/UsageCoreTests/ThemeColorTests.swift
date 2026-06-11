import Testing
@testable import UsageCore

@Test func parsesSixDigitHex() {
    let c = ThemeColor.parse("#C9A283")
    #expect(c == RGBA(r: 0xC9 / 255, g: 0xA2 / 255, b: 0x83 / 255, a: 1))
}

@Test func parsesEightDigitHexAndLowercaseAndNoHash() {
    #expect(abs((ThemeColor.parse("#FFFFFFBF")?.a ?? 0) - 0xBF / 255) < 0.001)
    #expect(ThemeColor.parse("c9a283") == ThemeColor.parse("#C9A283"))
}

@Test func rejectsGarbage() {
    for bad in ["", "#FFF", "#GGGGGG", "#C9A28", "#C9A283FF00", "red"] {
        #expect(ThemeColor.parse(bad) == nil, "should reject \(bad)")
    }
}

@Test func formatRoundTrips() {
    for hex in ["#C9A283FF", "#FFFFFFBF", "#00000000"] {
        let c = ThemeColor.parse(hex)!
        #expect(ThemeColor.format(c) == hex)
    }
    #expect(ThemeColor.format(ThemeColor.parse("#C9A283")!) == "#C9A283FF")
}

@Test func formatToleratesNonFiniteComponents() {
    #expect(ThemeColor.format(RGBA(r: .nan, g: .infinity, b: -.infinity, a: 1)) == "#000000FF")
}
