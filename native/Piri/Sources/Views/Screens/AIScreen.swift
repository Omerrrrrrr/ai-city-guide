import MapKit
import PhotosUI
import SwiftUI

/// Pairs a resolved `POIPlace` (with its live `MKMapItem`, recovered from the
/// same-turn candidate array by index) with the AI's reason for suggesting
/// it. Same-file private type, matching `TripDetailScreen`'s `PhotoViewerIndex`.
private struct POIRecommendation: Identifiable {
    let poi: POIPlace
    let aiReason: String
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
    case assistant(id: String, content: String, recommendations: [POIRecommendation])

    var id: String {
        switch self {
        case .user(let id, _, _): return id
        case .assistant(let id, _, _): return id
        }
    }
}

/// Port of `mobile/app/(tabs)/ai.tsx`.
struct AIScreen: View {
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @Environment(CityStore.self) private var cityStore
    @Environment(TabSelection.self) private var tabSelection
    @Environment(\.dismiss) private var dismiss

    @State private var weatherQuery = WeatherQuery()
    @State private var locationManager = LocationManager()
    @State private var query: String
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var conversation: [ConversationTurn] = []
    @State private var attachedItem: PhotosPickerItem?
    @State private var attachedImage: UIImage?
    @State private var hasAutoSubmitted = false
    @State private var selectedPOI: POIPlace?

    private let initialQuery: String?

    init(initialQuery: String? = nil) {
        self.initialQuery = initialQuery
        _query = State(initialValue: initialQuery ?? "")
    }

    private var profile: UserProfile { userProfileStore.profile }

    /// True only when this instance was pushed via `NavigationLink` (e.g.
    /// Scan's "Ask more") rather than being the Ask Piri tab's own root —
    /// `initialQuery` is `nil` for the tab-root instance `MainTabView`
    /// creates and stays set for the lifetime of a pushed instance, so it
    /// doubles as a reliable "can this screen be popped" flag without
    /// needing to inspect the navigation stack directly.
    private var showBackButton: Bool { initialQuery != nil }

