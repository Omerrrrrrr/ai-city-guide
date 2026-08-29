import Foundation

/// Piri's own star+text review — the one rating source actually generated
/// inside the app, as opposed to Tripadvisor's/Google's (both read-only,
/// third-party). Fetched/posted via `/poi/reviews`.
struct POIReview: Codable, Identifiable, Hashable {
    var id: String
    var userId: String
    var rating: Int
    var text: String?
    var createdAt: String
}

struct POIReviewsResponse: Codable {
    var reviews: [POIReview]
    var average: Double?
    var count: Int
}

struct SubmitReviewRequest: Encodable {
    var poiName: String
    var lat: Double
    var lng: Double
    var rating: Int
    var text: String?
}
