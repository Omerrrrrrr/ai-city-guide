import Foundation

/// UGC endpoints: user-submitted POI photos, content reports, and user
/// blocking (Apple Guideline 1.2). Same `bearerToken` plumbing `SocialAPI`
/// already uses -- every route here requires auth.
enum PhotosAPI {
    static func uploadPhoto(_ request: PhotoUploadRequest, token: String) async throws -> PhotoUploadResponse {
        try await APIClient.shared.post("/poi/photos", body: request, bearerToken: token)
    }

    static func fetchPhotos(name: String, lat: Double, lng: Double, token: String) async throws -> [UserSubmittedPhoto] {
        let response: UserSubmittedPhotosResponse = try await APIClient.shared.get(
            "/poi/photos",
            query: ["name": name, "lat": String(lat), "lng": String(lng)],
            bearerToken: token
        )
        return response.photos
    }

    static func reportPhoto(photoId: String, reason: String, token: String) async throws {
        let _: OkResponse = try await APIClient.shared.post(
            "/content-reports",
            body: ContentReportRequest(photoId: photoId, reason: reason),
            bearerToken: token
        )
    }

    static func blockUser(id: String, token: String) async throws {
        let _: OkResponse = try await APIClient.shared.post("/users/\(id)/block", bearerToken: token)
    }

    static func unblockUser(id: String, token: String) async throws {
        let _: OkResponse = try await APIClient.shared.post("/users/\(id)/unblock", bearerToken: token)
    }
}

private struct UserSubmittedPhotosResponse: Decodable {
    var photos: [UserSubmittedPhoto]
}
