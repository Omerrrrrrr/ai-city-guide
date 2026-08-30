import Foundation

/// Piri's own star+text reviews — separate from `TripAdvisorAPI`'s
/// read-only third-party reviews. Same call shape as `PhotosAPI`.
enum PiriReviewsAPI {
    static func submit(_ request: SubmitReviewRequest, token: String) async throws -> POIReviewSubmitResponse {
        try await APIClient.shared.post("/poi/reviews", body: request, bearerToken: token)
    }

    static func fetchReviews(name: String, lat: Double, lng: Double, token: String?) async throws -> POIReviewsResponse {
        try await APIClient.shared.get(
            "/poi/reviews",
            query: ["name": name, "lat": String(lat), "lng": String(lng)],
            bearerToken: token
        )
    }

    static func reportReview(reviewId: String, reason: String, token: String) async throws {
        let _: OkResponse = try await APIClient.shared.post(
            "/review-reports",
            body: ReviewReportRequest(reviewId: reviewId, reason: reason),
            bearerToken: token
        )
    }

    /// Casts (or changes) the caller's helpful/not-helpful vote on a
    /// review -- an upsert server-side, so calling this again with a
    /// different `helpful` value just changes the vote rather than
    /// stacking a second one.
    static func vote(reviewId: String, helpful: Bool, token: String) async throws {
        let _: OkResponse = try await APIClient.shared.post(
            "/poi/reviews/\(reviewId)/vote",
            body: ReviewVoteRequest(helpful: helpful),
            bearerToken: token
        )
    }
}

private struct ReviewVoteRequest: Encodable {
    var helpful: Bool
}

struct POIReviewSubmitResponse: Decodable {
    var id: String
    var status: String
    var moderationReason: String?
}

private struct ReviewReportRequest: Encodable {
    var reviewId: String
    var reason: String
}
