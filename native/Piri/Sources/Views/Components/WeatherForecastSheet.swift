import SwiftUI

/// Multi-day outlook behind the Home screen's weather badge tap — the badge
/// itself only ever showed current conditions with no way to see what the
/// next few days look like, and wasn't even tappable at all.
struct WeatherForecastSheet: View {
    let lat: Double
    let lng: Double
    let current: Weather

    @Environment(\.dismiss) private var dismiss
    @State private var daily: [DailyForecast] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    currentRow

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
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
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
            .navigationTitle(String(localized: "weather.forecast.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private var currentRow: some View {
        HStack(spacing: 12) {
            Image(systemName: current.condition.icon)
                .font(.system(size: 32))
                .foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(current.city).font(.headline)
                Text(current.description.capitalized).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(current.temp))°").font(.system(size: 34, weight: .bold))
        }
        .padding(16)
        .piriGlassCard(cornerRadius: 16)
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
            let response = try await WeatherAPI.daily(lat: lat, lng: lng)
            daily = response.daily
        } catch {
            errorMessage = String(localized: "weather.forecast.loadFailed")
        }
    }
}