    private var suggestions: [String] {
        var base = [
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
        conversation.map { turn in
            switch turn {
            case .user(_, let content, _): return AIConversationMessage(role: .user, content: content)
            case .assistant(_, let content, _): return AIConversationMessage(role: .assistant, content: content)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(Theme.closedRed)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.closedRed.opacity(0.08)))
                        }

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
                guard let newItem, let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                attachedImage = UIImage(data: data)
            }
        }
        .onChange(of: tabSelection.pendingAIQuery) { _, newValue in
            guard let newValue else { return }
            tabSelection.pendingAIQuery = nil
            query = newValue
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await search()
            }
        }
        .sheet(item: $selectedPOI) { poi in POIExplainSheet(poi: poi) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            if showBackButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                }
                .padding(.trailing, 4)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("ai.title").font(.system(size: 26, weight: .heavy)).tracking(1).foregroundStyle(Theme.gold)
                if let weather = weatherQuery.weather {
                    Text(L("ai.headerSub.withWeather", weather.condition.emoji, String(Int(weather.temp)), cityStore.cityName ?? String(localized: "common.everywhere")))
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
                } else {
                    Text(cityStore.cityName ?? String(localized: "ai.headerSub.fallback"))
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
                }
            }
            Spacer()
            if !conversation.isEmpty {
                Button("common.clear") {
                    conversation = []
                    errorMessage = nil
                }
                .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Theme.navy)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ai.tryAsking")
                .font(.system(size: 13, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            FlowLayout(spacing: 10) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        Task { await search(overrideQuery: suggestion) }
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.navy.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.navy.opacity(0.15)))
                    }
                }
            }
        }
        .padding(.top, 24)
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
                Text(content).foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: 320, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.navy))
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .assistant(_, let content, let recommendations):
            VStack(alignment: .leading, spacing: 12) {
                Text(content)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))

                if recommendations.isEmpty {
                    Text("ai.noMatches").foregroundStyle(.secondary).padding(.horizontal, 4)
                } else {
                    ForEach(recommendations) { recommendation in
                        Button {
                            selectedPOI = recommendation.poi
                        } label: {
                            recommendationCard(recommendation)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func distanceLabel(_ distanceKm: Double) -> String {
        if distanceKm < 1 {
            let meters = (distanceKm * 1000 / 50).rounded() * 50
            return L("home.distance.meters", String(Int(meters)))
        }
        return L("home.distance.km", String(format: "%.1f", distanceKm))
    }

    private func recommendationCard(_ recommendation: POIRecommendation) -> some View {
        let poi = recommendation.poi
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: POICategoryGroups.icon(for: poi.category))
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.gold.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(poi.name).font(.system(size: 18, weight: .bold))
                    Text(
                        [poi.categoryLabel.isEmpty ? nil : poi.categoryLabel, distanceLabel(recommendation.distanceKm)]
                            .compactMap { $0 }
                            .joined(separator: " · ")
                    )
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Text("✨")
                Text(recommendation.aiReason).font(.system(size: 14, weight: .medium)).foregroundStyle(Color(red: 0.61, green: 0.48, blue: 0.1))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.gold.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold.opacity(0.25)))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            if let attachedImage {
                HStack {
                    Image(uiImage: attachedImage).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                    Button {
                        self.attachedImage = nil
                        self.attachedItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            HStack(spacing: 8) {
                PhotosPicker(selection: $attachedItem, matching: .images) {
                    Image(systemName: "camera")
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(.secondary.opacity(0.3)))
                }
                .disabled(loading)

                TextField(String(localized: "ai.inputPlaceholder"), text: $query)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Color(.secondarySystemBackground)))
                    .disabled(loading)
                    .onSubmit { Task { await search() } }

                Button {
                    Task { await search() }
                } label: {
                    Text("ai.ask")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.navy))
                }
                .disabled(loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(loading || query.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    /// Nearby Apple POIs are looked up fresh per message rather than reused
    /// across turns — keeps candidates current with whatever city/location
    /// is active right now, and avoids stale-index bugs across turns since
    /// each turn's `[POIPlace]` array only ever needs to outlive that one
    /// exchange (see `POIRecommendation`, which embeds the resolved
    /// `POIPlace` directly into the conversation turn).
    private func nearbyPOICandidates(query: String, near coordinate: CLLocationCoordinate2D) async -> [POIPlace] {
        let textResults = await POISearchService.search(near: coordinate, categories: nil, naturalLanguageQuery: query)
        var combined = textResults
        if combined.count < 8 {
            let browseResults = await POISearchService.search(near: coordinate, categories: nil)
            let existingNames = Set(combined.map { $0.name.lowercased() })
            combined += browseResults.filter { !existingNames.contains($0.name.lowercased()) }
        }
        return combined
            .sorted {
                geoDistanceKm($0.coordinate.latitude, $0.coordinate.longitude, coordinate.latitude, coordinate.longitude)
                    < geoDistanceKm($1.coordinate.latitude, $1.coordinate.longitude, coordinate.latitude, coordinate.longitude)
            }
            .prefix(24)
            .map { $0 }
    }

    private func search(overrideQuery: String? = nil) async {
        let nextQuery = (overrideQuery ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextQuery.isEmpty else { return }

        let imageForRequest = overrideQuery == nil ? attachedImage : nil
        loading = true
        errorMessage = nil
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
            messages: history,
            userProfile: PersonalizationProfile(
                name: profile.name,
                profession: profile.profession?.rawValue,
                interests: profile.interests.map(\.rawValue),
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
            // `RecentlyViewedStore` holds Apple POI references now, not
            // curated DB ids — nothing left for the backend to resolve
            // recently-viewed summaries against.
            recentlyViewedPlaceIds: nil
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
                return POIRecommendation(poi: poi, aiReason: rec.aiReason, distanceKm: distanceKm)
            }
            conversation.append(.assistant(id: "\(Date().timeIntervalSince1970)-assistant", content: response.answer, recommendations: resolved))
        } catch {
            query = nextQuery
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}
