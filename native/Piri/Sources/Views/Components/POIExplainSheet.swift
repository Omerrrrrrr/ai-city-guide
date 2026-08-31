import MapKit
import SwiftUI

/// The personalized AI blurb for one POI — everything: description, photos,
/// combined rating/reviews, plain contact details, hours access, directions
/// preview, Look Around, and a follow-up chat. Self-contained (owns all its
/// own state, fetches its own data via `.task`), so it renders identically
/// wherever it's embedded.
///
/// Two presentations exist because the two contexts genuinely differ: a
/// full-screen sheet (`POIExplainSheet`, below) for list-based screens with
/// no map to stay visible behind it, and an inline floating card
/// (`MapScreen.mapFeatureCard`) that keeps the map visible/pannable behind
/// it. They used to be two separately-maintained implementations that
/// silently drifted apart (reported live: "neden farklı sayfalar çıkıyor" —
/// the inline card was missing chat entirely, still had a since-removed
/// rating-popover icon) -- this type is the single shared content both now
/// embed, so a feature added to one is never accidentally missing from the
/// other again. `onClose` is `nil` for the sheet case (dismiss goes through
/// the NavigationStack's own toolbar Cancel button, the HIG-correct pattern
/// for a full-screen modal); non-nil for the inline-card case, which has no
/// nav bar of its own and needs an in-content close affordance instead.
struct POIExplainContent: View {
    let poi: POIPlace
    var onClose: (() -> Void)? = nil

    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @Environment(TripsStore.self) private var tripsStore
    @Environment(AuthStore.self) private var authStore
    @Environment(CityStore.self) private var cityStore
    @Environment(TabSelection.self) private var tabSelection
    @Environment(\.dismiss) private var dismiss

    @State private var result: ExplainResult?
    @State private var userPhotos: [UserSubmittedPhoto] = []
    /// Fast preview photo (see the `photosToShow` comment in `body`) --
    /// deliberately fetched with no bearer token (`PlacesAPI.photosBulk`'s
    /// `token` param left at its `nil` default) even when signed in, so
    /// this preview call never triggers the paid Google-photo upgrade
    /// `/places/explain-poi`'s own `result` fetch already does -- calling
    /// both with a token would silently double-charge one POI view against
    /// the same monthly `google_places` quota.
    @State private var previewPhoto: POIPhoto?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var chatHistory: [POIChatTurn] = []
    @State private var chatInput = ""
    @State private var chatSending = false
    /// Kept separate from `chatHistory` (not appended as a fake `.assistant`
    /// turn) for two reasons: it needs visibly distinct styling so a network
    /// error can't be mistaken for something Piri actually said, and
    /// `chatHistory` is sent back to the backend as conversation context on
    /// the next message — an error turn baked into that history would leak
    /// "The request timed out." into the AI's own context.
    @State private var chatError: String?
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var weatherQuery = WeatherQuery()
    @State private var addToCollectionKind: SavedCollectionKind?
    @State private var showingReviews = false
    @State private var showingDirections = false
    /// Drives Apple's own full Place Card via `mapItemDetailSheet` — the
    /// only place hours show up. `MKMapItem` has no `hours`/`openingHours`
    /// property at all (confirmed against the SDK header directly, not just
    /// docs) — `phoneNumber`/`url` are real plain values we can lay out as
    /// text ourselves, hours genuinely is not, in any form, on any OS
    /// version. Every embedded-map variant tried previously (full/compact
    /// callout, sync/async selection) either rendered blank or showed a
    /// plain name-only bubble with no hours inside it — this sheet is the
    /// only surface Apple actually renders that data on.
    @State private var showingMapItemDetail = false
    /// Only ever touched when a chat message looks like a transit question
    /// (see `sendChat()`) -- a plain `LocationManager()` instance, same
    /// per-view-owns-its-own convention every other screen that needs
    /// location already uses (no shared/injected instance anywhere in the
    /// app). Never started/prompted-for on a normal chat message.
    @State private var chatLocationManager = LocationManager()

