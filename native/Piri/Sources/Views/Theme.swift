import SwiftUI

/// Piri's brand colors, matching the `NAVY`/`GOLD` constants repeated across
/// `mobile/app/(tabs)/*.tsx` and `mobile/app/place/[id].tsx`.
enum Theme {
    static let navy = Color(red: 0x0F / 255, green: 0x1C / 255, blue: 0x3F / 255)
    static let gold = Color(red: 0xD4 / 255, green: 0xA8 / 255, blue: 0x43 / 255)
    static let openGreen = Color(red: 0x06 / 255, green: 0x76 / 255, blue: 0x47 / 255)
    static let closedRed = Color(red: 0xB4 / 255, green: 0x23 / 255, blue: 0x18 / 255)
}
