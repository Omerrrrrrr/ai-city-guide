import Foundation

/// Mirrors `apps/api/src/holidays.ts`'s `PublicHoliday` plus the optional
/// AI enrichment `/holidays/upcoming` layers on top (`summary`/`activities`,
/// `nil` when the AI provider isn't configured or generation failed —
/// the date/name themselves are still real either way).
struct UpcomingHoliday: Codable, Identifiable, Hashable {
    var date: String
    var name: String
    var localName: String
    var countryCode: String
    var summary: String?
    var activities: [String]?

    var id: String { "\(countryCode)-\(date)-\(name)" }

    // Parsed in the device's own time zone, not UTC -- every call site
    // (HomeScreen's "days until" countdown, HolidayDetailSheet's display,
    // CollectionDetailScreen's date match) consumes this via
    // `Calendar.current`, which is also local. Parsing as UTC midnight
    // instead used to shift this to the PREVIOUS calendar day for anyone
    // west of UTC (any negative offset, e.g. the whole US) once
    // `Calendar.current` re-extracted day components locally -- a holiday
    // on "2026-12-25" landed on Dec 24 19:00 local for a UTC-5 user, so
    // every downstream day-difference/display was off by one. Parsing in
    // the same time zone it's later read back in keeps both sides
    // consistent regardless of the device's actual offset.
    var dateValue: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: date)
    }
}

struct HolidaysUpcomingResponse: Decodable {
    var countryCode: String?
    var holidays: [UpcomingHoliday]
}
