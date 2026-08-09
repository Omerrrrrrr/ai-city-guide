import Foundation

/// Port of `mobile/src/utils/place-hours.ts`. Same fixed `Europe/Oslo`
/// timezone convention as the backend/RN app — hours are relative to that
/// zone regardless of device locale.
enum PlaceHours {
    struct MinutesRange: Hashable {
        var start: Int
        var end: Int
    }

    enum State: String {
        case open, closed, allDay = "all-day", temporarilyClosed = "temporarily-closed", unknown
    }

    struct OpenStatus {
        var state: State
        var shortLabel: String
        var detail: String
        var note: String?
        var verified: Bool
    }

    struct WeeklyRow: Identifiable {
        var dayIndex: Int
        var label: String
        var hoursText: String
        var isToday: Bool
        var id: Int { dayIndex }
    }

    struct WeeklySchedule {
        var verified: Bool
        var note: String
        var rows: [WeeklyRow]
    }

    private enum Profile {
        case alwaysOpen(summaryKey: String)
        case scheduled(summaryKey: String, rangesByDay: [Int: [MinutesRange]])
    }

    private static let placeTimeZone = TimeZone(identifier: "Europe/Oslo")!
    private static let weeklyDayOrder: [(dayIndex: Int, labelKey: String)] = [
        (1, "placeHours.weekdayShort.mon"), (2, "placeHours.weekdayShort.tue"), (3, "placeHours.weekdayShort.wed"),
        (4, "placeHours.weekdayShort.thu"), (5, "placeHours.weekdayShort.fri"), (6, "placeHours.weekdayShort.sat"),
        (0, "placeHours.weekdayShort.sun"),
    ]
    private static let dayNameKeys = [
        "placeHours.day.sunday", "placeHours.day.monday", "placeHours.day.tuesday", "placeHours.day.wednesday",
        "placeHours.day.thursday", "placeHours.day.friday", "placeHours.day.saturday",
    ]

    private static func range(_ startHour: Int, _ endHour: Int) -> MinutesRange {
        MinutesRange(start: startHour * 60, end: endHour * 60)
    }

    private static func schedule(_ days: [Int], _ startHour: Int, _ endHour: Int) -> [Int: [MinutesRange]] {
        Dictionary(uniqueKeysWithValues: days.map { ($0, [range(startHour, endHour)]) })
    }

    private static let outdoorProfile = Profile.alwaysOpen(summaryKey: "placeHours.profile.outdoor")
    private static let landmarkDaytimeProfile = Profile.scheduled(
        summaryKey: "placeHours.profile.landmarkDaytime",
        rangesByDay: schedule([0, 1, 2, 3, 4, 5, 6], 9, 18)
    )
    private static let museumProfile = Profile.scheduled(
        summaryKey: "placeHours.profile.museum",
        rangesByDay: schedule([2, 3, 4, 5, 6], 11, 17).merging(schedule([0], 12, 16)) { a, _ in a }
    )
    private static let cultureProfile = Profile.scheduled(
        summaryKey: "placeHours.profile.culture",
        rangesByDay: schedule([1, 2, 3, 4, 5], 10, 17)
            .merging(schedule([6], 11, 17)) { a, _ in a }
            .merging(schedule([0], 12, 16)) { a, _ in a }
    )
    private static let cafeProfile = Profile.scheduled(
        summaryKey: "placeHours.profile.cafe",
        rangesByDay: schedule([1, 2, 3, 4, 5], 8, 18)
            .merging(schedule([6], 9, 18)) { a, _ in a }
            .merging(schedule([0], 10, 17)) { a, _ in a }
    )
    private static let restaurantProfile = Profile.scheduled(
        summaryKey: "placeHours.profile.restaurant",
        rangesByDay: schedule([1, 2, 3, 4], 12, 22)
            .merging(schedule([5, 6], 12, 23)) { a, _ in a }
            .merging(schedule([0], 13, 21)) { a, _ in a }
    )
    private static let shoppingProfile = Profile.scheduled(
        summaryKey: "placeHours.profile.shopping",
        rangesByDay: schedule([1, 2, 3, 4, 5], 10, 20).merging(schedule([6], 10, 18)) { a, _ in a }
    )

