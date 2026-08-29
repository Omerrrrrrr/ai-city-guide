import SwiftUI

/// Combines Piri's own reviews with the two read-only third-party ratings
/// (Tripadvisor, Google) already available on `ExplainResult` into one
/// section: a combined average (only shown once all three sources exist —
/// two sources disagreeing with no tiebreaker reads as less trustworthy
/// than just showing them separately), a per-source breakdown, Piri's own
/// review list, and a way to leave one.
struct PiriReviewsSection: View {
    let poi: POIPlace
    let tripAdvisorRating: TripAdvisorRating?
    let googleRating: SourceRating?

    @Environment(AuthStore.self) private var authStore
    @State private var piriReviews: POIReviewsResponse?
    @State private var showingWriteReview = false

    private var piriSource: SourceRating? {
        guard let piriReviews, let average = piriReviews.average, piriReviews.count > 0 else { return nil }
        return SourceRating(rating: average, count: piriReviews.count)
    }

    private var sources: [(label: String, rating: SourceRating)] {
        var result: [(String, SourceRating)] = []
        if let tripAdvisorRating {
            result.append(("Tripadvisor", SourceRating(rating: tripAdvisorRating.score, count: tripAdvisorRating.reviewCount)))
        }
        if let googleRating {
            result.append(("Google", googleRating))
        }
        if let piriSource {
            result.append(("Piri", piriSource))
        }
        return result
    }

    // Only meaningful with all three sources -- two disagreeing ratings
    // with nothing to break the tie reads as noise, not a real average.
    private var combinedAverage: Double? {
        guard sources.count >= 3 else { return nil }
        return sources.reduce(0) { $0 + $1.rating.rating } / Double(sources.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let combinedAverage {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill").foregroundStyle(Theme.gold)
                    Text(String(format: "%.1f", combinedAverage)).font(.system(size: 20, weight: .bold))
                    Text(L("poiReviews.combinedFrom", sources.count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(sources, id: \.label) { source in
                HStack(spacing: 6) {
                    Text(source.label).font(.footnote.weight(.semibold)).frame(width: 84, alignment: .leading)
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.gold)
                    Text(String(format: "%.1f", source.rating.rating)).font(.footnote)
                    Text("(\(source.rating.count))").font(.caption).foregroundStyle(.secondary)
                }
            }

            Button {
                Haptics.light()
                showingWriteReview = true
            } label: {
                Label(String(localized: piriSource == nil ? "poiReviews.write" : "poiReviews.editMine"), systemImage: "square.and.pencil")
                    .font(.footnote.weight(.semibold))
            }

            if let piriReviews, !piriReviews.reviews.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(piriReviews.reviews) { review in
                        reviewRow(review)
                    }
                }
                .padding(.top, 4)
            }
        }
        .task { await loadReviews() }
        .sheet(isPresented: $showingWriteReview) {
            WriteReviewSheet(poi: poi, existing: piriReviews?.reviews.first { $0.userId == authStore.user?.id }) {
                Task { await loadReviews() }
            }
        }
    }

    private func reviewRow(_ review: POIReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= review.rating ? "star.fill" : "star")
                        .font(.caption2)
                        .foregroundStyle(Theme.gold)
                }
            }
            if let text = review.text, !text.isEmpty {
                Text(text).font(.footnote)
            }
        }
    }

    private func loadReviews() async {
        piriReviews = try? await PiriReviewsAPI.fetchReviews(
            name: poi.name,
            lat: poi.coordinate.latitude,
            lng: poi.coordinate.longitude,
            token: authStore.token
        )
    }
}

private struct WriteReviewSheet: View {
    let poi: POIPlace
    let existing: POIReview?
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore
    @State private var rating = 0
    @State private var text = ""
    @State private var submitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            Haptics.light()
                            rating = star
                        } label: {
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.system(size: 32))
                                .foregroundStyle(Theme.gold)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 24)

                TextField(String(localized: "poiReviews.textPlaceholder"), text: $text, axis: .vertical)
                    .lineLimit(4...8)
                    .textFieldStyle(.roundedBorder)

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(Theme.closedRed)
                }

                Spacer()
            }
            .padding()
            .navigationTitle(String(localized: "poiReviews.write"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { Task { await submit() } }
                        .disabled(rating == 0 || submitting)
                }
            }
        }
        .task {
            if let existing {
                rating = existing.rating
                text = existing.text ?? ""
            }
        }
    }

    private func submit() async {
        guard let token = authStore.token else { return }
        submitting = true
        defer { submitting = false }
        do {
            _ = try await PiriReviewsAPI.submit(
                SubmitReviewRequest(
                    poiName: poi.name,
                    lat: poi.coordinate.latitude,
                    lng: poi.coordinate.longitude,
                    rating: rating,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
                ),
                token: token
            )
            onSubmitted()
            dismiss()
        } catch {
            errorMessage = String(localized: "poiReviews.submitFailed")
        }
    }
}
