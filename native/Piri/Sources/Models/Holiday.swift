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

    var dateValue: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: date)
    }
}

struct HolidaysUpcomingResponse: Decodable {
    var countryCode: String?
    var holidays: [UpcomingHoliday]
}
