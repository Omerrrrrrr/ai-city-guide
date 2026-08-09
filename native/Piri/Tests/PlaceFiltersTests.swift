import XCTest
@testable import Piri

/// Port of `mobile/src/utils/__tests__/place-filters.test.ts`.
final class PlaceFiltersTests: XCTestCase {
    // MARK: sortedForProfile

    func testBoostsPlacesMatchingProfessionToTop() {
        let museum = makePlace(id: "museum", category: "museum")
        let cafe = makePlace(id: "cafe", category: "cafe")

        let result = PlaceFilters.sortedForProfile([cafe, museum], profile: UserProfile(profession: .historian))
        XCTAssertEqual(result.first?.id, "museum")
    }

    func testBoostsPlacesMatchingStatedInterest() {
        let beach = makePlace(id: "beach", category: "beach")
        let shopping = makePlace(id: "shopping", category: "shopping-area")

        let result = PlaceFilters.sortedForProfile([shopping, beach], profile: UserProfile(interests: [.nature]))
        XCTAssertEqual(result.first?.id, "beach")
    }

    func testFallsBackToBrowseSortingWhenProfileEmpty() {
        let a = makePlace(id: "a", importanceTier: .longTail)
        let b = makePlace(id: "b", importanceTier: .hero)

        let result = PlaceFilters.sortedForProfile([a, b], profile: UserProfile())
        XCTAssertEqual(result.first?.id, "b")
    }

    func testBoostsBudgetTaggedPlacesForBudgetTraveler() {
        let budgetSpot = makePlace(id: "budget-spot", tags: ["budget"])
        let other = makePlace(id: "other", tags: [])

        let result = PlaceFilters.sortedForProfile([other, budgetSpot], profile: UserProfile(budget: .budget))
        XCTAssertEqual(result.first?.id, "budget-spot")
    }

    func testBoostsFamilyTaggedPlacesForFamilyTraveler() {
        let familySpot = makePlace(id: "family-spot", tags: ["family"])
        let other = makePlace(id: "other", tags: [])

        let result = PlaceFilters.sortedForProfile([other, familySpot], profile: UserProfile(groupType: .family))
        XCTAssertEqual(result.first?.id, "family-spot")
    }

    func testBoostsQuickStopsForPackedPaceAndLongerVisitsForRelaxedPace() {
        let quick = makePlace(id: "quick", visitInfo: makeVisitInfo(durationMinutes: 20))
        let long = makePlace(id: "long", visitInfo: makeVisitInfo(durationMinutes: 120))

        let packedResult = PlaceFilters.sortedForProfile([long, quick], profile: UserProfile(pace: .packed))
        XCTAssertEqual(packedResult.first?.id, "quick")

        let relaxedResult = PlaceFilters.sortedForProfile([quick, long], profile: UserProfile(pace: .relaxed))
        XCTAssertEqual(relaxedResult.first?.id, "long")
    }

    func testBoostsPlacesMatchingRecentlyViewedCategoryWithNoProfile() {
        let museum = makePlace(id: "museum", category: "museum")
        let cafe = makePlace(id: "cafe", category: "cafe")
        let viewedMuseum = makePlace(id: "viewed-museum", category: "museum")

        let result = PlaceFilters.sortedForProfile([cafe, museum], profile: UserProfile(), viewed: [viewedMuseum])
        XCTAssertEqual(result.first?.id, "museum")
    }

    func testHistoryDoesNotOverrideConflictingProfileBoost() {
        let museum = makePlace(id: "museum", category: "museum")
        let cafe = makePlace(id: "cafe", category: "cafe")
        let viewedCafe = makePlace(id: "viewed-cafe", category: "cafe")

        // Historian profile boost (+6) for museum outweighs a single history match (+2) for cafe.
        let result = PlaceFilters.sortedForProfile([cafe, museum], profile: UserProfile(profession: .historian), viewed: [viewedCafe])
        XCTAssertEqual(result.first?.id, "museum")
    }

    // MARK: filter

