import MapKit
import PhotosUI
import SwiftUI

/// Pairs a resolved `POIPlace` (with its live `MKMapItem`, recovered from the
/// same-turn candidate array by index) with the AI's reason for suggesting
/// it. Same-file private type, matching `TripDetailScreen`'s `PhotoViewerIndex`.
private struct POIRecommendation: Identifiable {
    let poi: POIPlace
    let aiReason: String
    let confidence: POIRecommendationConfidence
    /// Distance from the anchor used for that turn's POI search — the
    /// user's actual GPS position if no city is being browsed, or the
    /// browsed city's center otherwise (see `search()`). Either way "how far
    /// from here" is the right framing, so the label doesn't need to state
    /// which anchor it is.
    let distanceKm: Double
    var id: UUID { poi.id }
}

private enum ConversationTurn: Identifiable {
    case user(id: String, content: String, image: UIImage?)
    case assistant(id: String, content: String, recommendations: [POIRecommendation], isItinerary: Bool)
    // Distinct from `.assistant` (not just an assistant turn with an error
    // string as content) so it doesn't get sent back to the backend as fake
    // prior assistant history, and so `turnView` can skip the "no matches"
    // subtext that only makes sense for a real, empty AI answer.
    // `retryQuery`/`retryImage` are what actually failed, so a retry button
    // can resubmit the exact same thing instead of making the user retype
    // (and, for a photo question, re-pick the image from scratch).
    case error(id: String, message: String, retryQuery: String, retryImage: UIImage?)

    var id: String {
        switch self {
        case .user(let id, _, _): return id
        case .assistant(let id, _, _, _): return id
        case .error(let id, _, _, _): return id
        }
    }
}

/// Port of `mobile/app/(tabs)/ai.tsx`.
struct AIScreen: View {
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(TripsStore.self) private var tripsStore
    @Environment(CityStore.self) private var cityStore
    @Environment(TabSelection.self) private var tabSelection
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var weatherQuery = WeatherQuery()
    @State private var locationManager = LocationManager()
    @FocusState private var composerFocused: Bool
    @State private var query: String
    @State private var loading = false
    @State private var expandedAssistantTurns: Set<String> = []
    @State private var conversation: [ConversationTurn] = []
    @State private var attachedItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?
    @State private var hasAutoSubmitted = false
    @State private var selectedPOI: POIPlace?
    // Result entries also cache a nil/empty photo URL (checked, no photo found).
    @State private var poiPhotos: [String: PhotoBulkResult] = [:]
    @State private var photosInFlight: Set<String> = []
    /// Turn ids already saved as a Plan collection — keyed separately from
    /// `conversation` (an enum, so its cases can't carry mutable state)
    /// so the "Plan olarak kaydet" button can flip to a done state and stay
    /// there instead of creating a duplicate collection on a second tap.
    @State private var savedPlanTurnIds: Set<String> = []
    /// Tracked so "Temizle" can actually cancel an in-flight request instead
    /// of just wiping the visible conversation out from under it — without
    /// this, a still-running request's answer/error used to land in what
    /// looked like a brand-new empty chat with no explanation.
    @State private var searchTask: Task<Void, Never>?

    private let initialQuery: String?

    init(initialQuery: String? = nil) {
        self.initialQuery = initialQuery
        _query = State(initialValue: initialQuery ?? "")
    }

    private var profile: UserProfile { userProfileStore.profile }

    private var displayedCity: String {
        cityStore.cityName ?? String(localized: "common.everywhere")
    }

