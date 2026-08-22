import Foundation

/// Apple Guideline 1.2 UGC: user-submitted POI photos, reports, and
/// blocking. `photoUrl` is a real R2 `https://` URL for an approved photo,
/// or a `data:` URI for a rejected one (never served) or when R2 isn't
/// configured server-side (see r2.ts / the backend's `userSubmittedPhotos`
/// schema comment) -- `DataURIImage` branches on which one it got.
struct UserSubmittedPhoto: Codable, Identifiable, Hashable {
    var id: String
    var photoUrl: String
    var caption: String?
    var userId: String
    var createdAt: String
}

struct PhotoUploadRequest: Encodable {
    var poiName: String
    var lat: Double
    var lng: Double
    var photoUrl: String
    var caption: String?
}

/// `status` is `"approved"` or `"rejected"` -- a rejected submission failed
/// OpenAI moderation and was never made visible to anyone (including the
/// uploader on their next fetch); `moderationReason` explains why so the
/// UI can show it instead of the photo silently vanishing.
struct PhotoUploadResponse: Decodable {
    var id: String
    var status: String
    var moderationReason: String?
}

struct ContentReportRequest: Encodable {
    var photoId: String
    var reason: String
}
