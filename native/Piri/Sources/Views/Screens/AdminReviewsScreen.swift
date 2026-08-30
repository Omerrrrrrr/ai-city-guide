import SwiftUI

private let statusFilters: [(labelKey: String, value: String)] = [
    ("adminReviews.filters.flagged", "flagged"),
    ("adminReviews.filters.approved", "approved"),
    ("adminReviews.filters.rejected", "rejected"),
]

/// The admin side of the trust-scaled review-moderation queue (see the
/// backend's `/admin/reviews` + the two-tier threshold algorithm in
/// `apps/api/src/index.ts`) -- same `AdminGateView`/`AdminAPI` shape as
/// `AdminImagesScreen`, just for reviews that crossed the report-flag
/// threshold and need a human verdict instead of an automatic one.
struct AdminReviewsScreen: View {
    var body: some View {
        AdminGateView {
            AdminReviewsContent()
        }
        .navigationTitle("adminReviews.hero.title")
    }
}

private struct AdminReviewsContent: View {
    @Environment(\.adminToken) private var token

    @State private var statusFilter = "flagged"
    @State private var reviews: [AdminReviewRow] = []
    @State private var isLoading = true
    @State private var activeReviewId: String?
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("adminReviews.hero.title").font(.title.bold())
                    Text("adminReviews.hero.body").foregroundStyle(.secondary)
                }

                HStack {
                    ForEach(statusFilters, id: \.labelKey) { filter in
                        let selected = filter.value == statusFilter
                        Button(String(localized: String.LocalizationValue(filter.labelKey))) {
                            statusFilter = filter.value
                            Task { await loadReviews() }
                        }
                        .buttonStyle(.bordered)
                        .tint(selected ? .blue : .gray)
                    }
                }

                if let infoMessage { Text(infoMessage).foregroundStyle(.green) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }

                if isLoading { Text("adminReviews.loading").foregroundStyle(.secondary) }
                if !isLoading, reviews.isEmpty {
                    card { Text("adminReviews.empty").foregroundStyle(.secondary) }
                }

                ForEach(reviews) { review in
                    reviewCard(review)
                }
            }
            .padding(16)
        }
        .task { await loadReviews() }
    }

    private func reviewCard(_ review: AdminReviewRow) -> some View {
        let isBusy = activeReviewId == review.id

        return card {
            Text(review.poiName).font(.headline)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= review.rating ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(Theme.gold)
                }
                if review.verifiedVisit {
                    Text("poiReviews.verifiedVisit").font(.caption.weight(.semibold)).foregroundStyle(Theme.openGreen)
                }
            }
            if let text = review.text, !text.isEmpty {
                Text(text).font(.subheadline)
            }
            if let reason = review.moderationReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            Text(L("adminReviews.userLine", review.userId, review.createdAt)).font(.caption2).foregroundStyle(.secondary)

            if statusFilter == "flagged" {
                HStack {
                    Button(isBusy ? String(localized: "common.saving") : String(localized: "adminReviews.actions.approve")) {
                        Task { await approve(review) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)

                    Button("adminReviews.actions.reject") {
                        Task { await reject(review) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }
            }
        }
    }

    private func loadReviews() async {
        guard !token.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            reviews = try await AdminAPI.fetchReviews(status: statusFilter, token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func approve(_ review: AdminReviewRow) async {
        guard !token.isEmpty else { return }
        activeReviewId = review.id
        errorMessage = nil
        do {
            try await AdminAPI.approveReview(id: review.id, token: token)
            infoMessage = String(localized: "adminReviews.info.approved")
            await loadReviews()
        } catch {
            errorMessage = error.localizedDescription
        }
        activeReviewId = nil
    }

    private func reject(_ review: AdminReviewRow) async {
        guard !token.isEmpty else { return }
        activeReviewId = review.id
        errorMessage = nil
        do {
            try await AdminAPI.rejectReview(id: review.id, token: token)
            infoMessage = String(localized: "adminReviews.info.rejected")
            await loadReviews()
        } catch {
            errorMessage = error.localizedDescription
        }
        activeReviewId = nil
    }

    @ViewBuilder
    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.18)))
    }
}
