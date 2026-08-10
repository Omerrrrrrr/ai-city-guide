import SwiftUI

/// Port of `mobile/app/city-picker.tsx`. Apple POI data needs no per-city
/// "discovery" the way the curated database did, so picking any search
/// result just sets the active city immediately — no more
/// ready/discovering/queued/failed status, no discovery push-token
/// registration. `/cities/discover` stays intact server-side, just unused.
struct CityPickerScreen: View {
    @Environment(CityStore.self) private var cityStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [CityResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let cityName = cityStore.cityName {
                        currentCitySection(cityName)
                    }

                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(Theme.closedRed)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.closedRed.opacity(0.08)))
                    }

                    if !isLoading, !results.isEmpty {
                        resultsSection
                    }

                    if !isLoading, errorMessage == nil, !query.trimmingCharacters(in: .whitespaces).isEmpty, results.isEmpty {
                        VStack(spacing: 8) {
                            Text(L("cityPicker.noResults", query)).font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
                            Text("cityPicker.noResultsSub").font(.system(size: 14)).foregroundStyle(.secondary.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    }

                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        VStack(spacing: 10) {
                            Text("cityPicker.hintTitle").font(.system(size: 17, weight: .bold)).foregroundStyle(.secondary)
                            Text("cityPicker.hintBody").font(.system(size: 14)).foregroundStyle(.secondary.opacity(0.7)).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    }
                }
                .padding(16)
            }
            // Without this, ScrollView's default `.interactively` keyboard
            // dismissal mode treats the first tap on a result row (while the
            // search field is still focused) as the start of a dismiss-drag
            // and swallows it — the row's Button never fires, so picking a
            // city while the keyboard is still up silently does nothing.
            .scrollDismissesKeyboard(.immediately)
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                Button("common.cancel") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("cityPicker.title").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 56)
            }
            .padding(.horizontal, 20)

            TextField(String(localized: "cityPicker.searchPlaceholder"), text: $query)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.12)))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Theme.navy)
        .onChange(of: query) { _, newValue in
            scheduleSearch(newValue)
        }
    }

    private func currentCitySection(_ cityName: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("cityPicker.currentlyExploring").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            HStack(spacing: 10) {
                Circle().fill(Theme.gold).frame(width: 8, height: 8)
                Text(cityName).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button {
                    cityStore.clearCity()
                    dismiss()
                } label: {
                    Text("common.showAll")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))
                }
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.15)))
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("cityPicker.results").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            ForEach(Array(results.enumerated()), id: \.offset) { _, city in
                Button {
                    select(city)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(city.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                            if let country = city.country {
                                Text(country).font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("›").font(.system(size: 20)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    // Same fix as `ProfileScreen.cityCard` — the
                    // `Spacer()`-filled middle of the row isn't part of any
                    // subview's rendered bounds, so it's otherwise a dead
                    // tap zone.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.15)))
    }

    // Nominatim's usage policy prohibits autocomplete/type-ahead search — wait
    // for a mostly-typed name (debounced) before firing a geocode request.
    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        errorMessage = nil

        guard text.trimmingCharacters(in: .whitespaces).count >= 3 else {
            results = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            isLoading = true
            do {
                let cities = try await CitiesAPI.search(text)
                guard !Task.isCancelled else { return }
                results = cities
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = String(localized: "cityPicker.searchFailed")
            }
            isLoading = false
        }
    }

    private func select(_ city: CityResult) {
        // No curated-DB "known city" concept left — every geocoded result is
        // immediately usable with Apple POI data. Fall back to a coordinate-
        // derived id when the backend didn't have one on file.
        let id = city.id ?? "\(city.name.lowercased().replacingOccurrences(of: " ", with: "-"))-\(city.centerLat)-\(city.centerLng)"
        cityStore.setCity(id: id, name: city.name, lat: city.centerLat, lng: city.centerLng)
        dismiss()
    }
}
