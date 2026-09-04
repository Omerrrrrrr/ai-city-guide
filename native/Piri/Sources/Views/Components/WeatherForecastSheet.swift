import SwiftUI

/// Multi-day outlook behind the Home screen's weather badge tap — swipeable
/// pages (current location first, then any cities the user added via the
/// "+" button, backed by `WeatherCitiesStore`) rather than a single fixed
/// location, since a traveler planning ahead wants tomorrow's weather
/// somewhere they aren't yet, not just where they're standing right now.
struct WeatherForecastSheet: View {
    let lat: Double
    let lng: Double
    let current: Weather

    @Environment(\.dismiss) private var dismiss
    @Environment(WeatherCitiesStore.self) private var citiesStore

    private enum Page: Hashable {
        case current
        case saved(String)
    }

    @State private var selection: Page = .current
    @State private var showingAddCity = false

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                WeatherForecastPageView(cityName: current.city, lat: lat, lng: lng, prefetchedCurrent: current)
                    .tag(Page.current)
                ForEach(citiesStore.cities) { city in
                    WeatherForecastPageView(cityName: city.name, lat: city.lat, lng: city.lng, prefetchedCurrent: nil)
                        .tag(Page.saved(city.id))
                }
            }
            .tabViewStyle(.page)
            .navigationTitle(pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .saved(let id) = selection, let city = citiesStore.cities.first(where: { $0.id == id }) {
                        Button(role: .destructive) {
                            citiesStore.remove(city)
                            selection = .current
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        showingAddCity = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingAddCity) {
            CityPickerScreen { city in
                let saved = SavedWeatherCity(
                    id: city.id ?? "\(city.name.lowercased())-\(city.centerLat)-\(city.centerLng)",
                    name: city.name,
                    lat: city.centerLat,
                    lng: city.centerLng
                )
                citiesStore.add(saved)
                selection = .saved(saved.id)
            }
        }
        .background(Theme.screenBackground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var pageTitle: String {
        switch selection {
        case .current:
            return current.city
        case .saved(let id):
            return citiesStore.cities.first(where: { $0.id == id })?.name ?? String(localized: "weather.forecast.title")
        }
    }
}

/// One page's worth of content: current conditions + the multi-day outlook.
/// `prefetchedCurrent` is the "current location" page's already-fetched
/// `Weather` (avoids a redundant network call); every saved-city page fetches
/// its own.
private struct WeatherForecastPageView: View {
    let cityName: String
    let lat: Double
    let lng: Double
    let prefetchedCurrent: Weather?

    @State private var current: Weather?
    @State private var daily: [DailyForecast] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let current {
                    currentRow(current)
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if let errorMessage {
                    HStack(spacing: 8) {
                        Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("common.retry") { Task { await load() } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardFill))
                } else {
                    VStack(spacing: 0) {
                        ForEach(daily) { day in
                            dailyRow(day)
                            if day.id != daily.last?.id {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                    .piriGlassCard(cornerRadius: 16)
                }
            }
            .padding(16)
        }
        .task { await load() }
    }

    private func currentRow(_ current: Weather) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: current.condition.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cityName).font(.headline)
                    Text(current.description.capitalized).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(current.temp))°").font(.system(size: 34, weight: .bold))
            }
            if let airQuality = current.airQuality {
                airQualityRow(airQuality)
            }
        }
        .padding(16)
        .piriGlassCard(cornerRadius: 16)
    }

    private func airQualityRow(_ airQuality: AirQuality) -> some View {
        HStack(spacing: 6) {
            Circle().fill(airQuality.level.color).frame(width: 8, height: 8)
            Text(String(localized: String.LocalizationValue(airQuality.level.labelKey)))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private func dailyRow(_ day: DailyForecast) -> some View {
        HStack(spacing: 12) {
            Text(weekdayLabel(day.date))
                .font(.subheadline.weight(.semibold))
                .frame(width: 56, alignment: .leading)
            Image(systemName: day.condition.icon)
                .foregroundStyle(Theme.gold)
                .frame(width: 24)
            Text(day.description.capitalized)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("\(Int(day.tempMax))°").font(.subheadline.weight(.semibold))
            Text("\(Int(day.tempMin))°").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func weekdayLabel(_ isoDate: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        if Calendar.current.isDateInToday(date) {
            return String(localized: "common.today")
        }
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE")
        return weekdayFormatter.string(from: date)
    }

    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            if let prefetchedCurrent {
                current = prefetchedCurrent
            } else {
                var fetched = try await WeatherAPI.fetch(lat: lat, lng: lng)
                fetched.city = cityName
                current = fetched
            }
            let response = try await WeatherAPI.daily(lat: lat, lng: lng)
            daily = response.daily
        } catch {
            errorMessage = String(localized: "weather.forecast.loadFailed")
        }
    }
}
