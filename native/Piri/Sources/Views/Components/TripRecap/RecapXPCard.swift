import SwiftUI

/// XP earned this trip, with a level-up moment when it crosses a
/// threshold. Reuses `LevelBadge`'s exact gold-circle visual (same
/// component `ProfileScreen`'s own XP card uses) so this doesn't invent a
/// second version of that badge.
struct RecapXPCard: View {
    let data: TripRecapData

    var body: some View {
        ZStack {
            Theme.navy.ignoresSafeArea()

            VStack(spacing: 28) {
                HStack(spacing: 4) {
                    Text("+")
                    CountUpNumber(value: Double(data.xpDelta))
                    Text("tripRecap.xp.suffix")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(red: 0.5, green: 0.85, blue: 0.6))

                ZStack {
                    Circle().fill(Theme.gold.opacity(0.14)).frame(width: 148, height: 148)
                    Circle().strokeBorder(Theme.gold.opacity(0.4), style: StrokeStyle(lineWidth: 1.4, dash: [1, 5])).frame(width: 156, height: 156)
                    Text("\(data.levelAfter)")
                        .font(.system(size: 54, weight: .heavy))
                        .foregroundStyle(Theme.gold)
                }

                Text(data.leveledUp ? L("tripRecap.xp.leveledUp", data.levelAfter) : L("tripRecap.xp.progress", data.levelAfter))
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(.white)

                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule().fill(Theme.gold)
                                .frame(width: geo.size.width * Gamification.progressIntoCurrentLevel(data.xpAfter))
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Text(L("tripRecap.xp.level", data.levelAfter))
                        Spacer()
                        Text(L("tripRecap.xp.level", data.levelAfter + 1))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: 260)
            }
            .padding(.horizontal, 32)
        }
    }
}
