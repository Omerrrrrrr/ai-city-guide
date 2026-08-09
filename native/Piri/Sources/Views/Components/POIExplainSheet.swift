import MapKit
import SwiftUI

/// Sheet-presented version of the personalized AI blurb `MapScreen` shows
/// inline over the map — used by list-based screens (Home) that browse
/// Apple POIs without a map view to tap into. Same `/places/explain-poi`
/// backend call, same non-persisted, session-only behavior. A lightweight
/// follow-up chat (`/places/explain-poi/chat`) lets the user keep asking
/// about the place instead of the blurb being a dead end.
struct POIExplainSheet: View {
    let poi: POIPlace

    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(\.dismiss) private var dismiss

    @State private var result: ExplainResult?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var chatHistory: [POIChatTurn] = []
    @State private var chatInput = ""
    @State private var chatSending = false
    @State private var lookAroundScene: MKLookAroundScene?
    /// Drives Apple's own native Place Card content (hours, ratings) via
    /// `mapItemDetailSelectionAccessory` on a single-marker `Map`, embedded
    /// directly in this scroll content and pre-selected so it renders
    /// immediately. `mapItemDetailSheet`/`Popover` show a richer version of
    /// this (photos, reviews) but always as a second, separate modal
    /// stacked on top of this one — the user explicitly wants one page, not
    /// two, so this in-content accessory (plus the plain phone/website/
    /// address rows below) is the trade-off: everything on this page, at
    /// the cost of the photo/review section only a truly separate surface
    /// can render (confirmed via research — no plain data API exists for
    /// any of this).
    @State private var placeCardSelection: MapSelection<MKMapItem>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(poi.name).font(.title3.bold())
                                    if !poi.categoryLabel.isEmpty {
                                        Text(poi.categoryLabel).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if let identifier = poi.mapItem.identifier?.rawValue {
                                    HStack(spacing: 14) {
                                        Button {
                                            Haptics.medium()
                                            savedPlacesStore.toggleFavorite(poi)
                                        } label: {
                                            Image(systemName: savedPlacesStore.isFavorite(identifier) ? "heart.fill" : "heart")
                                                .foregroundStyle(savedPlacesStore.isFavorite(identifier) ? Theme.gold : .secondary)
                                        }
                                        Button {
                                            Haptics.light()
                                            savedPlacesStore.togglePlan(poi)
                                        } label: {
                                            Image(systemName: savedPlacesStore.isInPlan(identifier) ? "checkmark.circle.fill" : "plus.circle")
                                                .foregroundStyle(savedPlacesStore.isInPlan(identifier) ? Theme.gold : .secondary)
                                        }
                                    }
                                    .font(.title3)
                                }
                            }

                            // Apple's own native Place Card (hours, rating),
                            // embedded right in this scroll content — not a
                            // separate sheet on top of this one.
                            // `interactionModes: []` stops pan/zoom/rotate
                            // from fighting the outer ScrollView while
                            // leaving the card's own buttons tappable.
                            Map(interactionModes: [], selection: $placeCardSelection) {
                                Marker(item: poi.mapItem)
                                    .tag(MapSelection(poi.mapItem))
                                    .mapItemDetailSelectionAccessory(.callout(.full))
                            }
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .task { placeCardSelection = MapSelection(poi.mapItem) }

                            // Phone/website/address are plain `MKMapItem`
                            // properties (unlike hours/ratings) — shown
                            // directly so this page always has them even if
                            // the embedded card above doesn't surface them.
                            placeDetailsRows

                            Button("common.openInMaps") {
                                poi.mapItem.openInMaps()
                            }
                            .buttonStyle(.bordered)

                            // Apple's own street-level imagery — silently
                            // omitted where Look Around has no coverage
                            // (common outside a handful of countries) rather
                            // than showing an empty/broken placeholder.
                            if let lookAroundScene {
                                LookAroundCard(scene: lookAroundScene, height: 180)
                            }

