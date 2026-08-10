import SwiftUI

/// Piri's brand colors, matching the `NAVY`/`GOLD` constants repeated across
/// `mobile/app/(tabs)/*.tsx` and `mobile/app/place/[id].tsx`.
enum Theme {
    static let navy = Color(red: 0x0F / 255, green: 0x1C / 255, blue: 0x3F / 255)
    static let gold = Color(red: 0xD4 / 255, green: 0xA8 / 255, blue: 0x43 / 255)
    static let openGreen = Color(red: 0x06 / 255, green: 0x76 / 255, blue: 0x47 / 255)
    static let closedRed = Color(red: 0xB4 / 255, green: 0x23 / 255, blue: 0x18 / 255)
}

extension View {
    /// Every screen's navy header bar, upgraded to a real Liquid Glass
    /// surface — `glassEffect` only exists from iOS 26 (this app's
    /// deployment target is 18), so this is the fallback-guarded way every
    /// call site gets it instead of repeating the `#available` check.
    /// Visually this is the single biggest lever identified in the
    /// Ağustos 2026 visual-identity report: a flat, opaque `Theme.navy`
    /// fill was the one thing every screen had in common that didn't
    /// react to light, motion, or content at all — exactly what Liquid
    /// Glass is for. Falls back to the original flat fill pre-iOS 26 so
    /// older devices look exactly as they did before this change.
    @ViewBuilder
    func piriGlassSurface(tint: Color = Theme.navy, in shape: some Shape = Rectangle()) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            self.background(tint)
        }
    }

    /// Floating overlay cards (Map's search bar, POI cards, route sheet) —
    /// these already sat on `.regularMaterial` (a translucent blur), so
    /// this is a strict visual upgrade to the real thing on iOS 26 with the
    /// exact same pre-26 fallback they already had, not a new material
    /// swapped in cold.
    @ViewBuilder
    func piriGlassCard(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
