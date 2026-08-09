import SwiftUI

/// Renders a Tripadvisor rating using their own bubble-rating icon image
/// (`rating.iconUrl`) — their display terms require using the rating
/// graphic they provide rather than a custom-built one. Tapping opens the
/// review page on tripadvisor.com.
struct TripAdvisorRatingRow: View {
    let rating: TripAdvisorRating

    var body: some View {
        Link(destination: URL(string: rating.url) ?? URL(string: "https://www.tripadvisor.com")!) {
            HStack(spacing: 6) {
                CachedAsyncImage(url: URL(string: rating.iconUrl), maxPixelSize: 120) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color.clear
                }
                .frame(height: 20)

                Text("\(rating.score, specifier: "%.1f") (\(rating.reviewCount))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Tripadvisor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
