import CoreGraphics

/// Whole-sprite bounds, including asymmetric activity reservations and animation reach.
enum PokemonBounds {
    static func range(halfWidth: CGFloat, leading: CGFloat, trailing: CGFloat, radius: CGFloat) -> ClosedRange<CGFloat> {
        let left = -halfWidth + max(0, leading) + max(0, radius)
        let right = halfWidth - max(0, trailing) - max(0, radius)
        if left > right {
            let center = (max(0, leading) - max(0, trailing)) / 2
            return center...center
        }
        return left...right
    }
    static func clamp(_ x: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat { min(range.upperBound, max(range.lowerBound, x)) }
}
