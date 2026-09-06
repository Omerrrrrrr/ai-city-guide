import CoreGraphics

/// Shared timing/sizing constants between `TripRecapVideoRenderer` (which
/// drives the export frame-by-frame and places the audio chime) and
/// `RecapVideoScene` (which turns a single `t` in `0...1` into a fully
/// deterministic frame) -- one source of truth so the two can't drift out
/// of sync with each other.
enum RecapVideoTimeline {
    static let size = CGSize(width: 1080, height: 1920)
    static let frameRate: Int32 = 30
    static let totalDuration: Double = 8.0

    /// Brand mark fade-in.
    static let introEnd = 0.06
    /// The route line's `trim(from:to:)` progress window.
    static let routeStart = 0.06
    static let routeEnd = 0.60
    /// The completion glow/sparkle pulse at the route's last point.
    static let flourishStart = 0.60
    static let flourishEnd = 0.72
    /// The stats panel sliding up from the bottom.
    static let statsStart = 0.62
    static let statsEnd = 0.84
    /// Closing beat -- hero photo (if any) + brand mark, cross-dissolving
    /// in over what's behind it rather than a hard cut.
    static let outroStart = 0.88

    /// Where the completion chime should sit on the audio track, in real
    /// seconds -- lines up with `flourishStart`.
    static var chimeOffsetSeconds: Double { flourishStart * totalDuration }
}
