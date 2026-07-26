import CoreGraphics

/// Single source of truth for the COMPACT pill's geometry, shared by
/// PillView (content paddings) and PillPanel (window size) so the two can
/// never drift apart.
///
/// Shape contract (v1.2): the pill is a RoundedRectangle with a FIXED 18 pt
/// corner radius in BOTH states — compact and expanded share one silhouette
/// and expansion reads as pure vertical growth (no capsule→rect morph).
/// Because the corner radius no longer scales with height, the horizontal
/// padding is a CONSTANT 18 pt for every row/section count: the 18 pt inset
/// clears the 18 pt corner curve at every realistic vPad (see the contract
/// test), and the width is a constant 254 pt so the inner bar column keeps
/// its classic 218 pt length (254 − 2·18 = 250 − 2·16).
///
/// Vertical rhythm is unchanged from the capsule era: vPad still grows
/// 0.10 pt per pt of height beyond the classic 50, so every compact height
/// is byte-identical to v1.1.x.
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

    /// v1.2 unified-silhouette constants: fixed corner radius and a constant
    /// horizontal inset that clears it; width follows so bars stay roomy.
    public static let cornerRadius: CGFloat = 18
    public static let hPad: CGFloat = 18
    /// 263pt: the alert-state value ("100%" semibold) needs a 34pt slot and
    /// the bar must not pay for it (folding reported on 254).
    public static let width: CGFloat = 263

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
        // Height estimate with the CLASSIC vertical padding first, then swap
        // in the grown vPad — identical to the capsule-era formula, so
        // heights never jump for existing configurations.
        let estimated = max(
            minHeight,
            baseHeight + CGFloat(max(rows, 0)) * rowHeight + CGFloat(max(sections, 0)) * headerHeight
        )
        let extraHeight = max(0, estimated - classicHeight)
        let vPad = classicVPad + extraHeight * 0.10
        return Metrics(
            height: estimated + 2 * (vPad - classicVPad),
            width: width,
            hPad: hPad,
            vPad: vPad
        )
    }
}