    var body: some View {
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
                                if let onClose {
                                    Button {
                                        onClose()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .font(.title3)
                        }

                        // The real photo (Wikipedia/Tripadvisor, never
                        // AI-generated) is the most visually engaging thing
                        // this card has and, unlike the AI text/rating/
                        // badges below, is available from a fast,
                        // cache-first, keyless call (`/places/photos-bulk`)
                        // that doesn't need to wait for `/places/explain-poi`'s
                        // much heavier Promise.all + AI generation to finish
                        // server-side. Shown as soon as either arrives:
                        // `previewPhoto` (near-instant on a cache hit) first,
                        // then swapped for `result.photos`'s fuller gallery
                        // (possibly Google-upgraded for a paid account) once
                        // the full explanation lands. Reported live: "AI
                        // açıklaması, resimler, Tripadvisor vs aynı anda
                        // geliyor... hız sıralamasına göre üste koyulabilir."
                        let photosToShow = result?.photos ?? previewPhoto.map { [$0] } ?? []
                        if !photosToShow.isEmpty {
                            POIPhotoGallery(photos: photosToShow)
                        }
                        UserPhotoSection(poiName: poi.name, coordinate: poi.coordinate, photos: $userPhotos)

                        // AI explanation — the reason someone opens this
                        // sheet at all, but the slowest piece (grounding
                        // fetches + LLM generation, all server-side before
                        // this endpoint responds at all), so it stays
                        // skeleton-loading independently of the photo above.
                        if loading {
                            VStack(alignment: .leading, spacing: 8) {
                                SkeletonBox().frame(width: 180, height: 14)
                                SkeletonBox().frame(height: 12)
                                SkeletonBox().frame(width: 220, height: 12)
                            }
                        } else if let result {
                            Text(result.headline).font(.subheadline.bold()).foregroundStyle(Theme.gold)
                            HStack(spacing: 12) {
                                if let weather = weatherQuery.weather {
                                    weatherBadge(weather)
                                }
                                if let goldenHour = result.goldenHour, let window = goldenHourWindow(goldenHour) {
                                    goldenHourBadge(window)
                                }
                            }
                            if let rating = result.rating {
                                TripAdvisorRatingRow(rating: rating)
                                // Only offered when we already know
                                // Tripadvisor has a matched location for
                                // this place (i.e. `rating` resolved at
                                // all) -- avoids a dead-end tap that
                                // fetches reviews for a place with none.
                                Button {
                                    Haptics.light()
                                    showingReviews = true
                                } label: {
                                    Label(L("poiReviews.seeAll", rating.reviewCount), systemImage: "text.bubble")
                                        .font(.footnote.weight(.semibold))
                                }
                            }
                            PiriReviewsSection(poi: poi, tripAdvisorRating: result.rating, googleRating: result.googleRating, initialPiriRating: result.piriRating, reviewsSummary: result.reviewsSummary, aspectHighlights: result.aspectHighlights)
                            if let curatedInfo = result.curatedInfo {
                                CuratedInfoRow(info: curatedInfo)
                            }
                            if let dietaryTags = result.dietaryTags {
                                DietaryTagsRow(tags: dietaryTags)
                            }
                            Text(result.body).font(.footnote)
                            if let source = result.groundingSource {
                                // NOT `LocalizationValue("...\(source)")` -- that treats
                                // `source` as a substitution argument of the literal string
                                // "poiExplain.source.%@" rather than concatenating it into
                                // the lookup key, so the catalog lookup always misses and
                                // silently falls back to rendering the raw interpolated
                                // text (confirmed live: a real card showed literal
                                // "poiExplain.source.wikipedia" instead of the translated
                                // caption). Build the key as a plain `String` first, same
                                // fix `LPlural` already documents for the identical trap.
                                let key = "poiExplain.source." + source
                                SourceCaption(text: String(localized: String.LocalizationValue(key)))
                            }
                            ForEach(result.highlights, id: \.self) { highlight in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle().fill(Theme.gold).frame(width: 5, height: 5).padding(.top, 6)
                                    Text(highlight).font(.caption)
                                }
                            }
                        } else if let errorMessage {
                            HStack(spacing: 8) {
                                Text(errorMessage).font(.footnote).foregroundStyle(Theme.closedRed)
                                Spacer()
                                Button("common.retry") { Task { await explain() } }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }

                        // Phone/website/address — real plain values
                        // from Apple's own MapKit data.
                        PlaceDetailsCard(mapItem: poi.mapItem)

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
                                let opensInApp = PlaceDirections.opensInApp
                                PlaceDirections.openInMaps(name: poi.name, coordinate: poi.coordinate, tabSelection: tabSelection)
                                if opensInApp { close() }
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Haptics.light()
                                withAnimation(.easeInOut(duration: 0.2)) { showingDirections.toggle() }
                            } label: {
                                Label("directions.preview.button", systemImage: "arrow.triangle.turn.up.right.circle")
                            }
                            .buttonStyle(.bordered)
                        }

