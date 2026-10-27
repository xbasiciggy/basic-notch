import Foundation

/// Distance-limited movement, independent of refresh rate; never overshoots a destination.
enum BuddyMotion {
    /// PMD rows: down, down-right, right, up-right, up, up-left, left, down-left.
    /// AppKit Y increases upward.
    static func direction(dx: CGFloat, dy: CGFloat) -> Int {
        guard dx != 0 || dy != 0 else { return 0 }
        let angle = atan2(dx, -dy)
        return (Int((angle / (.pi / 4)).rounded()) + 8) % 8
    }

    static func step(from point: CGPoint, to target: CGPoint, speed: Double, elapsed: Double) -> CGPoint {
        let dx = target.x - point.x, dy = target.y - point.y
        let distance = hypot(dx, dy)
        guard distance > 0, speed.isFinite, elapsed.isFinite else { return point }
        let travel = min(distance, max(0, speed) * min(max(0, elapsed), 0.1))
        return CGPoint(x: point.x + dx / distance * travel, y: point.y + dy / distance * travel)
    }
}
