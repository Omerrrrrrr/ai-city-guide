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
    /// `ExplainResult.piriRating` — already resolved server-side, so the
    /// combined average below can include Piri's number immediately
    /// instead of waiting on this section's own `GET /poi/reviews` call
    /// (still made, for the full review list/text) to come back first.
    let initialPiriRating: SourceRating?
    /// `ExplainResult.reviewsSummary` — an AI-synthesized "what reviewers
    /// say" sentence, already grounded server-side; `nil` when there
    /// wasn't enough real review text to honestly summarize.
    let reviewsSummary: String?
    /// `ExplainResult.aspectHighlights` — specific things real reviewers
    /// discussed, each with its own sentiment; empty when there wasn't
    /// enough real review text to draw any from.
    let aspectHighlights: [AspectHighlight]

    @Environment(AuthStore.self) private var authStore
    @Environment(LanguageStore.self) private var languageStore
    @State private var piriReviews: POIReviewsResponse?
    @State private var showingWriteReview = false
    @State private var translations: [String: TranslationResult] = [:]
    @State private var translatingIds: Set<String> = []
    @State private var showingTranslated: Set<String> = []

    /// `LanguageStore.code` is `nil` for "follow system" -- falls back to
    /// the device's own language, then plain English.
    private var targetLangCode: String {
        languageStore.code ?? Locale.current.language.languageCode?.identifier ?? "en"
    }

    private var piriSource: SourceRating? {
        // Not loaded yet -- use the value handed to us already rather than
        // showing "no Piri rating" for the second or two this section's
        // own fetch takes.
        guard let piriReviews else { return initialPiriRating }
        guard let average = piriReviews.average, piriReviews.count > 0 else { return nil }
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

            if let reviewsSummary {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.bubble.fill").font(.caption).foregroundStyle(Theme.gold)
                    Text(reviewsSummary).font(.footnote.italic())
                }
            }

            if !aspectHighlights.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(aspectHighlights, id: \.aspect) { highlight in
                        aspectChip(highlight)
                    }
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

    private func aspectChip(_ highlight: AspectHighlight) -> some View {
        let color: Color = {
            switch highlight.sentiment {
            case .positive: return Theme.openGreen
            case .mixed: return .secondary
            case .negative: return Theme.closedRed
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(highlight.aspect)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.1)))
    }

    private func reviewRow(_ review: POIReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= review.rating ? "star.fill" : "star")
                        .font(.caption2)
                        .foregroundStyle(Theme.gold)
                }
                if review.verifiedVisit {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("poiReviews.verifiedVisit")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.openGreen)
                    .padding(.leading, 4)
                }
            }
            if let text = review.text, !text.isEmpty {
                if showingTranslated.contains(review.id), let translation = translations[review.id] {
                    Text(translation.translatedText).font(.footnote)
                    if let source = translation.detectedSourceLang {
                        Text(L("poiReviews.translatedFrom", source.uppercased()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(text).font(.footnote)
                }
                translateButton(review: review, text: text)
            }
            HStack(spacing: 14) {
                voteButton(review: review, helpful: true, icon: "hand.thumbsup", count: review.helpfulCount)
                voteButton(review: review, helpful: false, icon: "hand.thumbsdown", count: review.notHelpfulCount)
            }
            .padding(.top, 2)
        }
    }

    private func voteButton(review: POIReview, helpful: Bool, icon: String, count: Int) -> some View {
        let active = review.myVote == helpful
        return Button {
            castVote(reviewId: review.id, helpful: helpful)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: active ? "\(icon).fill" : icon)
                if count > 0 {
                    Text("\(count)")
                }
            }
            .font(.caption)
            .foregroundStyle(active ? Theme.gold : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(authStore.token == nil)
        .opacity(authStore.token == nil ? 0.5 : 1)
    }

    private func castVote(reviewId: String, helpful: Bool) {
        guard let token = authStore.token else { return }
        Haptics.light()
        Task {
            try? await PiriReviewsAPI.vote(reviewId: reviewId, helpful: helpful, token: token)
            await loadReviews()
        }
    }

    private func translateButton(review: POIReview, text: String) -> some View {
        Button {
            Haptics.light()
            if translations[review.id] != nil {
                if showingTranslated.contains(review.id) {
                    showingTranslated.remove(review.id)
                } else {
                    showingTranslated.insert(review.id)
                }
            } else {
                Task { await translate(review: review, text: text) }
            }
        } label: {
            HStack(spacing: 4) {
                if translatingIds.contains(review.id) {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "globe")
                    Text(showingTranslated.contains(review.id) ? "poiReviews.showOriginal" : "poiReviews.translate")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(translatingIds.contains(review.id))
        .padding(.top, 2)
    }

    private func translate(review: POIReview, text: String) async {
        translatingIds.insert(review.id)
        defer { translatingIds.remove(review.id) }
        if let result = try? await TranslateAPI.translate(text: text, targetLang: targetLangCode) {
            translations[review.id] = result
            showingTranslated.insert(review.id)
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
    @Environment(MyReviewsStore.self) private var myReviewsStore
    @Environment(TripsStore.self) private var tripsStore
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
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text,
                    visited: tripsStore.hasVisited(lat: poi.coordinate.latitude, lng: poi.coordinate.longitude)
                ),
                token: token
            )
            // Only a genuinely new review earns XP -- `existing` is set
            // when this sheet opened to edit one already written, which
            // re-uses the same backend upsert and shouldn't grant it twice.
            if existing == nil {
                myReviewsStore.recordReviewWritten()
            }
            onSubmitted()
            dismiss()
        } catch {
            errorMessage = String(localized: "poiReviews.submitFailed")
        }
    }
}
