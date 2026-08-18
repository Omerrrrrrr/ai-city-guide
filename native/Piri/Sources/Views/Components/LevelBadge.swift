import SwiftUI

/// The gold level-number circle from `ProfileScreen.xpLevelCard`, factored
/// out so `FriendProfileScreen` can show a friend's shared level with the
/// exact same visual instead of a second hand-rolled version of it.
struct LevelBadge: View {
    let level: Int

    var body: some View {
        ZStack {
            Circle().fill(Theme.gold.opacity(0.15)).frame(width: 46, height: 46)
            Text("\(level)").font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.gold)
        }
    }
}
