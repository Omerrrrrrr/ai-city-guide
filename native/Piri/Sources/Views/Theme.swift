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

    /// Replaces the plain `.overlay(RoundedRectangle().stroke(...))` outline
    /// most of Profile/Gamification/Paywall's info cards used -- a flat
    /// stroke with no fill or shadow reads as a wireframe, not a real card.
    /// Gives every one of them the same subtle elevation (soft shadow +
    /// faint tinted fill) in one place instead of restyling each by hand.
    func piriElevatedCard(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color(.secondarySystemGroupedBackground)))
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

extension LinearGradient {
    /// The gold-to-navy diagonal used behind Profile's header band and
    /// Gamification's hero -- the one premium touch every mockup screen had
    /// in some form (a colored glow behind the "important" content) that
    /// this app's screens, all flat `Theme.navy`, never actually reused
    /// anywhere themselves.
    static let piriHero = LinearGradient(
        colors: [Theme.gold.opacity(0.55), Theme.navy],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
