import CoreGraphics
import Foundation
import Testing
@testable import UsageCore

/// Capsule edge inset at vertical offset `y` from the top edge, for side
/// radius `r` = height/2: the corner circle is centered at (r, r), so at
/// vertical distance d = r − y from the center the edge sits at
/// x = r − sqrt(r² − d²). Below the corner circle (y ≥ r) the edge is flat.
private func capsuleInset(atY y: CGFloat, radius r: CGFloat) -> CGFloat {
    guard y < r else { return 0 }
    let d = r - y
    return r - sqrt(max(0, r * r - d * d))
}

/// THE geometry contract: for every realistic compact configuration the
/// content's top-left corner (hPad, vPad) must clear the capsule's corner
/// curve by at least 2 pt of grace — i.e. the formula can never regress
/// into corner clipping. (All four corners are symmetric.)
@Test(arguments: 2...8, 0...4)
func compactContentClearsCapsuleCorner(rows: Int, sections: Int) {
    let m = CompactGeometry.metrics(rows: rows, sections: sections)
    let inset = capsuleInset(atY: m.vPad, radius: m.height / 2)
    #expect(
        m.hPad >= inset + 2,
        "rows=\(rows) sections=\(sections): hPad \(m.hPad) must clear capsule inset \(inset) by ≥ 2pt"
    )
}

@Test func classicTwoRowHeaderlessPillIsExactlyV1() {
    let m = CompactGeometry.metrics(rows: 2, sections: 0)
    #expect(m.height == 50)
    #expect(m.width == 250)
    #expect(m.hPad == 16)
    #expect(m.vPad == 8)
}

/// Window width grows by exactly the extra padding on both sides, so the
/// inner content column (bars) keeps its classic 218 pt length.
@Test(arguments: 2...8, 0...4)
func widthGrowsWithPaddingSoBarsNeverShrink(rows: Int, sections: Int) {
    let m = CompactGeometry.metrics(rows: rows, sections: sections)
    #expect(m.width == 250 + 2 * (m.hPad - 16))
    #expect(abs((m.width - 2 * m.hPad) - (250 - 2 * 16)) < 0.0001)
}

/// Paddings and width never go below the classic values, and the height
/// floor for a content-less pill ("…" / "open Settings") is preserved.
@Test func emptyPillKeepsClassicFloor() {
    let m = CompactGeometry.metrics(rows: 0, sections: 0)
    #expect(m.height == 30)
    #expect(m.width == 250)
    #expect(m.hPad == 16)
    #expect(m.vPad == 8)
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