                        if showingDirections {
                            DirectionsPreview(destination: poi.coordinate)
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

                        if let chatError {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(chatError)
                            }
                            .font(.footnote)
                            .foregroundStyle(Theme.closedRed)
                            .padding(10)
                            .background(Theme.closedRed.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            .id("chat-error")
                        }
                    }
                    .padding()
                }
                .onChange(of: chatHistory.count) { _, _ in
                    guard let last = chatHistory.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: chatError) { _, newValue in
                    guard newValue != nil else { return }
                    withAnimation { proxy.scrollTo("chat-error", anchor: .bottom) }
                }
            }

            Divider()
            chatInputBar
        }
        .sheet(item: $addToCollectionKind) { kind in AddToCollectionSheet(poi: poi, kind: kind) }
        .sheet(isPresented: $showingReviews) { TripAdvisorReviewsSheet(poi: poi, totalReviewCount: result?.rating?.reviewCount) }
        .task { await explain() }
        .task { await loadPreviewPhoto() }
        .task { await loadLookAroundScene() }
        .task { await weatherQuery.load(lat: poi.coordinate.latitude, lng: poi.coordinate.longitude) }
        .task { await loadUserPhotos() }
    }

    /// `onClose` when embedded inline (no presentation context to dismiss),
    /// else the real sheet dismiss.
    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    /// Compact, not a card element — current conditions at this POI, one
    /// line, next to the rating row rather than a section of its own.
    private func weatherBadge(_ weather: Weather) -> some View {
        HStack(spacing: 4) {
            Image(systemName: weather.condition.icon)
            Text("\(Int(weather.temp))°, \(weather.description.capitalized)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Whichever golden-hour window (this morning's, already past, or this
    /// evening's, still ahead) hasn't happened yet today -- `nil` once both
    /// have passed, since showing a window that already closed isn't useful.
    private func goldenHourWindow(_ golden: GoldenHour) -> (start: Date, end: Date)? {
        let formatter = ISO8601DateFormatter()
        guard let sunrise = formatter.date(from: golden.sunrise),
              let sunset = formatter.date(from: golden.sunset),
              let morningEnd = formatter.date(from: golden.morningEndsAt),
              let eveningStart = formatter.date(from: golden.eveningStartsAt) else { return nil }
        let now = Date()
        if now < morningEnd { return (sunrise, morningEnd) }
        if now < sunset { return (eveningStart, sunset) }
        return nil
    }

    private func goldenHourBadge(_ window: (start: Date, end: Date)) -> some View {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return HStack(spacing: 4) {
            Image(systemName: "sun.horizon.fill")
            Text(L("poiExplain.goldenHour", timeFormatter.string(from: window.start), timeFormatter.string(from: window.end)))
        }
        .font(.caption)
        .foregroundStyle(Theme.gold)
    }

    private func loadLookAroundScene() async {
        let request = MKLookAroundSceneRequest(coordinate: poi.coordinate)
        lookAroundScene = try? await request.scene
    }

    private func loadUserPhotos() async {
        guard let token = authStore.token else { return }
        userPhotos = (try? await PhotosAPI.fetchPhotos(name: poi.name, lat: poi.coordinate.latitude, lng: poi.coordinate.longitude, token: token)) ?? []
    }

    /// See `previewPhoto`'s own doc comment for why `token` is deliberately
    /// omitted. A no-op once `result` has already landed (the fuller
    /// gallery from `explain()` wins regardless) -- this can finish after
    /// `explain()` on a slow cache miss, and `photosToShow` already prefers
    /// `result?.photos` first, so a late-arriving preview never overwrites it.
    private func loadPreviewPhoto() async {
        let request = PhotoBulkRequest(places: [
            PhotoBulkPlace(name: poi.name, lat: poi.coordinate.latitude, lng: poi.coordinate.longitude, category: poi.categoryLabel.isEmpty ? nil : poi.categoryLabel)
        ])
        guard let found = try? await PlacesAPI.photosBulk(request).results.first, let photoUrl = found.photoUrl else { return }
        previewPhoto = POIPhoto(
            url: photoUrl,
            source: found.source.flatMap(POIPhotoSource.init) ?? .unsplash,
            attributionUrl: found.attributionUrl,
            photographerName: found.photographerName,
            photographerUrl: found.photographerUrl
        )
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
            profession: profile.professionText,
            interests: profile.interestsText,
            faith: profile.faith?.rawValue,
            budget: profile.budget?.rawValue,
            groupType: profile.groupType?.rawValue,
            pace: profile.pace?.rawValue
        )
    }

    private func explain() async {
        loading = true
        errorMessage = nil
        defer { loading = false }

        let request = ExplainPOIRequest(
            name: poi.name,
            category: poi.categoryLabel.isEmpty ? nil : poi.categoryLabel,
            lat: poi.coordinate.latitude,
            lng: poi.coordinate.longitude,
            address: poi.mapItem.placemark.title,
            website: poi.mapItem.url?.absoluteString,
            locale: Locale.current.language.languageCode?.identifier,
            userProfile: personalizationProfile(),
            recentlyViewed: recentlyViewedStore.asPersonalizationSummaries,
            savedPlaces: savedPlacesStore.asPersonalizationSummaries,
            pastTrips: tripsStore.asPersonalizationSummaries
        )

        do {
            result = try await PlacesAPI.explainPOI(request, token: authStore.token)
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
        chatError = nil
        defer { chatSending = false }

        // Mirrors the backend's own `looksLikeTransitQuestion` -- only fetch
        // (and only prompt for, on a first ask) the user's location when the
        // message actually looks like it needs it, not on every message.
        let userLocation = Self.looksLikeTransitQuestion(message)
            ? await chatLocationManager.currentLocationOnce()
            : nil

        let request = POIChatRequest(
            name: poi.name,
            category: poi.categoryLabel.isEmpty ? nil : poi.categoryLabel,
            address: poi.mapItem.placemark.title,
            website: poi.mapItem.url?.absoluteString,
            lat: poi.coordinate.latitude,
            lng: poi.coordinate.longitude,
            userLat: userLocation?.latitude,
            userLng: userLocation?.longitude,
            locale: Locale.current.language.languageCode?.identifier,
            userProfile: personalizationProfile(),
            cityContext: CityContextSummary(
                countryInfo: cityStore.countryInfo,
                timezone: cityStore.timezones.first,
                exchangeRates: cityStore.exchangeRates
            ),
            history: historyForRequest,
            message: message
        )

        do {
            let response = try await PlacesAPI.chatAboutPOI(request)
            chatHistory.append(POIChatTurn(role: .assistant, content: response.reply))
        } catch {
            chatError = error.localizedDescription
        }
    }

    /// Mirrors the backend's own `looksLikeTransitQuestion` regex exactly
    /// (index.ts, `/places/explain-poi/chat`) -- kept in sync by hand since
    /// there's no shared source between a Swift client and a Node backend.
    private static func looksLikeTransitQuestion(_ message: String) -> Bool {
        message.range(
            of: #"\bbus\b|\bferry\b|\btrain\b|\btram\b|transit|public transport|how (do|can) i get|get (there|here)|otob[üu]s|feribot|vapur|tren|tramvay|toplu ta[şs][ıi]ma|nas[ıi]l (giderim|ulaş[ıi]r[ıi]m|gidilir)|hvordan kommer jeg|buss\b|ferge|kollektiv"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

/// Full-screen sheet presentation — used by list-based screens (Home) that
/// browse Apple POIs without a map view to tap into. See
/// `POIExplainContent`'s own doc comment for why this is now a thin wrapper.
struct POIExplainSheet: View {
    let poi: POIPlace

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            POIExplainContent(poi: poi)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel") { dismiss() }
                    }
                }
        }
    }
}