    private static func hoursProfile(for place: Place) -> Profile {
        switch place.category {
        case "walking-area", "beach", "viewpoint", "square-street":
            return outdoorProfile
        case "museum":
            return museumProfile
        case "cultural-spot":
            return cultureProfile
        case "cafe":
            return cafeProfile
        case "restaurant":
            return restaurantProfile
        case "shopping-area":
            return shoppingProfile
        case "landmark":
            return place.tags.contains("outdoor") ? outdoorProfile : landmarkDaytimeProfile
        default:
            return landmarkDaytimeProfile
        }
    }

    private static func nowParts(_ date: Date) -> (dayIndex: Int, minutes: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = placeTimeZone
        let weekday = calendar.component(.weekday, from: date) - 1 // Calendar: 1=Sunday -> 0-indexed
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return (weekday, hour * 60 + minute)
    }

    private static func formatMinutes(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private static func formatRangeList(_ ranges: [MinutesRange]) -> String {
        guard !ranges.isEmpty else { return String(localized: "placeHours.closed") }
        return ranges.map { "\(formatMinutes($0.start))-\(formatMinutes($0.end))" }.joined(separator: ", ")
    }

    private static func dayLabel(dayOffset: Int, dayIndex: Int) -> String {
        if dayOffset == 0 { return String(localized: "placeHours.day.today") }
        if dayOffset == 1 { return String(localized: "placeHours.day.tomorrow") }
        guard dayIndex >= 0, dayIndex < dayNameKeys.count else {
            return String(localized: "placeHours.day.another")
        }
        return String(localized: String.LocalizationValue(dayNameKeys[dayIndex]))
    }

    private static func nextOpening(_ rangesByDay: [Int: [MinutesRange]], dayIndex: Int, minutes: Int) -> (dayOffset: Int, dayIndex: Int, start: Int)? {
        for offset in 0..<7 {
            let targetDay = (dayIndex + offset) % 7
            let ranges = rangesByDay[targetDay] ?? []
            if let next = ranges.first(where: { offset > 0 || $0.start > minutes }) {
                return (offset, targetDay, next.start)
            }
        }
        return nil
    }

    static func openStatus(for place: Place, date: Date = Date()) -> OpenStatus {
        if place.visitInfo.temporarilyClosed {
            return OpenStatus(
                state: .temporarilyClosed,
                shortLabel: String(localized: "placeHours.status.temporarilyClosed"),
                detail: String(localized: "placeHours.detail.temporarilyClosed"),
                note: nil,
                verified: place.visitInfo.hoursVerified
            )
        }

        if place.visitInfo.hoursVerified, let openingHours = place.visitInfo.openingHours {
            return verifiedStatus(place: place, openingHours: openingHours, date: date)
        }

        let profile = hoursProfile(for: place)
        let (dayIndex, minutes) = nowParts(date)

        switch profile {
        case .alwaysOpen(let summaryKey):
            return OpenStatus(
                state: .allDay,
                shortLabel: String(localized: "placeHours.status.usuallyOpenAllDay"),
                detail: String(localized: String.LocalizationValue(summaryKey)),
                note: String(localized: "placeHours.note.publicOutdoor"),
                verified: false
            )
        case .scheduled(let summaryKey, let rangesByDay):
            let summary = String(localized: String.LocalizationValue(summaryKey))
            let todayRanges = rangesByDay[dayIndex] ?? []
            if let active = todayRanges.first(where: { minutes >= $0.start && minutes < $0.end }) {
                return OpenStatus(
                    state: .open,
                    shortLabel: String(localized: "placeHours.status.likelyOpenNow"),
                    detail: L("placeHours.detail.likelyOpenUntil", summary, formatMinutes(active.end)),
                    note: String(localized: "placeHours.note.estimatedNotVerified"),
                    verified: false
                )
            }
            let next = nextOpening(rangesByDay, dayIndex: dayIndex, minutes: minutes)
            let nextText = next.map { L("placeHours.detail.likelyOpensAt", dayLabel(dayOffset: $0.dayOffset, dayIndex: $0.dayIndex), formatMinutes($0.start)) }
                ?? String(localized: "placeHours.detail.unclear")
            return OpenStatus(
                state: .closed,
                shortLabel: String(localized: "placeHours.status.likelyClosedNow"),
                detail: L("placeHours.detail.likelyClosedWithNext", summary, nextText),
                note: String(localized: "placeHours.note.estimatedNotVerified"),
                verified: false
            )
        }
    }

    private static func verifiedStatus(place: Place, openingHours: OpeningHoursData, date: Date) -> OpenStatus {
        if openingHours.mode == .alwaysOpen {
            return OpenStatus(
                state: .allDay,
                shortLabel: String(localized: "placeHours.status.openAllDay"),
                detail: String(localized: "placeHours.detail.verifiedAllDay"),
                note: String(localized: "placeHours.note.verifiedFromSource"),
                verified: true
            )
        }

        let (dayIndex, minutes) = nowParts(date)
        let todayRanges = (openingHours.days[String(dayIndex)] ?? []).map { MinutesRange(start: toMinutes($0.start), end: toMinutes($0.end)) }

        if let active = todayRanges.first(where: { minutes >= $0.start && minutes < $0.end }) {
            return OpenStatus(
                state: .open,
                shortLabel: String(localized: "placeHours.status.openNow"),
                detail: L("placeHours.detail.verifiedOpenUntil", formatMinutes(active.end)),
                note: String(localized: "placeHours.note.verifiedFromSource"),
                verified: true
            )
        }

        let rangesByDay = Dictionary(uniqueKeysWithValues: (0..<7).map { day -> (Int, [MinutesRange]) in
            (day, (openingHours.days[String(day)] ?? []).map { MinutesRange(start: toMinutes($0.start), end: toMinutes($0.end)) })
        })
        let next = nextOpening(rangesByDay, dayIndex: dayIndex, minutes: minutes)
        let nextText = next.map { L("placeHours.detail.opensAt", dayLabel(dayOffset: $0.dayOffset, dayIndex: $0.dayIndex), formatMinutes($0.start)) }
            ?? String(localized: "placeHours.detail.unclear")

        return OpenStatus(
            state: .closed,
            shortLabel: String(localized: "placeHours.status.closedNow"),
            detail: L("placeHours.detail.verifiedClosedWithNext", nextText),
            note: String(localized: "placeHours.note.verifiedFromSource"),
            verified: true
        )
    }

    private static func toMinutes(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    static func weeklySchedule(for place: Place, date: Date = Date()) -> WeeklySchedule {
        let (dayIndex, _) = nowParts(date)

        if place.visitInfo.hoursVerified, let openingHours = place.visitInfo.openingHours {
            let rows = weeklyDayOrder.map { entry -> WeeklyRow in
                let text: String
                if openingHours.mode == .alwaysOpen {
                    text = String(localized: "placeHours.allDay")
                } else {
                    let ranges = (openingHours.days[String(entry.dayIndex)] ?? []).map { MinutesRange(start: toMinutes($0.start), end: toMinutes($0.end)) }
                    text = formatRangeList(ranges)
                }
                return WeeklyRow(dayIndex: entry.dayIndex, label: String(localized: String.LocalizationValue(entry.labelKey)), hoursText: text, isToday: entry.dayIndex == dayIndex)
            }
            return WeeklySchedule(verified: true, note: String(localized: "placeHours.weeklyNote.verifiedFromSource"), rows: rows)
        }

        let profile = hoursProfile(for: place)
        let rows = weeklyDayOrder.map { entry -> WeeklyRow in
            let text: String
            switch profile {
            case .alwaysOpen:
                text = String(localized: "placeHours.allDay")
            case .scheduled(_, let rangesByDay):
                text = formatRangeList(rangesByDay[entry.dayIndex] ?? [])
            }
            return WeeklyRow(dayIndex: entry.dayIndex, label: String(localized: String.LocalizationValue(entry.labelKey)), hoursText: text, isToday: entry.dayIndex == dayIndex)
        }
        return WeeklySchedule(verified: false, note: String(localized: "placeHours.weeklyNote.estimatedNotVerified"), rows: rows)
    }

    static func isOpen(_ status: OpenStatus) -> Bool {
        status.state == .open || status.state == .allDay
    }
}
