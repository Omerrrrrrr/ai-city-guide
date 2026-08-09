import Foundation

/// Port of `mobile/src/api/admin-client.ts` + `place-hours.ts` + `image-candidates.ts`.
/// Every call needs the admin bearer token (`AdminAuthStore`), same as the
/// backend's `isAdminPath`/`ADMIN_API_TOKEN` check.
enum AdminAPI {
    static func updatePlaceHours(placeId: String, request: UpdatePlaceHoursRequest, token: String) async throws -> Place {
        let response: UpdatePlaceHoursResponse = try await APIClient.shared.put("/admin/places/\(placeId)/hours", body: request, bearerToken: token)
        return response.place
    }

    static func fetchGoogleHoursPreview(placeId: String, token: String) async throws -> [GoogleHoursPreview] {
        let response: GoogleHoursPreviewResponse = try await APIClient.shared.post("/admin/places/\(placeId)/hours/google-preview", bearerToken: token)
        return response.previews
    }

    static func fetchImageCandidates(status: ImageCandidateStatus?, token: String) async throws -> [ImageCandidate] {
        try await APIClient.shared.get("/admin/image-candidates", query: ["status": status?.rawValue], bearerToken: token)
    }

    static func discoverImageCandidates(_ request: DiscoverImageCandidatesRequest, token: String) async throws -> DiscoverImageCandidatesResult {
        try await APIClient.shared.post("/admin/image-candidates/discover", body: request, bearerToken: token)
    }

    static func approveImageCandidate(id: String, token: String) async throws {
        let _: ApproveImageCandidateResponse = try await APIClient.shared.post("/admin/image-candidates/\(id)/approve", bearerToken: token)
    }

    static func rejectImageCandidate(id: String, token: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.post("/admin/image-candidates/\(id)/reject", bearerToken: token)
    }

    static func reassignImageCandidate(id: String, placeId: String, token: String) async throws {
        let _: ApproveImageCandidateResponse = try await APIClient.shared.post("/admin/image-candidates/\(id)/reassign", body: ReassignImageCandidateRequest(placeId: placeId), bearerToken: token)
    }

    static func applyImageCandidate(id: String, token: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.post("/admin/image-candidates/\(id)/apply", bearerToken: token)
    }
}
