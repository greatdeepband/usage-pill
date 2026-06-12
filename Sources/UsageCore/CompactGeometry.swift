import CoreGraphics

/// Single source of truth for the COMPACT pill's geometry, shared by
/// PillView (content paddings) and PillPanel (window size) so the two can
/// never drift apart.
///
/// Why paddings scale with height: the compact pill is a Capsule, so its
/// side radius is height/2. The classic v1 pill was 250×50 (radius 25) and
/// fixed paddings of 16/8 cleared the corner curvature fine. With section
/// headers + provider rows the compact height grows toward ~100+, the side
/// radius grows with it, and fixed paddings would leave the content's
/// corners INSIDE the curve (visually clipped/crowded). So both paddings
/// grow linearly with the height beyond the classic 50, and the window
/// width grows by the extra horizontal padding on both sides so the bars
/// keep their classic length.
///
/// Corner-clearance contract (unit-tested in CompactGeometryTests): at the
/// content's top-left corner (hPad, vPad), the capsule edge's horizontal
/// inset is r − sqrt(r² − (r − vPad)²) with r = height/2; hPad must exceed
/// that inset by ≥ 2 pt for every realistic row/section count. The 0.35 and
/// 0.10 factors are implementation — the test is the contract.
public enum CompactGeometry {
    public struct Metrics: Equatable, Sendable {
        public let height: CGFloat
        public let width: CGFloat
        public let hPad: CGFloat
        public let vPad: CGFloat
    }

    /// Classic v1 compact pill: 250×50 with 16/8 paddings (side radius 25).
    public static let classicWidth: CGFloat = 250
    public static let classicHeight: CGFloat = 50
    public static let classicHPad: CGFloat = 16
    public static let classicVPad: CGFloat = 8

    // Content constants MEASURED via NSHostingView.fittingSize against the
    // real compact layout (see the comment block in PillPanel): each compact
    // row costs 19 pt and each section header 15 pt over a 12 pt base, where
    // the base includes the classic 2×8 vertical padding.
    static let rowHeight: CGFloat = 19
    static let headerHeight: CGFloat = 15
    static let baseHeight: CGFloat = 12
    static let minHeight: CGFloat = 30

    /// `rows` = compact-visible (pinned) Claude + provider rows;
    /// `sections` = section headers visible in compact mode.
    public static func metrics(rows: Int, sections: Int) -> Metrics {
        // Estimate with the CLASSIC paddings first (this is the pre-v2 height
        // formula), then derive the padding growth from that estimate — the
        // real height just swaps the classic vertical padding for the grown one.
        let estimated = max(
            minHeight,
            baseHeight + CGFloat(max(rows, 0)) * rowHeight + CGFloat(max(sections, 0)) * headerHeight
        )
        let extraHeight = max(0, estimated - classicHeight)
        let hPad = classicHPad + extraHeight * 0.35
        let vPad = classicVPad + extraHeight * 0.10
        return Metrics(
            height: estimated + 2 * (vPad - classicVPad),
            width: classicWidth + 2 * (hPad - classicHPad),
            hPad: hPad,
            vPad: vPad
        )
    }
}
