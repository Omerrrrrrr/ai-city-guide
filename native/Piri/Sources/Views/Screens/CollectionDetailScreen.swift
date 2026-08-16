import MapKit
import SwiftUI

/// A user-named group of saved places (`SavedCollection`) — rename, remove
/// places, delete the whole list. Presented as a `.sheet` from `SavedScreen`,
/// same pattern as `TripDetailScreen`: a custom header row instead of a
/// `NavigationStack`, since there's no ambient navigation bar to hide here.
///
/// Only `.plan`-kind collections with 2+ places get the AI-optimize/
/// create-route buttons — `.saved`-kind lists are just for keeping places.
/// `.task(id:)` key for the weather/hours fetch — changes on either the
/// target date or the place list (identifiers + count, so both a reorder-
/// free add/remove and any other membership change trigger a refetch).
private struct WeatherHoursFetchKey: Hashable {
    let targetDate: Double?
    let placeIdentifiers: [String]

    init(collection: SavedCollection) {
        targetDate = collection.targetDate
        placeIdentifiers = collection.places.map(\.identifier)
    }
}

struct CollectionDetailScreen: View {
    let collectionId: String

    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(TabSelection.self) private var tabSelection
    @Environment(CityStore.self) private var cityStore
    @Environment(\.dismiss) private var dismiss

    @State private var isEditingName = false
    @State private var nameInput = ""
    @State private var showDeleteConfirm = false
    @State private var selectedPOI: POIPlace?
    @State private var resolvingIdentifier: String?
    @State private var showingDatePicker = false
    @State private var pickerDate = Date()
    @State private var forecast: Weather?
    @State private var forecastFailed = false
    @State private var hoursResults: [String: HoursCheckResult] = [:]
    @State private var hoursFailed = false
    @State private var searchQuery = ""
    @State private var searchResults: [POIPlace] = []
    @State private var isSearchingPlaces = false
    @State private var searchFailed = false
    @State private var searchTask: Task<Void, Never>?
    @State private var showingSearchCityPicker = false
    /// Overrides `cityStore` as the search anchor for this screen only —
    /// added because the search was silently limited to the globally
    /// active city (found live: searching "Sulamaniye" while Oslo was
    /// active only matched a mosque named after it *in* Oslo, not the
    /// actual place the user meant elsewhere). Never touches the app-wide
    /// active city.
    @State private var searchAnchorCityName: String?
    @State private var searchAnchorCoordinate: CLLocationCoordinate2D?

    private var collection: SavedCollection? {
        savedPlacesStore.collections.first { $0.id == collectionId }
    }

