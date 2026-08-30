import Foundation

/// Piri's own star+text review — the one rating source actually generated
/// inside the app, as opposed to Tripadvisor's/Google's (both read-only,
/// third-party). Fetched/posted via `/poi/reviews`.
struct POIReview: Codable, Identifiable, Hashable {
    var id: String
    var userId: String
    var rating: Int
    var text: String?
    /// Self-reported by the reviewer's own device from real local GPS
    /// history (`TripsStore.hasVisited`) at submission time — see
    /// `apps/api/src/schema.ts`'s `verifiedVisit` comment for the trust
    /// model this relies on.
    var verifiedVisit: Bool
    /// Community "was this useful" signal — counts from `reviewVotes`,
    /// recomputed server-side on every fetch rather than stored on the
    /// review row itself. `myVote` is `nil` (not voted), `true` (helpful)
    /// or `false` (not helpful) for the signed-in caller; always `nil`
    /// when signed out.
    var helpfulCount: Int
    var notHelpfulCount: Int
    var myVote: Bool?
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
    var visited: Bool
}