    private var filterFixture: [Place] {
        [
            makePlace(id: "cafe-1", category: "cafe", tags: ["local favorite"]),
            makePlace(id: "museum-1", category: "museum", tags: ["history"]),
        ]
    }

    func testFilterByCategory() {
        let result = PlaceFilters.filter(filterFixture, with: .init(query: "", category: "cafe", tag: "all", openNow: false))
        XCTAssertEqual(result.map(\.id), ["cafe-1"])
    }

    func testFilterByTag() {
        let result = PlaceFilters.filter(filterFixture, with: .init(query: "", category: "all", tag: "history", openNow: false))
        XCTAssertEqual(result.map(\.id), ["museum-1"])
    }

    func testFilterByCaseInsensitiveTextQuery() {
        let places = [
            makePlace(id: "cafe-1", name: "Rasmus", category: "cafe", tags: ["local favorite"]),
            makePlace(id: "museum-1", name: "City Museum", category: "museum", tags: ["history"]),
        ]
        let result = PlaceFilters.filter(places, with: .init(query: "RASMUS", category: "all", tag: "all", openNow: false))
        XCTAssertEqual(result.map(\.id), ["cafe-1"])
    }

    func testFilterReturnsEverythingWhenAllPermissive() {
        let result = PlaceFilters.filter(filterFixture, with: .init(query: "", category: "all", tag: "all", openNow: false))
        XCTAssertEqual(result.count, 2)
    }

    // MARK: quality score

    func testQualityScoreRanksHeroVerifiedWikiMatchedAboveBareLongTail() {
        let strong = makePlace(
            importanceTier: .hero,
            imageVerified: true,
            visitInfo: makeVisitInfo(hoursVerified: true),
            wiki: PlaceWiki(pageTitle: nil, pageUrl: nil, summary: nil, confidence: 90, status: .matched)
        )
        var strongWithTags = strong
        strongWithTags.tags = ["local favorite", "photogenic"]
        let weak = makePlace(importanceTier: .longTail)

        XCTAssertGreaterThan(PlaceFilters.qualityScore(strongWithTags), PlaceFilters.qualityScore(weak))
        XCTAssertTrue(PlaceFilters.isHighQuality(strongWithTags))
        XCTAssertFalse(PlaceFilters.isHighQuality(weak))
    }

    // MARK: sortedForBrowse

    func testSortedForBrowseRanksHigherQualityAboveLower() {
        let hero = makePlace(id: "hero", importanceTier: .hero, imageVerified: true)
        let longTail = makePlace(id: "long-tail", importanceTier: .longTail)

        let result = PlaceFilters.sortedForBrowse([longTail, hero])
        XCTAssertEqual(result.first?.id, "hero")
    }

    func testSortedForBrowseBreaksTiesAlphabetically() {
        let a = makePlace(id: "a", name: "Alpha Place")
        let b = makePlace(id: "b", name: "Beta Place")

        let result = PlaceFilters.sortedForBrowse([b, a])
        XCTAssertEqual(result.map(\.id), ["a", "b"])
    }

    // MARK: curated tags

    func testCuratedTagsCollectsUniqueTagsCuratedFirst() {
        let places = [
            makePlace(tags: ["zzz-custom", "family"]),
            makePlace(tags: ["budget", "zzz-custom"]),
        ]
        let curated = PlaceFilters.curatedTags(in: places)
        XCTAssertEqual(curated, ["family", "budget"])
    }

    // MARK: formatTag

    func testFormatTagResolvesKnownCuratedTag() {
        // Resolves through the real device/simulator language, whatever it
        // currently is — check the lookup actually succeeded (didn't
        // silently fall through to the raw key) rather than asserting one
        // specific language's exact text.
        let label = PlaceFilters.formatTag("local favorite")
        XCTAssertFalse(label.isEmpty)
        XCTAssertNotEqual(label, "tags.localFavorite")
    }

    func testFormatTagTitleCasesUnknownTag() {
        XCTAssertEqual(PlaceFilters.formatTag("super obscure tag"), "Super Obscure Tag")
    }
}
