import SwiftUI

/// Compact badge row surfacing Piri's own curated-place enrichment
/// (price level, family-friendliness, typical visit duration, rainy-day
/// fit) when the tapped Apple POI matches one of our own `places` rows.
/// Only non-nil/non-"Unknown" fields render — no "Price: Unknown" badge.
struct CuratedInfoRow: View {
    let info: CuratedPlaceInfo

    var body: some View {
        let badges = badges
        if !badges.isEmpty {
            HStack(spacing: 6) {
                ForEach(badges, id: \.text) { badge in
                    Label(badge.text, systemImage: badge.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.gold.opacity(0.15), in: Capsule())
                }
            }
        }
    }

    private var badges: [(text: String, icon: String)] {
        var result: [(text: String, icon: String)] = []
        if let priceLevel = info.priceLevel {
            result.append((priceLevel, "tag.fill"))
        }
        if info.familyFriendly == true {
            result.append((String(localized: "curatedInfo.familyFriendly"), "figure.2.and.child.holdinghands"))
        }
        if let durationMinutes = info.durationMinutes {
            result.append((L("placeDetail.typicalVisit", String(durationMinutes)), "clock.fill"))
        }
        if info.rainyDayFit == true {
            result.append((String(localized: "curatedInfo.rainyDayFit"), "cloud.rain.fill"))
        }
        return result
    }
}
