import CoreGraphics

/// Clamp a window's TOP-LEFT point so the pill stays fully on the nearest screen.
/// Coordinates are AppKit-style (y grows upward).
public func clampTopLeft(_ point: CGPoint, pillSize: CGSize, screens: [CGRect]) -> CGPoint {
    guard !screens.isEmpty else { return point }
    let target = screens.min(by: { distance(point, to: $0) < distance(point, to: $1) })!
    let x = min(max(point.x, target.minX), target.maxX - pillSize.width)
    let y = min(max(point.y, target.minY + pillSize.height), target.maxY)
    return CGPoint(x: x, y: y)
}

private func distance(_ p: CGPoint, to rect: CGRect) -> CGFloat {
    let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
    let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
    return dx * dx + dy * dy
}
