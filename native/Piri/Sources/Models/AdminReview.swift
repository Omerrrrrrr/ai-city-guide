import Foundation

/// A raw `poiReviews` row as `/admin/reviews` returns it -- every column,
/// unlike `POIReview` (the public shape `/poi/reviews` exposes), since the
/// moderation queue needs `status`/`moderationReason`/`poiName` to make a
/// call the public list never needs to show.
struct AdminReviewRow: Codable, Identifiable {
    var id: String
    var poiKey: String
    var poiName: String
    var userId: String
    var rating: Int
    var text: String?
    var verifiedVisit: Bool
    var status: String
    var moderationReason: String?
    var createdAt: String
}

struct AdminReviewActionResponse: Decodable {
    var review: AdminReviewRow
}
