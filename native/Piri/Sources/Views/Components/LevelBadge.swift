import SwiftUI

/// The one gold level-number circle, shared everywhere a level shows up
/// (`FriendProfileScreen`, `FriendsScreen`, `LeaderboardScreen`,
/// `ProfileScreen`'s header, `RecapXPCard`'s trip-recap moment) so a visual
/// tweak here never needs to be repeated by hand in five places. Two call
/// sites (`ProfileScreen.levelIndicator`, `RecapXPCard`) used to hand-roll
/// their own circle at a different size instead of actually calling this,
/// despite both carrying doc comments claiming they did.
struct LevelBadge: View {
    let level: Int
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(Theme.gold.opacity(0.15)).frame(width: size, height: size)
            Text("\(level)").font(.system(size: size * 0.41, weight: .bold)).foregroundStyle(Theme.gold)
        }
    }
}
