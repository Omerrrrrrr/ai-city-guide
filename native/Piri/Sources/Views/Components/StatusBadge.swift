import SwiftUI

/// Port of the `StatusBadge` component repeated in `index.tsx`/`explore.tsx`.
struct StatusBadge: View {
    let place: Place

    var body: some View {
        let status = PlaceHours.openStatus(for: place)
        let open = PlaceHours.isOpen(status)
        Text(status.shortLabel)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(open ? Theme.openGreen : Theme.closedRed)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill((open ? Theme.openGreen : Theme.closedRed).opacity(0.08))
            )
            .overlay(
                Capsule().stroke((open ? Theme.openGreen : Theme.closedRed).opacity(0.2))
            )
    }
}

/// Port of the `PlaceRow` component in `index.tsx`.
struct PlaceRowView: View {
    let place: Place

    var body: some View {
        HStack(spacing: 12) {
            PlaceImageView(place: place, cornerRadius: 10)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text("\(Categories.emoji(for: place.category)) \(Categories.label(for: place.category))\(place.tags.first.map { " · \($0)" } ?? "")")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            StatusBadge(place: place)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// Port of the `FeaturedCard` component in `index.tsx`.
struct FeaturedCardView: View {
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlaceImageView(place: place)
                .frame(width: 180, height: 130)
            StatusBadge(place: place)
            Text(place.name).font(.system(size: 15, weight: .bold)).lineLimit(2)
            Text("\(Categories.emoji(for: place.category)) \(Categories.label(for: place.category))")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.bottom, 12)
        .frame(width: 180, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
