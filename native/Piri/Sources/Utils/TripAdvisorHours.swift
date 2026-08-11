import Foundation

/// Tripadvisor's own `opening_hours.formatted` lines look like
/// "Mo,Tu,We,Th,Fr,Sa,Su 11:00-16:00" — comma-separated English two-letter
/// day codes grouping the days that share a time range, never localized.
/// Confirmed live: shown verbatim, this reads as broken English in a
/// Turkish-language card. Reformats each line into the current locale's
/// day names, collapsing a full 7-day match into "every day" instead of
/// listing all seven.
enum TripAdvisorHours {
    /// Index matches `Calendar.shortWeekdaySymbols`, which is Sunday-first.
    private static let dayCodeOrder = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    static func humanize(_ raw: String) -> String {
        let parts = raw.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return raw }
        let dayCodes = parts[0].split(separator: ",").map(String.init)
        let timeRange = String(parts[1])

        let indices = dayCodes.compactMap { dayCodeOrder.firstIndex(of: $0) }
        // Falls back to the raw, unlocalized line rather than guessing --
        // any code Tripadvisor sends that isn't one of the seven expected
        // ones means this isn't the format assumed above.
        guard indices.count == dayCodes.count, !indices.isEmpty else { return raw }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        let symbols = calendar.shortWeekdaySymbols

        if indices.count == 7 {
            return "\(String(localized: "tripadvisor.everyDay")) \(timeRange)"
        }

        let localizedDays = indices.map { symbols[$0] }.joined(separator: ", ")
        return "\(localizedDays) \(timeRange)"
    }
}
