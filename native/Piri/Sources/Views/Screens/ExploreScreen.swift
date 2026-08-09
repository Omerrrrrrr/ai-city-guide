import SwiftUI

/// Port of `mobile/app/(tabs)/explore.tsx`.
struct ExploreScreen: View {
    @Environment(PlacesQuery.self) private var placesQuery
    @Environment(CityStore.self) private var cityStore

    @State private var query: String
    @State private var category: String
    @State private var tag: String
    @State private var openNowOnly: Bool

    init(initialQuery: String = "", initialCategory: String? = "all", initialTag: String? = "all", initialOpenNow: Bool = false) {
        _query = State(initialValue: initialQuery)
        _category = State(initialValue: initialCategory ?? "all")
        _tag = State(initialValue: initialTag ?? "all")
        _openNowOnly = State(initialValue: initialOpenNow)
    }

    private var filters: PlaceFilters.QueryFilters {
        PlaceFilters.QueryFilters(query: query, category: category, tag: tag, openNow: openNowOnly)
    }

    private var hasFilters: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || category != "all" || tag != "all" || openNowOnly
    }

    private var curatedTags: [String] { PlaceFilters.curatedTags(in: placesQuery.places) }
    private var filteredPlaces: [Place] { PlaceFilters.sortedForBrowse(PlaceFilters.filter(placesQuery.places, with: filters)) }
    private var featured: [Place] { Array(PlaceFilters.sortedForBrowse(placesQuery.places).filter(PlaceFilters.isHighQuality).prefix(6)) }
    private var openNowList: [Place] { Array(placesQuery.places.filter { PlaceHours.isOpen(PlaceHours.openStatus(for: $0)) }.prefix(8)) }
    private var rainyDay: [Place] { Array(placesQuery.places.filter { $0.tags.contains("rainy day") }.prefix(6)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                categoryChips
                tagChips

                if let error = placesQuery.errorMessage, !placesQuery.isLoading {
                    HStack {
                        Text(error).foregroundStyle(Theme.closedRed)
                        Button("common.retry") { Task { await placesQuery.refresh() } }
                    }
                    .padding(.horizontal, 20)
                }

                if placesQuery.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if !hasFilters {
                    browseSections
                } else {
                    filteredGrid
                }
            }
            .padding(.bottom, 40)
        }
        // See CityPickerScreen: without this, the default `.interactively`
        // keyboard dismissal swallows the first tap on a place card while
        // the search field is still focused, instead of firing it.
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await placesQuery.refresh() }
        .task {
            if placesQuery.places.isEmpty {
                await placesQuery.load(cityName: cityStore.cityName, lat: cityStore.lat, lng: cityStore.lng)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(cityStore.cityName ?? String(localized: "explore.placesFallback"))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if hasFilters {
                    Button("explore.reset") {
                        query = ""; category = "all"; tag = "all"; openNowOnly = false
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            TextField(text: $query) {
                Text("common.searchPlaces")
            }
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.12)))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Theme.navy)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CategoryFilters.all, id: \.id) { filter in
                    let active = category == filter.id
                    Button {
                        category = filter.id
                    } label: {
                        Text((filter.emoji.map { "\($0) " } ?? "") + String(localized: String.LocalizationValue(filter.labelKey)))
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(active ? Theme.navy : Color(.secondarySystemBackground)))
                            .foregroundStyle(active ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    openNowOnly.toggle()
                } label: {
                    Text("explore.openNow")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(openNowOnly ? Theme.openGreen.opacity(0.1) : Color(.secondarySystemBackground)))
                        .foregroundStyle(openNowOnly ? Theme.openGreen : .primary)
                }
                ForEach(curatedTags, id: \.self) { curatedTag in
                    let active = tag == curatedTag
                    Button {
                        tag = active ? "all" : curatedTag
                    } label: {
                        Text(PlaceFilters.formatTag(curatedTag))
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(active ? Theme.navy : Color(.secondarySystemBackground)))
                            .foregroundStyle(active ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var browseSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let hero = featured.first {
                NavigationLink(destination: PlaceDetailScreen(placeId: hero.id)) {
                    ZStack(alignment: .bottomLeading) {
                        PlaceImageView(place: hero, cornerRadius: 20).frame(height: 220)
                        VStack(alignment: .leading, spacing: 4) {
                            StatusBadge(place: hero)
                            Text(hero.name).font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: .top))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }

            horizontalSection(title: String(localized: "explore.sections.openRightNow"), places: openNowList)
            horizontalSection(title: String(localized: "explore.sections.featuredPlaces"), places: Array(featured.dropFirst()))
            if !rainyDay.isEmpty {
                horizontalSection(title: String(localized: "explore.sections.rainyDayPicks"), places: rainyDay)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("explore.sections.allPlaces").font(.system(size: 20, weight: .heavy))
                placesGrid(filteredPlaces)
            }
            .padding(.horizontal, 16)
        }
    }

    private var filteredGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LPlural("explore.placesFound", count: filteredPlaces.count)).font(.system(size: 13)).foregroundStyle(.secondary)
            placesGrid(filteredPlaces)
            if filteredPlaces.isEmpty {
                Text("explore.emptyText").foregroundStyle(.secondary).padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 16)
    }

    private func horizontalSection(title: String, places: [Place]) -> some View {
        Group {
            if !places.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(size: 20, weight: .heavy)).padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(places) { place in
                                NavigationLink(destination: PlaceDetailScreen(placeId: place.id)) {
                                    FeaturedCardView(place: place)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func placesGrid(_ places: [Place]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(places) { place in
                NavigationLink(destination: PlaceDetailScreen(placeId: place.id)) {
                    VStack(alignment: .leading, spacing: 5) {
                        PlaceImageView(place: place, cornerRadius: 0).frame(height: 130)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name).font(.system(size: 15, weight: .bold)).lineLimit(2)
                            Text("\(Categories.emoji(for: place.category)) \(Categories.label(for: place.category))")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .padding(12)
                    }
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
