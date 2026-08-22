import SwiftUI

/// Lifetime completed-trip-count standing against up to 2 friends (see
/// `TripRecapData`'s doc comment for why this is lifetime, not per-trip),
/// plus a leaderboard rank line when available. Both pieces are optional
/// -- this card simply omits whichever part has no data rather than
/// showing a placeholder, matching `FriendsStore`'s best-effort contract.
struct RecapSocialCard: View {
    let data: TripRecapData

    var body: some View {
        ZStack {
            Theme.navy.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("tripRecap.social.heading").font(.system(size: 24, weight: .heavy)).foregroundStyle(.white)
                    Text("tripRecap.social.sub").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }

                if data.friendsComparison.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 14) {
                        ForEach(Array(data.friendsComparison.enumerated()), id: \.offset) { _, friend in
                            compareRow(friendName: friend.name, theirCount: friend.theirTripCount)
                        }
                    }
                }

                if let rank = data.leaderboardRank {
                    rankCard(rank: rank)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 100)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func compareRow(friendName: String, theirCount: Int) -> some View {
        let total = max(data.myLifetimeTripCount, theirCount, 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("tripRecap.social.you").foregroundStyle(Theme.gold)
                Spacer()
                Text(friendName)
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(Theme.gold)
                        .frame(width: geo.size.width * CGFloat(data.myLifetimeTripCount) / CGFloat(total))
                }
            }
            .frame(height: 10)

            HStack {
                Text(L("tripRecap.social.tripCount", data.myLifetimeTripCount))
                Spacer()
                Text(L("tripRecap.social.tripCount", theirCount))
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func rankCard(rank: Int) -> some View {
        HStack(spacing: 14) {
            Text("#\(rank)")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Theme.gold)
            Text("tripRecap.social.rank")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1)))
        .padding(.top, 6)
    }

    private var emptyState: some View {
        Text("tripRecap.social.empty")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
    }
}
