import CoreLocation
import SwiftUI

/// Port of `mobile/app/place/[id].tsx`.
struct PlaceDetailScreen: View {
    let placeId: String

    // Dormant screen — no longer reachable from anywhere in the app now that
    // Explore/Saved/Trips resolve through Apple POI data (`POIExplainSheet`)
    // instead. Kept compiling rather than deleted (see `useCuratedMapData`
    // precedent). `SavedPlacesStore`/`RecentlyViewedStore` now only accept
    // `POIPlace`, not curated `Place`, so favorite/plan/recently-viewed
    // integration below is stubbed out rather than wired to them.
    @Environment(PlacesQuery.self) private var placesQuery
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(TabSelection.self) private var tabSelection
    @Environment(\.dismiss) private var dismiss

    @State private var place: Place?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var explainResult: ExplainResult?
    @State private var explainLoading = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let place {
                content(for: place)
            } else {
                errorView
            }
        }
        .task(id: placeId) {
            await load()
        }
        .navigationBarHidden(true)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await PlacesAPI.fetchPlace(id: placeId)
            place = fetched
            await loadExplain(for: fetched)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadExplain(for place: Place) async {
        explainLoading = true
        defer { explainLoading = false }
        let profile = userProfileStore.profile
        let request = ExplainRequest(
            placeId: place.id,
            userProfile: PersonalizationProfile(
                name: profile.name,
                profession: profile.professionText,
                interests: profile.interestsText,
                faith: profile.faith?.rawValue,
                budget: profile.budget?.rawValue,
                groupType: profile.groupType?.rawValue,
                pace: profile.pace?.rawValue
            ),
            locale: Locale.current.language.languageCode?.identifier,
            recentlyViewedPlaceIds: nil
        )
        explainResult = try? await PlacesAPI.explain(request)
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Text("placeDetail.errorTitle").font(.system(size: 20, weight: .bold))
            if let errorMessage {
                Text(errorMessage).font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("common.tryAgain") { Task { await load() } }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for place: Place) -> some View {
        let status = PlaceHours.openStatus(for: place)
        let open = PlaceHours.isOpen(status)
        let saved = false
        let inPlan = false
        let verifiedGallery = (place.gallery ?? []).filter { $0.verified || $0.status == "applied" }
        let nearby = placesQuery.nearby(to: place, limit: 5)

        // A plain `.frame(maxWidth: .infinity)` only *caps* an incoming width
        // proposal — when a descendant (the hero `AsyncImage`, sized only by
        // `.frame(height:)`) reports an oversized concrete ideal width during
        // an unconstrained measurement pass, "infinity" has nothing to clip
        // and the oversized value propagates straight up through ZStack ->
        // VStack -> ScrollView regardless. Reading the real width via
        // GeometryReader and forcing it explicitly is the only way to
        // guarantee the content never exceeds the screen.
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroImage(place, status: status, open: open, saved: saved, inPlan: inPlan)
                    actionBar(place, saved: saved, inPlan: inPlan)

                    if explainLoading || explainResult != nil {
                        pirisTakeCard
                    }

                    aboutCard(place)

                    if !place.tags.isEmpty {
                        tagsRow(place)
                    }

                    hoursCard(place, status: status)

                    if place.localVibe.mood != nil || place.localVibe.bestFor != nil {
                        vibeCard(place)
                    }

                    if verifiedGallery.count > 1 {
                        galleryRow(verifiedGallery)
                    }

                    locationCard(place)

                    if !nearby.isEmpty {
                        nearbyRow(nearby)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
                .frame(width: proxy.size.width, alignment: .leading)
            }
        }
    }

    private func heroImage(_ place: Place, status: PlaceHours.OpenStatus, open: Bool, saved: Bool, inPlan: Bool) -> some View {
        ZStack(alignment: .bottom) {
            PlaceImageView(place: place).frame(height: 340).clipped()

            HStack {
                iconButton(systemName: "chevron.left") { dismiss() }
                Spacer()
                iconButton(systemName: saved ? "heart.fill" : "heart", active: saved) {}
                iconButton(systemName: inPlan ? "checkmark.circle.fill" : "plus.circle", active: inPlan) {}
            }
            .padding(.horizontal, 16)
            .padding(.top, 50)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 4) {
                Text(status.shortLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(open ? Color(red: 0.43, green: 0.98, blue: 0.69) : Color(red: 1, green: 0.65, blue: 0.63))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill((open ? Color.green : Color.red).opacity(0.25)))
                Text(place.name).font(.system(size: 28, weight: .heavy)).foregroundStyle(.white)
                (Text(Image(systemName: Categories.icon(for: place.category))) + Text(" \(Categories.label(for: place.category))" + (place.verifiedFacts.address.map { " · \($0)" } ?? "")))
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .bottom, endPoint: .top))
        }
    }

    private func iconButton(systemName: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 40, height: 40)
                .background(Circle().fill(active ? Theme.gold : .black.opacity(0.4)))
                .foregroundStyle(active ? Theme.navy : .white)
        }
    }

    private func actionBar(_ place: Place, saved: Bool, inPlan: Bool) -> some View {
        HStack(spacing: 0) {
            actionBarButton(icon: saved ? "heart.fill" : "heart", label: saved ? "placeDetail.actionBar.saved" : "placeDetail.actionBar.save") {}
            Divider().frame(height: 32)
            actionBarButton(icon: inPlan ? "checkmark" : "list.bullet.clipboard", label: inPlan ? "placeDetail.actionBar.inPlan" : "placeDetail.actionBar.addToPlan") {}
            Divider().frame(height: 32)
            actionBarButton(icon: "arrow.up.right", label: "placeDetail.actionBar.directions", disabled: !PlaceDirections.canOpenInMaps(place)) {
                let opensInApp = PlaceDirections.opensInApp
                PlaceDirections.openInMaps(place, tabSelection: tabSelection)
                if opensInApp { dismiss() }
            }
            Divider().frame(height: 32)
            ShareLink(item: shareText(for: place)) {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 20))
                    Text("common.share").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .shadow(radius: 8, y: 4)
        .offset(y: -20)
        .padding(.bottom, -20)
    }

    private func shareText(for place: Place) -> String {
        var text = "\(place.name) — \(Categories.label(for: place.category)), \(place.city)\n\(place.shortStory.isEmpty ? place.description : place.shortStory)"
        if let wikiURL = place.wiki?.pageUrl {
            text += "\n\(wikiURL)"
        }
        return text
    }

    private func actionBarButton(icon: String, label: LocalizedStringKey, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    private var pirisTakeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("◈").foregroundStyle(Theme.gold)
                Text("placeDetail.pirisTake").font(.system(size: 14, weight: .bold)).tracking(0.5).foregroundStyle(.white)
            }
            if explainLoading {
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonBox().frame(width: 200, height: 16)
                    SkeletonBox().frame(height: 13)
                    SkeletonBox().frame(width: 260, height: 13)
                }
            } else if let explainResult {
                Text(explainResult.headline).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.gold)
                Text(explainResult.body).font(.system(size: 15)).foregroundStyle(.white.opacity(0.85))
                ForEach(explainResult.highlights, id: \.self) { highlight in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Theme.gold).frame(width: 6, height: 6).padding(.top, 7)
                        Text(highlight).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.navy))
    }

    private func aboutCard(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("placeDetail.about").font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            Text(place.description).font(.system(size: 16))
            if !place.shortStory.isEmpty, place.shortStory != place.description {
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(Theme.gold).frame(width: 3)
                    Text(place.shortStory).font(.system(size: 15)).italic().opacity(0.85)
                }
                .padding(.top, 12)
            }
            if let summary = place.wiki?.summary {
                Text(summary).font(.system(size: 14)).opacity(0.75).padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func tagsRow(_ place: Place) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(place.tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.navy.opacity(0.07)))
            }
        }
    }

    private func hoursCard(_ place: Place, status: PlaceHours.OpenStatus) -> some View {
        let schedule = PlaceHours.weeklySchedule(for: place)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("placeDetail.hours").font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Text(schedule.verified ? String(localized: "placeDetail.verified") : String(localized: "placeDetail.estimated"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(schedule.verified ? Theme.openGreen : .secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill((schedule.verified ? Theme.openGreen : .gray).opacity(0.08)))
            }
            Text(status.detail).font(.system(size: 15, weight: .semibold))
            if let note = status.note {
                Text(note).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            if place.visitInfo.temporarilyClosed {
                Text("placeDetail.temporarilyClosed").foregroundStyle(Theme.closedRed).font(.system(size: 14, weight: .semibold))
            }
            VStack(spacing: 4) {
                ForEach(schedule.rows) { row in
                    HStack {
                        Text(row.label).font(.system(size: 14, weight: row.isToday ? .bold : .regular)).opacity(row.isToday ? 1 : 0.7)
                        Spacer()
                        Text(row.hoursText).font(.system(size: 14, weight: row.isToday ? .bold : .regular)).opacity(row.isToday ? 1 : 0.85)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(row.isToday ? Theme.navy.opacity(0.06) : .clear))
                }
            }
            if let duration = place.visitInfo.durationMinutes {
                Text(L("placeDetail.typicalVisit", String(duration))).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func vibeCard(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("placeDetail.vibe").font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            if let mood = place.localVibe.mood { Text(mood).font(.system(size: 16)) }
            if let bestFor = place.localVibe.bestFor {
                HStack {
                    Text("placeDetail.bestFor").font(.system(size: 13)).foregroundStyle(.secondary)
                    Text(bestFor).font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func galleryRow(_ photos: [PlaceGalleryImage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("placeDetail.photos").font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos) { photo in
                        CachedAsyncImage(url: URL(string: photo.imageUrl), maxPixelSize: 400) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color(.secondarySystemBackground) }
                            .frame(width: 140, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func locationCard(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("placeDetail.location").font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            if let address = place.verifiedFacts.address {
                Text(address).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            if let location = place.location {
                PlaceMiniMap(coordinate: .init(latitude: location.lat, longitude: location.lng), interactive: true)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            if PlaceDirections.canOpenInMaps(place) {
                Button {
                    let opensInApp = PlaceDirections.opensInApp
                    PlaceDirections.openInMaps(place, tabSelection: tabSelection)
                    if opensInApp { dismiss() }
                } label: {
                    Text("common.openInMaps")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.navy))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func nearbyRow(_ nearby: [PlaceWithDistance]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("placeDetail.nearby").font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(nearby) { entry in
                        NavigationLink(destination: PlaceDetailScreen(placeId: entry.place.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                PlaceImageView(place: entry.place, cornerRadius: 0).frame(width: 140, height: 90)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.place.name).font(.system(size: 13, weight: .bold)).lineLimit(2)
                                    Text(walkMinutesLabel(entry.distanceKm)).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                .padding(10)
                            }
                            .frame(width: 140)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func walkMinutesLabel(_ distanceKm: Double) -> String {
        let minutes = max(1, Int((distanceKm / 4.8 * 60).rounded()))
        return L("placeDetail.walkMin", String(minutes))
    }
}

/// Minimal wrapping HStack for tag chips — SwiftUI has no built-in flow layout pre-iOS 16 `Layout` protocol usage here.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // A `nil` proposal (asked for an unconstrained/ideal size, e.g. during
        // a ScrollView's content-size pass) must NOT resolve to `.infinity`
        // here — returning an infinite width poisons every ancestor's width
        // computation, since a `Layout.sizeThatFits` result is exactly the
        // ideal size SwiftUI treats as this view's content-driven request,
        // unlike `.frame(maxWidth: .infinity)` which is a flexible *upper
        // bound*, not a literal reported size. Fall back to the natural
        // single-row width (sum of subviews) so an unconstrained query still
        // returns a finite, real number.
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let naturalWidth = sizes.reduce(CGFloat(0)) { $0 + $1.width } + spacing * CGFloat(max(0, subviews.count - 1))
        let width = proposal.width ?? naturalWidth

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for size in sizes {
            if x + size.width > width, x > 0 {
                maxX = max(maxX, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        maxX = max(maxX, x - spacing)
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

