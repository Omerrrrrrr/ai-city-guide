import Foundation

/// An un-enriched Overture-sourced pin returned by `/places/nearby-live`.
/// Unlike react-native-maps, MapKit's native clustering can absorb the full
/// server response without a client-side crash, so there's no equivalent
/// here of the RN app's manual "tap to discover this area" workaround.
struct LivePin: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var category: String
    var lat: Double
    var lng: Double
}

struct LivePinsResponse: Decodable {
    var livePins: [LivePin]
}

struct EnrichLiveRequest: Encodable {
    var overtureId: String
}
