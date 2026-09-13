import MapKit
import SwiftUI

/// Shared editorial POI detail for the full modal and expanded map card.
/// Owns its data and actions; the map parent controls collapsed presentation.
/// Secondary content is disclosed without losing reviews, sources, or chat.
/// `onClose` dismisses the inline card; modal callers use the environment.
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
    /// Chat starts collapsed behind an "Ask about this place" row instead
    /// of always rendering at the bottom of the scroll — most opens of this
    /// card never lead to a follow-up question, so showing the input bar
    /// unconditionally cost every single POI tap a chunk of scroll length
    /// for a feature most people never touch.
    @State private var showingChat = false
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
        GeometryReader { viewport in
            detailBody(viewportWidth: viewport.size.width)
        }
    }

    private func detailAction(_ key: LocalizedStringKey, icon: String, accessory: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.body).foregroundStyle(Theme.gold).frame(width: 24)
            Text(key).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: accessory).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 52).contentShape(Rectangle())
    }

    private func detailBody(viewportWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
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
                        // the full explanation lands.
                        //
                        // Pulled out of the padded content below it (full-
                        // bleed, edge-to-edge) so this reads as a real photo
                        // header, matching every mockup this pass drew from,
                        // instead of just another inset element on the card.
                        let photosToShow = result?.photos ?? previewPhoto.map { [$0] } ?? []
                        POIPhotoGallery(photos: photosToShow) {
                            VStack(alignment: .leading, spacing: 12) {
                                detailHeader
                                collectionActions
                                Divider().overlay(Theme.border).padding(.vertical, 6)

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
                                    // "Why Piri recommends this" -- headline/body/
                                    // highlights exactly as before, just gathered
                                    // under an explicit label instead of running
                                    // straight into the badges/ratings/reviews
                                    // below with nothing marking where the AI's
                                    // own voice ends. Deliberately plain text, no
                                    // colored box -- a bordered callout here read
                                    // as louder than the content warranted.
                                    HStack(spacing: 9) {
                                        Image(systemName: "sparkles").foregroundStyle(Theme.gold)
                                        Text(String(localized: "design.detail.narration"))
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    .font(.system(size: 13, weight: .medium))
                                    Text(result.headline)
                                        .font(.system(size: 17, weight: .medium))
                                        .fixedSize(horizontal: false, vertical: true)
                                    DisclosureGroup {
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text(result.body).font(.system(size: 16)).lineSpacing(5)
                                            ForEach(result.highlights, id: \.self) { highlight in
                                                HStack(alignment: .top, spacing: 8) {
                                                    Circle().fill(Theme.gold).frame(width: 4, height: 4).padding(.top, 8)
                                                    Text(highlight).font(.subheadline).lineSpacing(3)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 10)
                                    } label: {
                                        Text(String(localized: "design.detail.fullStory"))
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    .accessibilityIdentifier("piri.detail.narration.disclosure")

                                    if weatherQuery.weather != nil || goldenHourBadgeWindow(result) != nil {
                                        HStack(spacing: 8) {
                                            if let weather = weatherQuery.weather {
                                                weatherBadge(weather)
                                            }
                                            if let window = goldenHourBadgeWindow(result) {
                                                goldenHourBadge(window)
                                            }
                                        }
                                    }

                                    Divider().overlay(Theme.border)
                                    DisclosureGroup {
                                        VStack(alignment: .leading, spacing: 14) {
                                            verifiedFactsRow(result)
                                            if let rating = result.rating {
                                                hoursRow(rating)
                                            }
                                            PlaceDetailsCard(mapItem: poi.mapItem)
                                            if let curatedInfo = result.curatedInfo {
                                                CuratedInfoRow(info: curatedInfo)
                                            }
                                            if let dietaryTags = result.dietaryTags {
                                                DietaryTagsRow(tags: dietaryTags)
                                            }

                                            VStack(spacing: 0) {
                                                Button { showingMapItemDetail = true } label: {
                                                    detailAction("poiExplain.fullDetails", icon: "info.circle", accessory: "chevron.right")
                                                }
                                                .accessibilityIdentifier("piri.detail.fullDetails")
                                                .mapItemDetailSheet(isPresented: $showingMapItemDetail, item: poi.mapItem)
                                                Divider().overlay(Theme.border).padding(.leading, 52)
                                                Button {
                                                    Haptics.light()
                                                    withAnimation(.easeInOut(duration: 0.2)) { showingDirections.toggle() }
                                                } label: {
                                                    detailAction("directions.preview.button", icon: "arrow.triangle.turn.up.right.circle", accessory: showingDirections ? "chevron.up" : "chevron.down")
                                                }
                                                .accessibilityIdentifier("piri.detail.routePreview")
                                                Divider().overlay(Theme.border).padding(.leading, 52)
                                                Button {
                                                    let opensInApp = PlaceDirections.opensInApp
                                                    PlaceDirections.openInMaps(name: poi.name, coordinate: poi.coordinate, tabSelection: tabSelection)
                                                    if opensInApp { close() }
                                                } label: {
                                                    detailAction("common.openInMaps", icon: "map", accessory: "arrow.up.right")
                                                }
                                                .accessibilityIdentifier("piri.detail.openMaps")
                                            }
                                            .buttonStyle(.plain)
                                            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16))
                                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))

                                            if showingDirections {
                                                DirectionsPreview(destination: poi.coordinate)
                                            }

                                            // Apple's own street-level imagery — silently
                                            // omitted where Look Around has no coverage
                                            // (common outside a handful of countries)
                                            // rather than showing an empty/broken
                                            // placeholder.
                                            if let lookAroundScene {
                                                LookAroundCard(scene: lookAroundScene, height: 180)
                                            }

                                        }.padding(.vertical, 12)
                                    } label: {
                                        Label(String(localized: "design.detail.location"), systemImage: "mappin.and.ellipse")
                                            .accessibilityIdentifier("piri.detail.info.disclosure")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white)
                                            .padding(.vertical, 10)
                                    }

                                    Divider().overlay(Theme.border)
                                    DisclosureGroup {
                                        VStack(alignment: .leading, spacing: 14) {
                                            if let rating = result.rating {
                                                TripAdvisorRatingRow(rating: rating, showHours: false)
                                                // Only offered when we already know
                                                // Tripadvisor has a matched location for
                                                // this place (i.e. `rating` resolved at
                                                // all) -- avoids a dead-end tap that
                                                // fetches reviews for a place with none.
                                                Button {
                                                    Haptics.light()
                                                    showingReviews = true
                                                } label: {
                                                    Label(
                                                        L("poiReviews.seeAll", rating.reviewCount), systemImage: "text.bubble"
                                                    )
                                                    .font(.footnote.weight(.semibold))
                                                }
                                            }
                                            PiriReviewsSection(
                                                poi: poi, tripAdvisorRating: result.rating, googleRating: result.googleRating,
                                                initialPiriRating: result.piriRating, reviewsSummary: result.reviewsSummary,
                                                aspectHighlights: result.aspectHighlights)

                                        }.padding(.vertical, 12)
                                    } label: {
                                        Label("poiExplain.reviewsSection", systemImage: "star.bubble")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white)
                                            .padding(.vertical, 10)
                                    }
                                    .accessibilityIdentifier("piri.detail.reviews.disclosure")

                                    // Chat starts collapsed -- see `showingChat`'s
                                    // own doc comment.
                                    Divider().padding(.vertical, 4)
                                    Button {
                                        Haptics.light()
                                        withAnimation { showingChat.toggle() }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Label("poiExplain.askAboutPlace", systemImage: "bubble.left.and.bubble.right")
                                            Spacer(minLength: 8)
                                            Image(systemName: showingChat ? "chevron.down" : "chevron.right")
                                                .font(.caption)
                                        }
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                    }
                                    // A real nearby university exists (Wikidata-
                                    // sourced) -- an honest invitation, not a
                                    // promise: asking might still come back empty
                                    // if that university never wrote about this
                                    // specific place (see `hasLocalAcademicSources`'s
                                    // own doc comment). Hidden once chat is open --
                                    // at that point they can just ask directly.
                                    if !showingChat, result.hasLocalAcademicSources {
                                        Text("poiExplain.localAcademicHint")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if showingChat {
                                        if !chatHistory.isEmpty {
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
                                                Spacer()
                                                Button("common.retry") { Task { await retryLastChat() } }
                                                    .buttonStyle(.bordered)
                                                    .controlSize(.small)
                                            }
                                            .font(.footnote)
                                            .foregroundStyle(Theme.closedRed)
                                            .padding(10)
                                            .background(
                                                Theme.closedRed.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)
                                            )
                                            .id("chat-error")
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
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 24)
                        } trailing: {
                            UserPhotoSection(poiName: poi.name, coordinate: poi.coordinate, photos: $userPhotos)
                        }
                    }
                    .frame(width: viewportWidth, alignment: .leading)
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

            // Gated behind `showingChat` too, not just the message bubbles
            // above -- confirmed live: leaving this always visible while
            // the "Ask about this place" row lived collapsed further up
            // put two separate invitations to chat on screen at once
            // (the collapsed row, easy to miss below the fold, *and* this
            // input bar sitting permanently docked at the bottom), which
            // reads as redundant rather than as one clear affordance.
            if showingChat {
                Divider()
                chatInputBar
            }
            directionsButton
        }
        .frame(width: viewportWidth)
        .background(Theme.navy)
        .foregroundStyle(.white)
        .tint(Theme.gold)
        .environment(\.colorScheme, .dark)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Theme.navy, in: Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("common.cancel"))
                .accessibilityIdentifier("piri.detail.close")
                Spacer()
                Button { addToCollectionKind = .saved } label: {
                    Image(systemName: savedPlacesStore.isSaved(poi.asReference.identifier) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 44, height: 44)
                        .background(Theme.navy, in: Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("placeDetail.actionBar.save"))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.navy)
        }
        .sheet(item: $addToCollectionKind) { kind in AddToCollectionSheet(poi: poi, kind: kind) }
        .sheet(isPresented: $showingReviews) {
            TripAdvisorReviewsSheet(poi: poi, totalReviewCount: result?.rating?.reviewCount)
        }
        .task { await explain() }
        .task { await loadPreviewPhoto() }
        .task { await loadLookAroundScene() }
        .task { await weatherQuery.load(lat: poi.coordinate.latitude, lng: poi.coordinate.longitude) }
        .task { await loadUserPhotos() }
    }

    private func localizedCategory(_ category: MKPointOfInterestCategory) -> String {
        if let group = POICategoryGroups.all.first(where: { $0.categories?.contains(category) == true }) {
            return String(localized: String.LocalizationValue(group.labelKey))
        }
        return String(localized: "design.detail.placeOfInterest")
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(poi.name)
                .font(Theme.editorial(size: 34))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let category = poi.category {
                Text(localizedCategory(category))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let badge = result?.unescoBadge { unescoBadgeView(badge) }
            if let heritage = result?.heritageDesignation { heritageDesignationBadgeView(heritage) }
        }
    }

    private var collectionActions: some View {
        let identifier = poi.asReference.identifier
        let saved = savedPlacesStore.isSaved(identifier)
        let planned = savedPlacesStore.isPlanned(identifier)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                collectionButton(.saved, active: saved)
                collectionButton(.plan, active: planned)
            }
            VStack(spacing: 10) {
                collectionButton(.saved, active: saved)
                collectionButton(.plan, active: planned)
            }
        }
        .padding(.top, 4)
    }

    private func collectionButton(_ kind: SavedCollectionKind, active: Bool) -> some View {
        let isSave = kind == .saved
        let key: LocalizedStringKey =
            isSave
            ? (active ? "placeDetail.actionBar.saved" : "placeDetail.actionBar.save")
            : (active ? "placeDetail.actionBar.inPlan" : "placeDetail.actionBar.addToPlan")
        return Button {
            Haptics.light()
            addToCollectionKind = kind
        } label: {
            Label(
                key,
                systemImage: isSave
                    ? (active ? "bookmark.fill" : "bookmark") : (active ? "checkmark.circle" : "plus.circle")
            )
            .font(.system(size: 14, weight: .medium))
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 12)
            .foregroundStyle(active ? Theme.gold : .white)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }

    private var directionsButton: some View {
        Button {
            Haptics.light()
            let opensInApp = PlaceDirections.opensInApp
            PlaceDirections.openInMaps(
                name: poi.name, coordinate: poi.coordinate, tabSelection: tabSelection)
            if opensInApp { close() }
        } label: {
            Label("placeDetail.actionBar.directions", systemImage: "location.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.navy)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.gold, in: RoundedRectangle(cornerRadius: 16))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("piri.detail.directions")
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.navy)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
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
            Text("\(weather.temp.localizedTemperatureRounded)°, \(weather.description.capitalized)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// A verified UNESCO designation (World Heritage Site / Global Geopark
    /// / Biosphere Reserve), server-matched by proximity — never guessed
    /// client-side, so this badge only ever appears for a real match (see
    /// apps/api/src/unesco.ts). Switched on the raw designation string the
    /// server sends rather than interpolating it into a localization key
    /// (`"unesco.\(designation)"` would silently render the raw key
    /// instead of translated text).
    private func unescoBadgeIcon(_ designation: String) -> String {
        switch designation {
        case "Global Geopark": return "mountain.2.fill"
        case "Biosphere Reserve": return "leaf.fill"
        default: return "building.columns.fill"
        }
    }

    private func unescoBadgeLabel(_ designation: String) -> String {
        switch designation {
        case "Global Geopark": return String(localized: "unesco.geopark")
        case "Biosphere Reserve": return String(localized: "unesco.biosphere")
        default: return String(localized: "unesco.worldHeritage")
        }
    }

    private func unescoBadgeView(_ badge: UnescoBadge) -> some View {
        HStack(spacing: 4) {
            Image(systemName: unescoBadgeIcon(badge.designation))
            Text(unescoBadgeLabel(badge.designation))
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemBlue).opacity(0.18), in: Capsule())
        .foregroundStyle(Color(.systemBlue))
    }

    /// `designation` is an open-ended, server-supplied real official term
    /// (e.g. "Grade II listed building", "monument historique inscrit") --
    /// unlike `UnescoBadge`'s fixed 3 designations, this isn't localized
    /// into a translated label, it's shown as the real term as-is (see
    /// heritage-designation.ts's own comment on the Wikidata source).
    private func heritageDesignationBadgeView(_ heritage: HeritageDesignation) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
            Text(heritage.designation)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.gold.opacity(0.18), in: Capsule())
        .foregroundStyle(Theme.gold)
    }

    private func goldenHourBadge(_ window: (start: Date, end: Date)) -> some View {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return HStack(spacing: 4) {
            Image(systemName: "sun.horizon.fill")
            Text(
                L(
                    "poiExplain.goldenHour", timeFormatter.string(from: window.start),
                    timeFormatter.string(from: window.end)))
        }
        .font(.caption)
        .foregroundStyle(Theme.gold)
    }

    /// Small caps section header used to group "Good to know"/"Reviews"/
    /// etc. — a plain label, not a card or colored box, matching the
    /// synthesis of both mockups' Place Detail structure (see the plan's
    /// "Divergences" section on why a box was deliberately rejected here).
    private func sectionLabel(_ key: String) -> some View {
        Text(String(localized: String.LocalizationValue(key)))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func goldenHourBadgeWindow(_ result: ExplainResult) -> (start: Date, end: Date)? {
        result.goldenHour?.activeWindow
    }

    /// Which real sources back this card, shown as a trust row rather than
    /// the single inline caption this replaced — `groundingSource` is
    /// mutually exclusive (Wikipedia or Tripadvisor, whichever grounded the
    /// AI explanation); Wikivoyage/Google/UNESCO are each independent of
    /// that and independent of each other, only present when that specific
    /// source actually had real data for this place. More sources here
    /// than before is deliberate — the point of this row is to make the
    /// full extent of real, verified grounding visible, not just the one
    /// primary source.
    private func verifiedSourceNames(_ result: ExplainResult) -> [String] {
        var names: [String] = []
        if let source = result.groundingSource {
            names.append(source == "wikipedia" ? "Wikipedia" : "Tripadvisor")
        }
        if result.wikivoyageUsed { names.append("Wikivoyage") }
        if result.unescoBadge != nil { names.append("UNESCO") }
        if result.googleRating != nil { names.append("Google") }
        return names
    }

    @ViewBuilder
    private func verifiedFactsRow(_ result: ExplainResult) -> some View {
        let sources = verifiedSourceNames(result)
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("poiExplain.verifiedFacts")
                HStack(spacing: 14) {
                    ForEach(sources, id: \.self) { SourceCaption(text: $0) }
                }
            }
        }
    }

    /// Hours pulled up into "Good to know" on their own — `MKMapItem` has
    /// no hours property at all, so Tripadvisor's `hoursFormatted` (only
    /// present once a Tripadvisor match resolved) is the only structured
    /// source for this. `TripAdvisorRatingRow` below (in the Reviews
    /// section) shows the bubble/score/open-now tag but not these lines,
    /// via its own `showHours: false` — avoids showing the same schedule
    /// twice on one card.
    @ViewBuilder
    private func hoursRow(_ rating: TripAdvisorRating) -> some View {
        if let hoursFormatted = rating.hoursFormatted, !hoursFormatted.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 18)
                    if let isOpenNow = rating.isOpenNow {
                        Text(isOpenNow ? "tripadvisor.openNow" : "tripadvisor.closedNow")
                            .font(.footnote.bold())
                            .foregroundStyle(isOpenNow ? Theme.openGreen : Theme.closedRed)
                    }
                }
                ForEach(hoursFormatted, id: \.self) { line in
                    Text(TripAdvisorHours.humanize(line))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                }
            }
        }
    }

    private func loadLookAroundScene() async {
        let request = MKLookAroundSceneRequest(coordinate: poi.coordinate)
        lookAroundScene = try? await request.scene
    }

    private func loadUserPhotos() async {
        guard let token = authStore.token else { return }
        userPhotos =
            (try? await PhotosAPI.fetchPhotos(
                name: poi.name, lat: poi.coordinate.latitude, lng: poi.coordinate.longitude, token: token))
            ?? []
    }

    /// See `previewPhoto`'s own doc comment for why `token` is deliberately
    /// omitted. A no-op once `result` has already landed (the fuller
    /// gallery from `explain()` wins regardless) -- this can finish after
    /// `explain()` on a slow cache miss, and `photosToShow` already prefers
    /// `result?.photos` first, so a late-arriving preview never overwrites it.
    private func loadPreviewPhoto() async {
        let request = PhotoBulkRequest(places: [
            PhotoBulkPlace(
                name: poi.name, lat: poi.coordinate.latitude, lng: poi.coordinate.longitude,
                category: poi.categoryLabel.isEmpty ? nil : poi.categoryLabel)
        ])
        guard let found = try? await PlacesAPI.photosBulk(request).results.first,
            let photoUrl = found.photoUrl
        else { return }
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
                        .fill(turn.role == .user ? Theme.gold.opacity(0.15) : Theme.cardFill)
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
        await performChatRequest(message: message, historyForRequest: historyForRequest)
    }

    /// `chatInput` is cleared optimistically before the send, so on failure
    /// the user has nothing left to retype -- unlike the `explain()` error
    /// right below this one in `body`, which already has a retry button.
    /// The failed user turn is still sitting in `chatHistory` (appended
    /// before the request, never rolled back on failure), so retrying just
    /// resends that same turn's content instead of re-appending a duplicate.
    private func retryLastChat() async {
        guard let lastTurn = chatHistory.last, lastTurn.role == .user else { return }
        let historyForRequest = Array(chatHistory.dropLast())
        await performChatRequest(message: lastTurn.content, historyForRequest: historyForRequest)
    }

    private func performChatRequest(message: String, historyForRequest: [POIChatTurn]) async {
        chatSending = true
        chatError = nil
        defer { chatSending = false }

        // Mirrors the backend's own `looksLikeTransitQuestion` -- only fetch
        // (and only prompt for, on a first ask) the user's location when the
        // message actually looks like it needs it, not on every message.
        let userLocation =
            Self.looksLikeTransitQuestion(message)
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
                cityName: cityStore.cityName,
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
            of:
                #"\bbus\b|\bferry\b|\btrain\b|\btram\b|transit|public transport|how (do|can) i get|get (there|here)|otob[üu]s|feribot|vapur|tren|tramvay|toplu ta[şs][ıi]ma|nas[ıi]l (giderim|ulaş[ıi]r[ıi]m|gidilir)|hvordan kommer jeg|buss\b|ferge|kollektiv"#,
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
                .background(Theme.screenBackground.ignoresSafeArea())
                .environment(\.colorScheme, .dark)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}
