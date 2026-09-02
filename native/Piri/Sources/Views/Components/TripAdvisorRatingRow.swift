import SwiftUI

/// Renders a Tripadvisor rating using their own bubble-rating icon image
/// (`rating.iconUrl`) — their display terms require using the rating
/// graphic they provide rather than a custom-built one. Tapping opens the
/// review page on tripadvisor.com.
struct TripAdvisorRatingRow: View {
    let rating: TripAdvisorRating
    /// `false` when the caller shows the formatted hours lines itself
    /// elsewhere (e.g. grouped into a "Good to know" section instead of
    /// living here next to the bubble/score) -- avoids showing the same
    /// hours text twice on one card.
    var showHours: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

                    if let isOpenNow = rating.isOpenNow {
                        Text(isOpenNow ? "tripadvisor.openNow" : "tripadvisor.closedNow")
                            .font(.caption.bold())
                            .foregroundStyle(isOpenNow ? Theme.openGreen : Theme.closedRed)
                    }
                }
            }

            if showHours, let hoursFormatted = rating.hoursFormatted {
                ForEach(hoursFormatted, id: \.self) { line in
                    Text(TripAdvisorHours.humanize(line)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
