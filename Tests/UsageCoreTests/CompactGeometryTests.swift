import CoreGraphics
import Foundation
import Testing
@testable import UsageCore

/// Rounded-rect corner inset at vertical offset `y` from the top edge, for
/// corner radius `r`: the corner circle is centered at (r, r), so at
/// vertical distance d = r − y from the center the edge sits at
/// x = r − sqrt(r² − d²). Below the corner circle (y ≥ r) the edge is flat.
private func cornerInset(atY y: CGFloat, radius r: CGFloat) -> CGFloat {
    guard y < r else { return 0 }
    let d = r - y
    return r - sqrt(max(0, r * r - d * d))
}

/// THE geometry contract: for every realistic compact configuration the
/// content's top-left corner (hPad, vPad) must clear the 18 pt rounded-rect
/// corner curve by at least 2 pt of grace. (All four corners are symmetric.)
@Test(arguments: 2...8, 0...4)
func compactContentClearsRoundedCorner(rows: Int, sections: Int) {
    let m = CompactGeometry.metrics(rows: rows, sections: sections)
    let inset = cornerInset(atY: m.vPad, radius: CompactGeometry.cornerRadius)
    #expect(
        m.hPad >= inset + 2,
        "rows=\(rows) sections=\(sections): hPad \(m.hPad) must clear corner inset \(inset) by ≥ 2pt"
    )
}

/// The unified-silhouette compact pill: constant 18 pt inset and constant
/// 263 pt width for every configuration (no more capsule-driven growth).
@Test(arguments: 0...8, 0...4)
func paddingAndWidthAreConstant(rows: Int, sections: Int) {
    let m = CompactGeometry.metrics(rows: rows, sections: sections)
    #expect(m.hPad == 18)
    #expect(m.width == 263)
}

/// The bar never pays for the value: compact rows are icon 12pt + 6pt
/// spacing + flexible bar + 6pt spacing + content-sized value (≤ ~30pt for
/// a semibold "100%"), so the worst-case bar stays above the classic 158pt.
@Test(arguments: 2...8, 0...4)
func barNeverShrinksBelowClassic(rows: Int, sections: Int) {
    let m = CompactGeometry.metrics(rows: rows, sections: sections)
    let barFlex = m.width - 2 * m.hPad - 12 - 6 - 6 - 30
    #expect(barFlex >= 158, "rows=\(rows) sections=\(sections): bar \(barFlex)pt < classic 158pt")
}

/// Heights are byte-identical to the capsule era: the vPad growth formula is
/// unchanged, so no existing configuration jumps when the app updates.
@Test func heightsMatchCapsuleEra() {
    // (rows, sections, capsule-era height)
    let cases: [(Int, Int, CGFloat)] = [
        (2, 1, 68),    // default: two Claude rows + CLAUDE header
        (2, 0, 50),    // classic v1 two-row headerless
        (0, 0, 30),    // empty floor
        (3, 2, 108.8),
        (5, 4, 190.4),
    ]
    for (rows, sections, expected) in cases {
        let m = CompactGeometry.metrics(rows: rows, sections: sections)
        #expect(
            abs(m.height - expected) < 0.05,
            "rows=\(rows) sections=\(sections): height \(m.height) != capsule-era \(expected)"
        )
    }
}

@Test func negativeCountsClampToZero() {
    #expect(CompactGeometry.metrics(rows: -3, sections: -1) == CompactGeometry.metrics(rows: 0, sections: 0))
}

/// Monotonicity: adding a row never reduces any metric (no sudden jumps
/// backwards that would make the pill twitch when a row is added).
@Test func metricsAreMonotonic() {
    for sections in 0...4 {
        for rows in 2...7 {
            let a = CompactGeometry.metrics(rows: rows, sections: sections)
            let b = CompactGeometry.metrics(rows: rows + 1, sections: sections)
            #expect(b.height > a.height)
            #expect(b.hPad >= a.hPad)
            #expect(b.vPad >= a.vPad)
            #expect(b.width >= a.width)
        }
    }
}
