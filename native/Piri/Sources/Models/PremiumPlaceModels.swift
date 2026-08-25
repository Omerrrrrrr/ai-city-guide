import Foundation

/// Mirrors `apps/api/src/google-places-poi.ts`'s request/response shape for
/// `POST /places/premium-details` -- paid-tier-only Google Places data
/// (rating/price/hours/photo), consumed by `PremiumDetailsSection`.
struct PremiumDetailsRequest: Encodable {
    var name: String
    var lat: Double?
    var lng: Double?
    var address: String?
}

struct PremiumPlaceDetails: Decodable {
    var googlePlaceId: String
    var displayName: String
    var formattedAddress: String?
    var googleMapsUri: String?
    var websiteUri: String?
    var rating: Double?
    var userRatingCount: Int?
    var priceLevel: String?
    var editorialSummary: String?
    var openNow: Bool?
    var weekdayDescriptions: [String]?
    var photoUrl: String?
}
