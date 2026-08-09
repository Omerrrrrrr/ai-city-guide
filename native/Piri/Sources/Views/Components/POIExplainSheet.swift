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
    /// Drives Apple's own full Place Card via `mapItemDetailSheet` — the
    /// only place hours show up. `MKMapItem` has no `hours`/`openingHours`
    /// property at all (confirmed against the SDK header directly, not just
    /// docs) — `phoneNumber`/`url` are real plain values we can lay out as
    /// text ourselves, hours genuinely is not, in any form, on any OS
    /// version. Every embedded-map variant tried this session (full/compact
    /// callout, sync/async selection) either rendered blank or showed a
    /// plain name-only bubble with no hours inside it — this sheet is the
    /// only surface Apple actually renders that data on.
    @State private var showingMapItemDetail = false
    @State private var addToCollectionKind: SavedCollectionKind?

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
                                // `poi.mapItem.identifier` is nil for some
                                // POIs (a known Apple gap, not a bug here) —
                                // `asReference.identifier` is never nil (it
                                // falls back to a synthetic id), so
                                // `isSaved`/`isPlanned` checks always work.
                                let identifier = poi.asReference.identifier
                                HStack(spacing: 14) {
                                    Button {
                                        Haptics.light()
                                        addToCollectionKind = .saved
                                    } label: {
                                        Image(systemName: savedPlacesStore.isSaved(identifier) ? "bookmark.fill" : "bookmark")
                                            .foregroundStyle(savedPlacesStore.isSaved(identifier) ? Theme.gold : .secondary)
                                    }
                                    Button {
                                        Haptics.light()
                                        addToCollectionKind = .plan
                                    } label: {
                                        // Not "flag" — that's MapScreen's
                                        // Route Mode toggle icon; kept
                                        // distinct so the two concepts don't
                                        // look like the same action there.
                                        Image(systemName: savedPlacesStore.isPlanned(identifier) ? "suitcase.fill" : "suitcase")
                                            .foregroundStyle(savedPlacesStore.isPlanned(identifier) ? Theme.gold : .secondary)
                                    }
                                }
                                .font(.title3)
                            }

                            // AI explanation first — the reason someone opens
                            // this sheet at all — before any of Apple's own
                            // place data further down.
                            if loading {
                                VStack(alignment: .leading, spacing: 8) {
                                    SkeletonBox().frame(width: 180, height: 14)
                                    SkeletonBox().frame(height: 12)
                                    SkeletonBox().frame(width: 220, height: 12)
                                }
                            } else if let result {
                                Text(result.headline).font(.subheadline.bold()).foregroundStyle(Theme.gold)
                                if let rating = result.rating {
                                    TripAdvisorRatingRow(rating: rating)
                                }
                                POIPhotoGallery(photos: result.photos)
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

                            // Phone/website/address — real plain values,
                            // laid out as text right here next to each
                            // other, same section as everything else on
                            // this page.
                            placeDetailsRows

                            // Hours has no plain-value form to put in the
                            // section above (see note on `showingMapItemDetail`)
                            // — this is the only way to see it at all.
                            HStack(spacing: 10) {
                                Button {
                                    showingMapItemDetail = true
                                } label: {
                                    Label("poiExplain.fullDetails", systemImage: "info.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.gold)
                                .mapItemDetailSheet(isPresented: $showingMapItemDetail, item: poi.mapItem)

                                Button("common.openInMaps") {
                                    poi.mapItem.openInMaps()
                                }
                                .buttonStyle(.bordered)
                            }

                            // Apple's own street-level imagery — silently
                            // omitted where Look Around has no coverage
                            // (common outside a handful of countries) rather
                            // than showing an empty/broken placeholder.
                            if let lookAroundScene {
                                LookAroundCard(scene: lookAroundScene, height: 180)
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
        .sheet(item: $addToCollectionKind) { kind in AddToCollectionSheet(poi: poi, kind: kind) }
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