    private func targetDate(for collection: SavedCollection) -> Date? {
        collection.targetDate.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// Only the free-tier forecast horizon actually has real data —
    /// further out, `/weather/forecast` would just return whatever slot
    /// happens to be closest, which is misleading rather than useful.
    private func isWithinForecastWindow(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: date)
        ).day ?? -1
        return days >= 0 && days <= 5
    }

    /// Anchors weather/hours lookups on the plan's own places rather than
    /// whatever city happens to be active right now — correct even if the
    /// user switches cities later, since a Plan is self-contained.
    private func centroid(for collection: SavedCollection) -> (lat: Double, lng: Double)? {
        guard !collection.places.isEmpty else { return nil }
        let count = Double(collection.places.count)
        let lat = collection.places.map(\.lat).reduce(0, +) / count
        let lng = collection.places.map(\.lng).reduce(0, +) / count
        return (lat, lng)
    }

    private func loadForecastIfNeeded(for collection: SavedCollection, date: Date) async {
        guard isWithinForecastWindow(date), let coordinate = centroid(for: collection) else {
            forecast = nil
            forecastFailed = false
            return
        }
        forecastFailed = false
        do {
            forecast = try await WeatherAPI.forecast(lat: coordinate.lat, lng: coordinate.lng, date: date)
        } catch {
            // Previously `try?` — a network failure was visually identical
            // to "no forecast for this date," with no way to tell the
            // difference or retry.
            forecast = nil
            forecastFailed = true
        }
    }

    private func loadHoursIfNeeded(for collection: SavedCollection, date: Date) async {
        guard !collection.places.isEmpty else {
            hoursResults = [:]
            hoursFailed = false
            return
        }
        hoursFailed = false
        // Matches /places/hours-check's own server-side cap.
        let places = collection.places.prefix(15).map { HoursCheckPlace(name: $0.name, lat: $0.lat, lng: $0.lng) }
        do {
            let response = try await PlanSchedulingAPI.checkHours(
                HoursCheckRequest(places: Array(places), date: ISO8601DateFormatter().string(from: date))
            )
            hoursResults = Dictionary(uniqueKeysWithValues: response.results.map { ($0.name, $0) })
        } catch {
            hoursResults = [:]
            hoursFailed = true
        }
    }

    var body: some View {
        Group {
            if let collection {
                content(collection)
            } else {
                VStack(spacing: 16) {
                    Text("saved.collections.notFound").foregroundStyle(.secondary)
                    Button("common.cancel") { dismiss() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private func content(_ collection: SavedCollection) -> some View {
        VStack(spacing: 0) {
            header(collection)
            ScrollView {
                VStack(spacing: 12) {
                    searchField

                    if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                        searchResultsSection(collection)
                    } else {
                        if collection.kind == .plan {
                            dateSection(collection)
                            weatherBanner(collection)
                            hoursFailedBanner(collection)
                            if collection.places.count >= 2 {
                                optimizeButton(collection)
                                createRouteButton(collection)
                            }
                        }

                        if collection.places.isEmpty {
                            emptyState
                        } else {
                            referencesList(collection)
                        }
                    }
                }
                .padding(16)
            }
        }
        .sheet(item: $selectedPOI) { poi in POIExplainSheet(poi: poi) }
        .sheet(isPresented: $showingDatePicker) { datePickerSheet(collection) }
        .onAppear { nameInput = collection.name }
        // Was keyed on `targetDate` alone -- adding/removing places via the
        // inline search didn't change the id, so the weather centroid and
        // hours-check silently went stale after an edit until the date was
        // re-picked. Folding the place list into the id (SwiftUI only
        // restarts a `.task(id:)` when the id actually changes) makes an
        // edit refetch too.
        .task(id: WeatherHoursFetchKey(collection: collection)) {
            guard let date = targetDate(for: collection) else {
                forecast = nil
                forecastFailed = false
                hoursResults = [:]
                hoursFailed = false
                return
            }
            async let weatherTask: Void = loadForecastIfNeeded(for: collection, date: date)
            async let hoursTask: Void = loadHoursIfNeeded(for: collection, date: date)
            _ = await (weatherTask, hoursTask)
        }
        .onChange(of: searchQuery) { _, newValue in scheduleSearch(newValue) }
    }

    private var searchField: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "collection.searchPlaceholder"), text: $searchQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchTask?.cancel()
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

            // A place search anchored on the wrong city just returns
            // nothing useful — surfaced directly (not buried in a
            // separate settings screen) since it's exactly what explains
            // an empty/unexpected result to the person searching.
            Button {
                showingSearchCityPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 12))
                    Text(L("collection.searchLocation", searchAnchorCityName ?? cityStore.cityName ?? String(localized: "common.everywhere")))
                        .font(.system(size: 12, weight: .medium))
                    Text("common.change").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.gold)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingSearchCityPicker) {
            CityPickerScreen { city in
                searchAnchorCityName = city.name
                searchAnchorCoordinate = CLLocationCoordinate2D(latitude: city.centerLat, longitude: city.centerLng)
                if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    scheduleSearch(searchQuery)
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultsSection(_ collection: SavedCollection) -> some View {
        if isSearchingPlaces && searchResults.isEmpty {
            VStack(spacing: 8) {
                SkeletonBox().frame(height: 60)
                SkeletonBox().frame(height: 60)
            }
        } else if searchFailed {
            // Previously indistinguishable from "no results for this query"
            // — both fell into the same empty-results text — since
            // `POISearchService.search` swallowed every error into `[]`.
            HStack(spacing: 8) {
                Text("collection.searchFailed").font(.system(size: 14)).foregroundStyle(.secondary)
                Spacer()
                Button("common.retry") { scheduleSearch(searchQuery) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.top, 8)
        } else if searchResults.isEmpty {
            Text("collection.searchNoResults").font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, 8)
        } else {
            ForEach(searchResults) { poi in
                searchResultRow(poi, collection: collection)
            }
        }
    }

    private func searchResultRow(_ poi: POIPlace, collection: SavedCollection) -> some View {
        let added = collection.places.contains { $0.identifier == poi.asReference.identifier }
        return HStack(spacing: 12) {
            Button {
                selectedPOI = poi
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: POICategoryGroups.icon(for: poi.category))
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(POICategoryGroups.gradient(for: poi.category)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(poi.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        if !poi.categoryLabel.isEmpty {
                            Text(poi.categoryLabel).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.light()
                savedPlacesStore.toggle(poi, inCollection: collection.id)
            } label: {
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(added ? Theme.gold : .secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(added ? Theme.gold.opacity(0.08) : Color(.secondarySystemBackground)))
    }

    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchFailed = false
            return
        }
        let activeCityCoordinate: CLLocationCoordinate2D? = cityStore.lat.flatMap { lat in
            cityStore.lng.map { lng in CLLocationCoordinate2D(latitude: lat, longitude: lng) }
        }
        guard let coordinate = searchAnchorCoordinate ?? activeCityCoordinate else { return }
        isSearchingPlaces = true
        searchFailed = false
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            // `searchThrowing`, not the silent-degrade `search(...)` every
            // other caller uses — this screen specifically wants to tell
            // "the network failed" apart from "genuinely no results."
            do {
                searchResults = try await POISearchService.searchThrowing(near: coordinate, categories: nil, naturalLanguageQuery: trimmed)
            } catch {
                guard !Task.isCancelled else { return }
                searchResults = []
                searchFailed = true
            }
            guard !Task.isCancelled else { return }
            isSearchingPlaces = false
        }
    }

    @ViewBuilder
    private func dateSection(_ collection: SavedCollection) -> some View {
        Button {
            pickerDate = targetDate(for: collection) ?? Date()
            showingDatePicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar").font(.system(size: 18)).foregroundStyle(Theme.gold)
                if let date = targetDate(for: collection) {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                } else {
                    Text("collection.pickDate").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("common.change").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func weatherBanner(_ collection: SavedCollection) -> some View {
        if let forecast {
            HStack(spacing: 10) {
                Image(systemName: forecast.condition.icon).font(.system(size: 20)).foregroundStyle(Theme.gold)
                Text(L("collection.forecast", String(Int(forecast.temp)), forecast.description))
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.gold.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.25)))
        } else if forecastFailed, let date = targetDate(for: collection) {
            // Was previously indistinguishable from "no forecast available
            // for this date" (both rendered nothing at all) — a real
            // network failure now says so and offers a retry.
            HStack(spacing: 8) {
                Text("collection.forecastFailed").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("common.retry") {
                    Task { await loadForecastIfNeeded(for: collection, date: date) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        }
    }

    @ViewBuilder
    private func hoursFailedBanner(_ collection: SavedCollection) -> some View {
        if hoursFailed, let date = targetDate(for: collection) {
            HStack(spacing: 8) {
                Text("collection.hoursFailed").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("common.retry") {
                    Task { await loadHoursIfNeeded(for: collection, date: date) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        }
    }

    private func datePickerSheet(_ collection: SavedCollection) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Time, not just date -- was displayedComponents: .date only,
                // so the persisted targetDate silently carried whatever
                // time-of-day pickerDate happened to default to (roughly
                // "now," from whenever the sheet was first opened) instead
                // of a deliberately chosen one. Confirmed live: the
                // "Açık olacak" badge downstream is computed against that
                // exact timestamp via /places/hours-check, so an accidental
                // time made its open/closed prediction meaningless.
                DatePicker("collection.dateLabel", selection: $pickerDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
                // A single reference instant, not a start/end range — the
                // whole list's hours are checked against just this one
                // moment (see /places/hours-check), so this makes explicit
                // what "one time for a multi-stop plan" actually means.
                Text("collection.dateSubtitle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if collection.targetDate != nil {
                    Button(role: .destructive) {
                        savedPlacesStore.setTargetDate(collection.id, date: nil)
                        showingDatePicker = false
                    } label: {
                        Text("collection.removeDate")
                    }
                }
                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle(String(localized: "collection.dateLabel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { showingDatePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        savedPlacesStore.setTargetDate(collection.id, date: pickerDate.timeIntervalSince1970 * 1000)
                        showingDatePicker = false
                    }
                }
            }
        }
    }

    private func optimizeButton(_ collection: SavedCollection) -> some View {
        Button {
            let placeNames = collection.places.map(\.name).joined(separator: ", ")
            tabSelection.pendingAIQuery = L("saved.optimize.query", placeNames)
            tabSelection.selection = 3
            // Presented as a `.sheet` (from SavedScreen, itself a `.sheet`
            // from ProfileScreen) — switching `tabSelection.selection` alone
            // changes the tab underneath, invisibly, while these sheets
            // keep covering the whole screen. Dismissing is what actually
            // makes the tab switch to Ask Piri visible.
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text("◈").font(.system(size: 26)).foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 3) {
                    Text("saved.optimize.title").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    Text(LPlural("saved.optimize.sub", count: collection.places.count)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.navy))
        }
        .buttonStyle(.plain)
    }

    private func createRouteButton(_ collection: SavedCollection) -> some View {
        Button {
            // `/routes/directions` caps at 10 coordinates server-side —
            // matched here so a large list doesn't get silently rejected.
            tabSelection.pendingRouteStops = Array(collection.places.prefix(10))
            tabSelection.selection = 2
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.gold)
                Text("saved.createRoute.title")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.gold.opacity(0.3), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func header(_ collection: SavedCollection) -> some View {
        HStack {
            Button("common.cancel") { dismiss() }
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            if isEditingName {
                TextField(collection.name, text: $nameInput)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .onSubmit { commitRename(collection) }
                    // Swiping the sheet away instead of pressing Return
                    // used to lose the typed name with no warning — commit
                    // it on disappear too.
                    .onDisappear {
                        guard isEditingName else { return }
                        commitRename(collection)
                    }
            } else {
                Button {
                    nameInput = collection.name
                    isEditingName = true
                } label: {
                    HStack(spacing: 6) {
                        Text(collection.name).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                        Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            Spacer()

            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash").foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .piriGlassSurface()
        .alert(String(localized: "collection.delete.title"), isPresented: $showDeleteConfirm) {
            Button(String(localized: "common.delete"), role: .destructive) {
                savedPlacesStore.deleteCollection(collection.id)
                dismiss()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text("collection.delete.message")
        }
    }

    private func commitRename(_ collection: SavedCollection) {
        let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            savedPlacesStore.renameCollection(collection.id, name: trimmed)
        }
        isEditingName = false
    }

    /// Native `List` + `.onMove` drag-handle reordering — was two tiny
    /// adjacent up/down chevrons plus a separate remove button, all crowded
    /// together with no explicit tap-target sizing (easy to mis-tap between
    /// "reorder" and "irreversibly remove"), and inconsistent with
    /// `MapScreen+RouteMode.swift`'s `routeModeSheet`, which already uses
    /// this same List/`.onMove` pattern for the same "reorder a list of
    /// stops" concept. A `List` sizes itself independently rather than
    /// flowing with its content, so it needs an explicit height to nest
    /// inside the outer `ScrollView` without fighting it for the scroll
    /// gesture — estimated generously per-row (icon + up to two lines of
    /// text + an optional hours badge, taller than `routeModeSheet`'s
    /// simpler row) and capped at 4 visible rows, same convention
    /// `routeModeSheet` uses, with the List scrolling internally beyond that.
    private func referencesList(_ collection: SavedCollection) -> some View {
        List {
            ForEach(collection.places) { reference in
                referenceRow(reference)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { offsets, destination in
                savedPlacesStore.moveInCollection(collectionId, fromOffsets: offsets, toOffset: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        .frame(height: min(CGFloat(collection.places.count), 4) * 82)
    }

    private func referenceRow(_ reference: SavedPOIReference) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await open(reference) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: POICategoryGroups.icon(for: reference.category))
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(POICategoryGroups.gradient(for: reference.category)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reference.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                        if let category = reference.category?.rawValue {
                            Text(category.replacingOccurrences(of: "MKPOICategory", with: ""))
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        if let willBeOpen = hoursResults[reference.name]?.willBeOpen {
                            Text(willBeOpen ? "collection.willBeOpen" : "collection.mayBeClosed")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(willBeOpen ? Theme.openGreen : Theme.closedRed)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill((willBeOpen ? Theme.openGreen : Theme.closedRed).opacity(0.12)))
                        }
                    }
                    Spacer()
                    if resolvingIdentifier == reference.identifier {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(resolvingIdentifier != nil)

            if resolvingIdentifier != reference.identifier {
                Button {
                    savedPlacesStore.removeFromCollection(collectionId, identifier: reference.identifier)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private func open(_ reference: SavedPOIReference) async {
        resolvingIdentifier = reference.identifier
        selectedPOI = await reference.resolve()
        resolvingIdentifier = nil
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("◈").font(.system(size: 48)).opacity(0.25)
            Text("saved.collections.emptyTitle").font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
            Text("saved.collections.emptyBody").font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}
