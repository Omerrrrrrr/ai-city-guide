import SwiftUI

/// Real Tripadvisor traveler reviews for one place — separate from
/// `POIExplainSheet`'s own AI blurb, which only ever cites a rating number
/// and (at most) a short paraphrase. Fetched lazily on open via
/// `/places/reviews`, never as part of the initial card load.
struct TripAdvisorReviewsSheet: View {
    let poi: POIPlace
    /// From the rating widget's own review count — compared against how
    /// many `/places/reviews` actually returns so a real gap (Tripadvisor's
    /// Content API only ever returns their 3 most recent reviews per
    /// location, confirmed live against a place with 36 total, regardless
    /// of the `size` requested — a paid-tier limitation on their end, not
    /// a bug here) gets an honest note instead of silently looking like
    /// "See all 36 reviews" under-delivered.
    var totalReviewCount: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var reviews: [TripAdvisorReview] = []
    @State private var tripadvisorUrl: String?
    @State private var loading = true
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(0..<3, id: \.self) { _ in reviewSkeleton }
                        }
                        .padding()
                    }
                } else if reviews.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let totalReviewCount, totalReviewCount > reviews.count {
                                Text(L("poiReviews.moreOnTripadvisor", reviews.count, totalReviewCount))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(reviews) { review in reviewRow(review) }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(String(localized: "poiReviews.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                if let tripadvisorUrl, let url = URL(string: tripadvisorUrl) {
                    ToolbarItem(placement: .confirmationAction) {
                        Link(destination: url) {
                            Text("poiReviews.openOnTripadvisor")
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble").font(.system(size: 32)).foregroundStyle(.secondary)
            Text(loadFailed ? "poiReviews.loadFailed" : "poiReviews.empty")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reviewSkeleton: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color(.secondarySystemBackground)).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBox().frame(width: 120, height: 12)
                SkeletonBox().frame(height: 10)
                SkeletonBox().frame(width: 200, height: 10)
            }
        }
    }

    private func reviewRow(_ review: TripAdvisorReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if let avatarUrl = review.authorAvatarUrl, let url = URL(string: avatarUrl) {
                    CachedAsyncImage(url: url, maxPixelSize: 80) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle().fill(Color(.secondarySystemBackground))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Circle().fill(Color(.secondarySystemBackground))
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(review.authorName).font(.subheadline.bold())
                    if let location = review.authorLocation {
                        Text(location).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                starRow(review.rating)
            }

            if let title = review.title, !title.isEmpty {
                Text(title).font(.subheadline.bold())
            }
            Text(review.text).font(.footnote).foregroundStyle(.secondary)
            Text(formattedDate(review.publishedAt)).font(.caption2).foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func starRow(_ rating: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < rating ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.gold)
            }
        }
    }

    private func formattedDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let response = try await PlacesAPI.reviews(ReviewsRequest(
                name: poi.name,
                lat: poi.coordinate.latitude,
                lng: poi.coordinate.longitude
            ))
            reviews = response.reviews
            tripadvisorUrl = response.tripadvisorUrl
        } catch {
            loadFailed = true
        }
    }
}
