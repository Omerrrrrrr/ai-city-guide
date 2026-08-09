import Foundation

struct GoogleHoursPreview: Decodable, Identifiable {
    var googlePlaceId: String
    var displayName: String
    var formattedAddress: String?
    var googleMapsUri: String?
    var websiteUri: String?
    var businessStatus: String?
    var confidence: Double
    var openingHours: OpeningHoursData?
    var weekdayDescriptions: [String]
    var hoursNote: String
    var temporarilyClosed: Bool
    var matchReason: String

    var id: String { googlePlaceId }
}

struct GoogleHoursPreviewResponse: Decodable {
    var previews: [GoogleHoursPreview]
}

struct UpdatePlaceHoursRequest: Encodable {
    var hoursVerified: Bool
    var hoursSourceUrl: String?
    var hoursNote: String?
    var temporarilyClosed: Bool
    var openingHours: OpeningHoursData?
}

struct UpdatePlaceHoursResponse: Decodable {
    var place: Place
}

enum ImageCandidateStatus: String, Codable, CaseIterable {
    case pending, approved, rejected, applied
}

struct ImageCandidateCurrentImage: Codable {
    var imageUrl: String
    var verified: Bool
    var sourceName: String?
    var imageType: String?
}

struct ImageCandidate: Codable, Identifiable {
    var id: String
    var placeId: String
    var placeName: String
    var provider: String
    var status: ImageCandidateStatus
    var confidence: Double
    var rank: Int
    var searchQuery: String?
    var pageTitle: String
    var imageUrl: String
    var sourceUrl: String
    var sourceName: String?
    var imageLicense: String?
    var imageAttribution: String?
    var imageType: String
    var notes: String?
    var currentPlaceImage: ImageCandidateCurrentImage
}

struct DiscoverImageCandidatesRequest: Encodable {
    var placeId: String?
    var limit: Int?
    var includeVerified: Bool?
}

struct DiscoverImageCandidatesResult: Decodable {
    struct PlaceResult: Decodable {
        var placeId: String
        var placeName: String
        var discoveredCount: Int
    }

    var discoveredPlaces: Int
    var discoveredCandidates: Int
    var results: [PlaceResult]
}

struct ReassignImageCandidateRequest: Encodable {
    var placeId: String
}

struct ApproveImageCandidateResponse: Decodable {
    var candidate: ImageCandidate
}