                            if loading {
                                VStack(alignment: .leading, spacing: 8) {
                                    SkeletonBox().frame(width: 180, height: 14)
                                    SkeletonBox().frame(height: 12)
                                    SkeletonBox().frame(width: 220, height: 12)
                                }
                            } else if let result {
                                Text(result.headline).font(.subheadline.bold()).foregroundStyle(Theme.gold)
                                Text(result.body).font(.footnote)
                                ForEach(result.highlights, id: \.self) { highlight in
                                    HStack(alignment: .top, spacing: 6) {
                                        Circle().fill(Theme.gold).frame(width: 5, height: 5).padding(.top, 6)
                                        Text(highlight).font(.caption)
                                    }
                                }
                            } else if let errorMessage {
                                Text(errorMessage).font(.footnote).foregroundStyle(Theme.closedRed)
                            }

                            if !chatHistory.isEmpty {
                                Divider().padding(.vertical, 4)
                                ForEach(chatHistory) { turn in chatBubble(turn) }
                            }

                            if chatSending {
                                HStack {
                                    ProgressView().tint(Theme.gold)
                                    Spacer()
                                }
                                .id("chat-sending")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: chatHistory.count) { _, _ in
                        guard let last = chatHistory.last else { return }
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }

                Divider()
                chatInputBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
        .task { await explain() }
        .task { await loadLookAroundScene() }
    }

    @ViewBuilder
    private var placeDetailsRows: some View {
        let phoneNumber = poi.mapItem.phoneNumber
        let website = poi.mapItem.url
        let address = poi.mapItem.placemark.title

        if phoneNumber != nil || website != nil || address != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let phoneNumber, let telURL = URL(string: "tel:\(phoneNumber.filter { !$0.isWhitespace })") {
                    Link(phoneNumber, destination: telURL)
                }
                if let website {
                    Link(website.host ?? website.absoluteString, destination: website)
                }
                if let address {
                    Text(address).foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        }
    }

    private func loadLookAroundScene() async {
        let request = MKLookAroundSceneRequest(coordinate: poi.coordinate)
        lookAroundScene = try? await request.scene
    }

    private func chatBubble(_ turn: POIChatTurn) -> some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 40) }
            Text(turn.content)
                .font(.footnote)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(turn.role == .user ? Theme.gold.opacity(0.15) : Color(.secondarySystemBackground))
                )
            if turn.role == .assistant { Spacer(minLength: 40) }
        }
        .id(turn.id)
    }

    private var chatInputBar: some View {
        HStack(spacing: 8) {
            TextField(String(localized: "poiChat.inputPlaceholder"), text: $chatInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await sendChat() } }
            Button {
                Task { await sendChat() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
                    .foregroundStyle(Theme.gold)
            }
            .disabled(chatInput.trimmingCharacters(in: .whitespaces).isEmpty || chatSending)
        }
        .padding(12)
    }

    private func personalizationProfile() -> PersonalizationProfile {
        let profile = userProfileStore.profile
        return PersonalizationProfile(
            name: profile.name,
            profession: profile.profession?.rawValue,
            interests: profile.interests.map(\.rawValue),
            faith: profile.faith?.rawValue,
            budget: profile.budget?.rawValue,
            groupType: profile.groupType?.rawValue,
            pace: profile.pace?.rawValue
        )
    }

    private func explain() async {
        loading = true
        defer { loading = false }

        let request = ExplainPOIRequest(
            name: poi.name,
            category: poi.categoryLabel.isEmpty ? nil : poi.categoryLabel,
            lat: poi.coordinate.latitude,
            lng: poi.coordinate.longitude,
            address: poi.mapItem.placemark.title,
            locale: Locale.current.language.languageCode?.identifier,
            userProfile: personalizationProfile(),
            recentlyViewedPlaceIds: nil
        )

        do {
            result = try await PlacesAPI.explainPOI(request)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendChat() async {
        let message = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        chatInput = ""

        let historyForRequest = chatHistory
        chatHistory.append(POIChatTurn(role: .user, content: message))
        chatSending = true
        defer { chatSending = false }

        let request = POIChatRequest(
            name: poi.name,
            category: poi.categoryLabel.isEmpty ? nil : poi.categoryLabel,
            address: poi.mapItem.placemark.title,
            locale: Locale.current.language.languageCode?.identifier,
            userProfile: personalizationProfile(),
            history: historyForRequest,
            message: message
        )

        do {
            let response = try await PlacesAPI.chatAboutPOI(request)
            chatHistory.append(POIChatTurn(role: .assistant, content: response.reply))
        } catch {
            chatHistory.append(POIChatTurn(role: .assistant, content: error.localizedDescription))
        }
    }
}