    private var cannotSubmit: Bool {
        loading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True only when this instance was pushed via `NavigationLink` (e.g.
    /// Scan's "Ask more") rather than being the Ask Piri tab's own root —
    /// `initialQuery` is `nil` for the tab-root instance `MainTabView`
    /// creates and stays set for the lifetime of a pushed instance, so it
    /// doubles as a reliable "can this screen be popped" flag without
    /// needing to inspect the navigation stack directly.
    private var showBackButton: Bool { initialQuery != nil }

    private var suggestions: [String] {
        let base = [
            String(localized: "ai.suggestions.bestCafes"),
            String(localized: "ai.suggestions.uniqueLocal"),
            String(localized: "ai.suggestions.soloAfternoon"),
            String(localized: "ai.suggestions.bestView"),
        ]
        if let weather = weatherQuery.weather {
            if weather.condition == .rainy || weather.condition == .stormy {
                return [String(localized: "ai.suggestions.cozyRainy")] + Array(base.prefix(3))
            }
            if weather.condition == .sunny, weather.temp > 18 {
                return [String(localized: "ai.suggestions.outdoorTerraces")] + Array(base.prefix(3))
            }
        }
        switch profile.profession {
        case .photographer: return [String(localized: "ai.suggestions.photoSpots")] + Array(base.prefix(3))
        case .architect: return [String(localized: "ai.suggestions.architectureBuildings")] + Array(base.prefix(3))
        case .foodie: return [String(localized: "ai.suggestions.localFood")] + Array(base.prefix(3))
        default: return base
        }
    }

    private var history: [AIConversationMessage] {
        conversation.compactMap { turn in
            switch turn {
            case .user(_, let content, _): return AIConversationMessage(role: .user, content: content)
            case .assistant(_, let content, _, _): return AIConversationMessage(role: .assistant, content: content)
            case .error: return nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        introduction
                        if conversation.isEmpty {
                            emptyState
                        } else {
                            ForEach(conversation) { turn in
                                turnView(turn).id(turn.id)
                            }
                            if loading {
                                ProgressView().tint(Theme.gold).padding(12)
                            }
                        }
                    }
                    .padding(16)
                }
                // See CityPickerScreen: without this, the default
                // `.interactively` keyboard dismissal swallows the first tap
                // on a suggestion chip or result while the input field is
                // still focused, instead of firing it.
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: conversation.count) { _, _ in
                    if let last = conversation.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            inputBar
        }
        .navigationBarHidden(true)
        .task {
            if let lat = cityStore.lat, let lng = cityStore.lng {
                await weatherQuery.load(lat: lat, lng: lng)
            }
            if !hasAutoSubmitted, initialQuery != nil {
                hasAutoSubmitted = true
                try? await Task.sleep(for: .milliseconds(300))
                await search()
            }
        }
        .onChange(of: attachedItem) { _, newItem in
            Task {
                guard let newItem else { return }
                guard let data = try? await newItem.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    // Was a silent no-op on failure — the picker's
                    // selection binding stayed set to the failed item with
                    // no preview ever appearing and no explanation why.
                    attachedItem = nil
                    return
                }
                attachedImage = image
            }
        }
        // `.task(id:)`, not `.onChange` — see the identical comment on
        // MapScreen's `pendingRouteStops` handling. This tab-root AIScreen
        // instance is created once at launch and can easily still be on its
        // very first appearance the first time some other tab hands off a
        // query (e.g. before the user has ever manually opened Ask Piri),
        // and `onChange` never fires for a value that was already set
        // before this view mounted.
        .task(id: tabSelection.pendingAIQuery) {
            guard let newValue = tabSelection.pendingAIQuery else { return }
            query = newValue
            try? await Task.sleep(for: .milliseconds(300))
            await search()
            tabSelection.pendingAIQuery = nil
        }
        .sheet(item: $selectedPOI) { poi in POIExplainSheet(poi: poi) }
        .background(Theme.screenBackground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if showBackButton {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(String(localized: "design.common.back"))
            }
            Image(systemName: "sparkle")
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(Theme.gold)
                .accessibilityHidden(true)
            Text("ai.title")
                .font(.headline)
            Spacer(minLength: 4)
            // Context, not a button: this screen has no existing city-picker action.
            Text(displayedCity)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.cardFill, in: Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
            if !conversation.isEmpty {
                Button {
                    searchTask?.cancel()
                    loading = false
                    conversation = []
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15))
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(Theme.secondaryText)
                .accessibilityLabel(Text("common.clear"))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.navy)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "design.ai.title"))
                .font(Theme.editorial(size: 29))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(L("design.ai.introduction", displayedCity))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ai.tryAsking")
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .padding(.bottom, 4)
            ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                Button {
                    searchTask = Task { await search(overrideQuery: suggestion) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: ["cup.and.saucer", "sparkles", "sun.horizon", "binoculars"][index % 4])
                            .font(.system(size: 19))
                            .foregroundStyle(Theme.gold)
                            .frame(width: 36, height: 36)
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "arrow.up.left")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(12)
                    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(loading)
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func turnView(_ turn: ConversationTurn) -> some View {
        switch turn {
        case .user(_, let content, let image):
            VStack(alignment: .leading, spacing: 8) {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text(content).font(.subheadline).foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: 320, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.navyLight))
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .assistant(let id, let content, let recommendations, let isItinerary):
            VStack(alignment: .leading, spacing: 8) {
                assistantSummary(content, turnID: id, hasCards: !recommendations.isEmpty)

                if recommendations.isEmpty {
                    Text("ai.noMatches").foregroundStyle(.secondary).padding(.horizontal, 4)
                } else {
                    ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, recommendation in
                        // Attribution is a sibling hit target, never a Link inside a Button.
                        ZStack(alignment: .bottomTrailing) {
                            Button {
                                selectedPOI = recommendation.poi
                            } label: {
                                recommendationCard(recommendation, number: index + 1)
                            }
                            .buttonStyle(.plain)
                            photoCredit(for: recommendation.poi)
                        }
                    }
                    // Only offer to save as a Plan when the backend itself
                    // judged this an itinerary-style request (its own
                    // ITINERARY RULE) — a plain "best cafes open now"
                    // answer isn't a plan just because it returned 2+
                    // candidates, and showing the button there every time
                    // was noise unrelated to what was actually asked.
                    if recommendations.count >= 2, isItinerary {
                        saveAsPlanButton(turnId: id, recommendations: recommendations)
                    }
                }
            }
            .task(id: id) { await loadRecommendationPhotos(recommendations) }

        case .error(_, let message, let retryQuery, let retryImage):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.closedRed)
                    Text(message).foregroundStyle(Theme.closedRed)
                }
                Button("common.retry") {
                    query = retryQuery
                    attachedImage = retryImage
                    searchTask = Task { await search() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(loading)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.closedRed.opacity(0.08)))
        }
    }

    private func assistantSummary(_ content: String, turnID: String, hasCards: Bool) -> some View {
        let firstParagraph = content.components(separatedBy: "\n\n").first ?? content
        let canCollapse = hasCards && (firstParagraph != content || content.count > 140)
        let expanded = expandedAssistantTurns.contains(turnID)
        let visible = canCollapse && !expanded ? firstParagraph : content
        let attributed = (try? AttributedString(markdown: visible, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(visible)
        return VStack(alignment: .leading, spacing: 8) {
            Text(attributed)
                .lineLimit(canCollapse && !expanded ? 2 : nil)
                .font(.subheadline)
                .lineSpacing(3)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if canCollapse {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expanded { expandedAssistantTurns.remove(turnID) }
                        else { expandedAssistantTurns.insert(turnID) }
                    }
                } label: {
                    Label(expanded ? String(localized: "design.ai.showLess") : String(localized: "design.ai.fullResponse"), systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(minHeight: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 0.5))
    }

    private func saveAsPlanButton(turnId: String, recommendations: [POIRecommendation]) -> some View {
        let saved = savedPlanTurnIds.contains(turnId)
        return Button {
            guard !saved else { return }
            Haptics.light()
            let name = cityStore.cityName.map { L("ai.savedPlan.name", $0) } ?? String(localized: "ai.savedPlan.nameFallback")
            let collectionId = savedPlacesStore.createCollection(name: name, kind: .plan)
            for recommendation in recommendations {
                savedPlacesStore.toggle(recommendation.poi, inCollection: collectionId)
            }
            savedPlanTurnIds.insert(turnId)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: saved ? "checkmark.circle.fill" : "suitcase.fill")
                Text(saved ? "ai.savedPlan.done" : "ai.savedPlan.cta")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(saved ? Theme.secondaryText : Theme.navy)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14).fill(saved ? Theme.cardFill : Theme.gold))
        }
        .buttonStyle(.plain)
        .disabled(saved)
        .padding(.top, 6)
    }

    private func distanceLabel(_ distanceKm: Double) -> String {
        if distanceKm < 1 {
            let meters = (distanceKm * 1000 / 50).rounded() * 50
            return L("home.distance.meters", String(Int(meters)))
        }
        return L("home.distance.km", String(format: "%.1f", distanceKm))
    }

    private func recommendationCategory(_ poi: POIPlace) -> String {
        guard let category = poi.category,
              let group = POICategoryGroups.all.first(where: { $0.categories?.contains(category) == true }) else { return poi.categoryLabel }
        return String(localized: String.LocalizationValue(group.labelKey))
    }

    private func recommendationCard(_ recommendation: POIRecommendation, number: Int) -> some View {
        let poi = recommendation.poi
        return HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .topLeading) {
                recommendationThumbnail(for: poi)
                Text("\(number)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 21, height: 21)
                    .background(Theme.navyLight, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                    .padding(4)
            }
            .frame(width: 68, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(poi.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text([poi.categoryLabel.isEmpty ? nil : recommendationCategory(poi), distanceLabel(recommendation.distanceKm)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Text(recommendation.aiReason)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                if recommendation.confidence == .weak {
                    Text("ai.weakMatch")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.leading)
        .padding(10)
        .padding(.bottom, photoCreditURL(for: poi) == nil ? 0 : 15)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Theme.border, lineWidth: 0.5))
    }

    private func recommendationThumbnail(for poi: POIPlace) -> some View {
        GeometryReader { geometry in
            if let value = poiPhotos[poi.name]?.photoUrl,
               !value.isEmpty, let url = URL(string: value) {
                CachedAsyncImage(url: url, maxPixelSize: 240) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    recommendationThumbnailFallback(for: poi)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            } else {
                recommendationThumbnailFallback(for: poi)
            }
        }
    }

    private func recommendationThumbnailFallback(for poi: POIPlace) -> some View {
        ZStack {
            LinearGradient(colors: [Theme.navyLight, Theme.navy], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: POICategoryGroups.icon(for: poi.category))
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(Theme.gold)
        }
    }

    private func photoCreditURL(for poi: POIPlace) -> URL? {
        guard let photo = poiPhotos[poi.name],
              let photoURL = photo.photoUrl, !photoURL.isEmpty else { return nil }
        let credit = photo.source == "unsplash" ? photo.photographerUrl : photo.attributionUrl
        return credit.flatMap { URL(string: $0) }
    }

    @ViewBuilder
    private func photoCredit(for poi: POIPlace) -> some View {
        if let photo = poiPhotos[poi.name], let url = photoCreditURL(for: poi) {
            Link(destination: url) {
                Text(photo.source == "unsplash"
                     ? (photo.photographerName.map { "\($0) · Unsplash" } ?? "Unsplash")
                     : (photo.source?.capitalized ?? String(localized: "design.photo.source")))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.navy, in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    @MainActor
    private func loadRecommendationPhotos(_ recommendations: [POIRecommendation]) async {
        var seen: Set<String> = []
        let missing = recommendations.map(\.poi).filter {
            poiPhotos[$0.name] == nil && !photosInFlight.contains($0.name) && seen.insert($0.name).inserted
        }
        guard !missing.isEmpty else { return }
        let names = Set(missing.map(\.name))
        photosInFlight.formUnion(names)
        defer { photosInFlight.subtract(names) }
        // Same cache-first endpoint as Home's `loadNearbyPhotosIfNeeded` --
        // unlike the deliberately-tokenless preview fetches in
        // `POIExplainContent`/`MapScreen` (which stay free to avoid
        // double-charging the paid quota before a user opens full details),
        // this IS the full recommendation list a signed-in user actually
        // sees, same as Home's main grid, so it should get the same
        // paid-tier photo treatment Home's call already does.
        for start in stride(from: 0, to: missing.count, by: 20) {
            guard !Task.isCancelled else { return }
            let batch = missing[start..<min(start + 20, missing.count)]
            let request = PhotoBulkRequest(places: batch.map {
                PhotoBulkPlace(name: $0.name, lat: $0.coordinate.latitude, lng: $0.coordinate.longitude,
                               category: $0.categoryLabel.isEmpty ? nil : $0.categoryLabel)
            })
            guard let response = try? await PlacesAPI.photosBulk(request, token: authStore.token), !Task.isCancelled else { return }
            for result in response.results {
                poiPhotos[result.name] = result
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 10) {
            if let attachedImage {
                HStack(spacing: 8) {
                    Image(uiImage: attachedImage).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                    Button {
                        self.attachedImage = nil
                        self.attachedItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(String(localized: "design.photo.remove"))
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $attachedItem, matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 48)
                        .background(Theme.cardFill, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                }
                .accessibilityLabel(String(localized: "design.photo.attach"))
                .disabled(loading)

                HStack(alignment: .bottom, spacing: 4) {
                    TextField(String(localized: "design.ai.placeholder"), text: $query, axis: .vertical)
                        .accessibilityIdentifier("piri.ai.input")
                        .focused($composerFocused)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .tint(Theme.gold)
                        .lineLimit(1...5)
                        .padding(.leading, 14)
                        .padding(.vertical, 13)
                        .disabled(loading)
                        .onSubmit { searchTask = Task { await search() } }

                    Button {
                        searchTask = Task { await search() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Theme.navy)
                            .frame(width: 36, height: 36)
                            .background(Theme.gold, in: Circle())
                            .frame(width: 44, height: 48)
                    }
                    .accessibilityLabel(Text("ai.ask"))
                    .accessibilityIdentifier("piri.ai.send")
                    .disabled(cannotSubmit)
                    .opacity(cannotSubmit ? 0.45 : 1)
                }
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.border, lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.navy)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }

    /// Nearby Apple POIs are looked up fresh per message rather than reused
    /// across turns — keeps candidates current with whatever city/location
    /// is active right now, and avoids stale-index bugs across turns since
    /// each turn's `[POIPlace]` array only ever needs to outlive that one
    /// exchange (see `POIRecommendation`, which embeds the resolved
    /// `POIPlace` directly into the conversation turn).
    private func nearbyPOICandidates(query: String, near coordinate: CLLocationCoordinate2D) async -> [POIPlace] {
        // Always merge in a plain category-less browse, not just when the
        // text search comes up short — `naturalLanguageQuery` is built for
        // short search terms ("coffee", "pizza"), not a full natural-
        // language question like "şu an açık en iyi kafeler". Sent whole,
        // it can fuzzy-match 8+ loosely-related local businesses by
        // word-fragment overlap alone (confirmed live: it returned unrelated
        // Norwegian company listings for a "best cafes open now" question),
        // which used to block the real fallback merge below from ever
        // running since it only fired when results were sparse. Actual
        // nearby POIs are now unconditionally in the pool for the AI to
        // choose from, regardless of how the free-text match went.
        async let textResults = POISearchService.search(near: coordinate, categories: nil, naturalLanguageQuery: query)
        async let browseResults = POISearchService.search(near: coordinate, categories: nil)
        // A themed ask ("sanatsal bir deneyim") has no chance against a
        // plain nearest-first browse in a city with thousands of POIs — the
        // nearest 24 things of any kind are almost never mostly museums.
        // `inferredCategories` maps the query's own words to the relevant
        // Apple categories so there's an actually-targeted search feeding
        // the pool, not just a bigger pile of the same generic nearby noise.
        async let themedResults = fetchThemedCandidates(
            POICategoryGroups.inferredCategories(fromQuery: query),
            near: coordinate
        )
        // Confirmed live: Apple's own un-filtered nearby ranking can bury a
        // city's own cathedral below the ~25-result cap entirely (Kristiansand
        // Domkirke never appeared in a plain radius browse, only when
        // searched by name directly) — so a generic "plan my day" request,
        // with no theme keyword to trigger `themedResults` above, would
        // never even have it as an option. Unlike `themedResults`, this
        // always runs regardless of query wording, since a city's core
        // sights are relevant background for nearly any Ask Piri request,
        // not just explicitly themed ones.
        async let coreSightResults = fetchThemedCandidates(POICategoryGroups.coreSightCategories, near: coordinate)

        func sortedByDistance(_ items: [POIPlace]) -> [POIPlace] {
            items.sorted {
                geoDistanceKm($0.coordinate.latitude, $0.coordinate.longitude, coordinate.latitude, coordinate.longitude)
                    < geoDistanceKm($1.coordinate.latitude, $1.coordinate.longitude, coordinate.latitude, coordinate.longitude)
            }
        }

        var seenNames = Set<String>()
        var prioritized: [POIPlace] = []
        func appendUnique(_ items: [POIPlace]) {
            for item in items {
                let key = item.name.lowercased()
                guard !seenNames.contains(key) else { continue }
                seenNames.insert(key)
                prioritized.append(item)
            }
        }

        // Themed matches go first and survive the cap even when they're
        // farther away than a pile of unrelated nearby places — a flat
        // distance sort across everything would bury them below the cutoff
        // before the model ever sees them. Core sights come right after —
        // still ahead of the generic text/browse noise, but yielding to an
        // explicit theme match (e.g. a "sanat" query's museum-heavy results)
        // when there is one.
        appendUnique(sortedByDistance(await themedResults))
        appendUnique(sortedByDistance(await coreSightResults))
        appendUnique(sortedByDistance(await textResults))
        appendUnique(sortedByDistance(await browseResults))

        return Array(prioritized.prefix(30))
    }

    private func fetchThemedCandidates(_ categories: Set<MKPointOfInterestCategory>?, near coordinate: CLLocationCoordinate2D) async -> [POIPlace] {
        guard let categories else { return [] }
        return await POISearchService.search(near: coordinate, categories: categories)
    }

    private func search(overrideQuery: String? = nil) async {
        // The UI already disables Ask/submit while `loading`, but that's a
        // rendering-timing guard, not a real one — two taps (or Return +
        // Ask) landing in the same render tick could both reach here before
        // SwiftUI applies `.disabled`, firing two LLM requests for one input.
        guard !loading else { return }
        let nextQuery = (overrideQuery ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextQuery.isEmpty else { return }
        composerFocused = false

        let imageForRequest = overrideQuery == nil ? attachedImage : nil
        loading = true
        query = ""
        attachedImage = nil
        attachedItem = nil

        conversation.append(.user(id: "\(Date().timeIntervalSince1970)-user", content: nextQuery, image: imageForRequest))

        // cityStore first (matches HomeScreen.loadPOIs's precedent — "near
        // the city being browsed," not necessarily near the device), GPS
        // fallback. A deliberate, small behavior change from the old
        // GPS-only lookup, aligning Ask Piri with how Home/Map already work.
        let coordinate: CLLocationCoordinate2D?
        if let lat = cityStore.lat, let lng = cityStore.lng {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            coordinate = await locationManager.currentLocationOnce()
        }

        var candidates: [POIPlace] = []
        if let coordinate {
            candidates = await nearbyPOICandidates(query: nextQuery, near: coordinate)
        }
        // Empty candidates isn't an error — a normal, backend-handled state
        // (no location, or an area with little Apple POI data). The request
        // still goes out so chit-chat/general-knowledge answers keep working.

        let profile = userProfileStore.profile

        let request = RecommendPOIRequest(
            query: nextQuery,
            // `/places/recommend-poi` rejects any request over 8 messages
            // (`chatMessageSchema` array cap, server-side) — sending the
            // full, unbounded `history` meant every conversation broke
            // outright on its 6th exchange (validation failure, opaque
            // message, only recoverable by tapping Clear and losing
            // everything). Trim to the same cap; the full conversation
            // still stays visible in the UI, only what's sent as context
            // to the model is bounded.
            messages: Array(history.suffix(8)),
            userProfile: PersonalizationProfile(
                name: profile.name,
                profession: profile.professionText,
                interests: profile.interestsText,
                faith: profile.faith?.rawValue,
                budget: profile.budget?.rawValue,
                groupType: profile.groupType?.rawValue,
                pace: profile.pace?.rawValue
            ),
            weather: weatherQuery.weather.map { WeatherContext(condition: $0.condition.rawValue, temp: $0.temp, city: $0.city, description: $0.description) },
            city: cityStore.cityName,
            lat: coordinate?.latitude,
            lng: coordinate?.longitude,
            poiCandidates: candidates.map {
                POICandidateInput(
                    name: $0.name,
                    category: $0.categoryLabel.isEmpty ? nil : $0.categoryLabel,
                    lat: $0.coordinate.latitude,
                    lng: $0.coordinate.longitude,
                    address: $0.mapItem.placemark.title
                )
            },
            imageBase64: imageForRequest?.jpegData(compressionQuality: 0.6)?.base64EncodedString(),
            mimeType: imageForRequest != nil ? "image/jpeg" : nil,
            locale: Locale.current.language.languageCode?.identifier,
            recentlyViewed: recentlyViewedStore.asPersonalizationSummaries,
            savedPlaces: savedPlacesStore.asPersonalizationSummaries,
            pastTrips: tripsStore.asPersonalizationSummaries
        )

        do {
            let response = try await PlacesAPI.recommendPOI(request)
            // Defensive bounds check client-side too, even though the
            // server already validates indices — never trust blindly.
            let resolved = response.recommendations.compactMap { rec -> POIRecommendation? in
                guard candidates.indices.contains(rec.index) else { return nil }
                let poi = candidates[rec.index]
                let distanceKm = coordinate.map {
                    geoDistanceKm(poi.coordinate.latitude, poi.coordinate.longitude, $0.latitude, $0.longitude)
                } ?? 0
                return POIRecommendation(poi: poi, aiReason: rec.aiReason, confidence: rec.confidence, distanceKm: distanceKm)
            }
            // "Temizle" cancels `searchTask` but a request already in
            // flight keeps running to completion regardless — without this
            // check, its answer could land in a conversation the user
            // already cleared, looking like a stray message out of nowhere.
            guard !Task.isCancelled else { return }
            conversation.append(.assistant(id: "\(Date().timeIntervalSince1970)-assistant", content: response.answer, recommendations: resolved, isItinerary: response.isItinerary))
        } catch {
            guard !Task.isCancelled else { return }
            query = nextQuery
            // Restore the photo too, not just the text — previously only
            // the query was put back, so retrying a failed photo question
            // meant re-picking the same image from scratch.
            attachedImage = imageForRequest
            conversation.append(.error(id: "\(Date().timeIntervalSince1970)-error", message: error.localizedDescription, retryQuery: nextQuery, retryImage: imageForRequest))
        }
        guard !Task.isCancelled else { return }
        loading = false
    }
}
