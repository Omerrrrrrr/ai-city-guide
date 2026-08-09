@testable import Piri

/// Port of `mobile/src/test-utils/place-fixtures.ts`'s `makePlace`.
func makePlace(
    id: String = "place-1",
    name: String = "Test Place",
    category: String = "landmark",
    tags: [String] = [],
    importanceTier: PlaceImportanceTier = .supporting,
    imageVerified: Bool = false,
    visitInfo: PlaceVisitInfo = PlaceVisitInfo(
        durationMinutes: nil, hoursNote: nil, openingHours: nil, hoursVerified: false,
        hoursSourceUrl: nil, hoursLastCheckedAt: nil, bestTime: nil, seasonality: nil, temporarilyClosed: false
    ),
    wiki: PlaceWiki? = nil
) -> Place {
    Place(
        id: id,
        name: name,
        category: category,
        tags: tags,
        description: "A test place description.",
        imageUrl: "https://example.com/image.jpg",
        image: PlaceImage(sourceUrl: nil, sourceName: nil, license: nil, attribution: nil, verified: imageVerified, type: .unknown),
        importanceTier: importanceTier,
        shortStory: "A short story.",
        verifiedFacts: PlaceVerifiedFacts(address: nil, type: nil, priceLevel: nil, sourceUrl: nil),
        visitInfo: visitInfo,
        localVibe: PlaceLocalVibe(mood: nil, bestFor: nil),
        city: "Kristiansand",
        country: nil,
        wiki: wiki,
        location: nil,
        gallery: nil
    )
}

func makeVisitInfo(
    durationMinutes: Int? = nil,
    hoursVerified: Bool = false,
    temporarilyClosed: Bool = false,
    openingHours: OpeningHoursData? = nil,
    hoursSourceUrl: String? = nil,
    hoursLastCheckedAt: String? = nil
) -> PlaceVisitInfo {
    PlaceVisitInfo(
        durationMinutes: durationMinutes, hoursNote: nil, openingHours: openingHours, hoursVerified: hoursVerified,
        hoursSourceUrl: hoursSourceUrl, hoursLastCheckedAt: hoursLastCheckedAt, bestTime: nil, seasonality: nil,
        temporarilyClosed: temporarilyClosed
    )
}
