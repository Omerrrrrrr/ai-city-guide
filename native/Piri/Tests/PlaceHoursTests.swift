import XCTest
@testable import Piri

/// Port of `mobile/src/utils/__tests__/place-hours.test.ts`. Same winter
/// (Oslo = UTC+1, no DST) fixed dates to avoid daylight-saving ambiguity —
/// 2026-01-05 is a Monday.
final class PlaceHoursTests: XCTestCase {
    private func utc(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private var monday1400: Date { utc("2026-01-05T13:00:00Z") } // 14:00 Oslo
    private var monday0800: Date { utc("2026-01-05T07:00:00Z") } // 08:00 Oslo
    private var monday2300: Date { utc("2026-01-05T22:00:00Z") } // 23:00 Oslo

    func testTemporarilyClosedOverridesEverything() {
        let place = makePlace(category: "restaurant", visitInfo: makeVisitInfo(hoursVerified: true, temporarilyClosed: true))
        let status = PlaceHours.openStatus(for: place, date: monday1400)
        XCTAssertEqual(status.state, .temporarilyClosed)
    }

    func testOutdoorCategoryIsAlwaysOpen() {
        let beach = makePlace(category: "beach")
        let status = PlaceHours.openStatus(for: beach, date: monday2300)
        XCTAssertEqual(status.state, .allDay)
        XCTAssertFalse(status.verified)
    }

    func testRestaurantOpenDuringScheduledWindow() {
        let restaurant = makePlace(category: "restaurant")
        let status = PlaceHours.openStatus(for: restaurant, date: monday1400)
        XCTAssertEqual(status.state, .open)
        XCTAssertFalse(status.verified)
    }

    func testRestaurantClosedBeforeOpeningHasNextOpeningHint() {
        let restaurant = makePlace(category: "restaurant")
        let status = PlaceHours.openStatus(for: restaurant, date: monday0800)
        XCTAssertEqual(status.state, .closed)
        XCTAssertFalse(status.detail.isEmpty)
    }

    func testRestaurantClosedAfterHoursSameDay() {
        let restaurant = makePlace(category: "restaurant")
        let status = PlaceHours.openStatus(for: restaurant, date: monday2300)
        XCTAssertEqual(status.state, .closed)
    }

    func testMuseumClosedOnMonday() {
        let museum = makePlace(category: "museum")
        let status = PlaceHours.openStatus(for: museum, date: monday1400)
        XCTAssertEqual(status.state, .closed)
    }

    func testOutdoorTaggedLandmarkAlwaysOpenUnlikePlainLandmark() {
        let outdoorLandmark = makePlace(category: "landmark", tags: ["outdoor"])
        let indoorLandmark = makePlace(category: "landmark", tags: [])

        XCTAssertEqual(PlaceHours.openStatus(for: outdoorLandmark, date: monday2300).state, .allDay)
        XCTAssertEqual(PlaceHours.openStatus(for: indoorLandmark, date: monday2300).state, .closed)
    }

    func testVerifiedAlwaysOpen() {
        let place = makePlace(category: "walking-area", visitInfo: makeVisitInfo(
            hoursVerified: true,
            openingHours: OpeningHoursData(timezone: "Europe/Oslo", mode: .alwaysOpen, days: [:])
        ))
        let status = PlaceHours.openStatus(for: place, date: monday1400)
        XCTAssertEqual(status.state, .allDay)
        XCTAssertTrue(status.verified)
    }

    func testVerifiedScheduledHoursOverrideCategoryProfileGuess() {
        // A "restaurant" whose verified hours say it's actually closed at
        // 14:00 — verified data must win over the RESTAURANT_PROFILE guess
        // (which would otherwise say open at this hour).
        let place = makePlace(category: "restaurant", visitInfo: makeVisitInfo(
            hoursVerified: true,
            openingHours: OpeningHoursData(timezone: "Europe/Oslo", mode: .scheduled, days: ["1": [OpeningHoursRange(start: "17:00", end: "23:00")]])
        ))

        let closedStatus = PlaceHours.openStatus(for: place, date: monday1400)
        XCTAssertEqual(closedStatus.state, .closed)
        XCTAssertTrue(closedStatus.verified)

        let openStatus = PlaceHours.openStatus(for: place, date: utc("2026-01-05T16:30:00Z")) // 17:30 Oslo
        XCTAssertEqual(openStatus.state, .open)
        XCTAssertTrue(openStatus.verified)
    }
}
