import XCTest
@testable import Piri

/// Not a fast unit test -- this actually drives `MKMapSnapshotter` (real
/// network map tiles) and renders ~240 frames through `ImageRenderer`, so
/// it takes real wall-clock seconds. Exists to give a human something
/// concrete to inspect (the printed path is a real .mp4 on disk, openable
/// directly on the host Mac since the Simulator shares its filesystem)
/// rather than trusting the render pipeline compiled, therefore works.
final class TripRecapVideoRendererTests: XCTestCase {
    @MainActor
    func testRendersAPlayableVideoForARealLoop() async throws {
        // A rough loop around Kristiansand, Norway (same area used by this
        // app's other trip fixtures) -- real coordinates so the map
        // snapshot has real tiles/water/roads to render, not empty ocean.
        let center = (lat: 58.1467, lng: 7.9956)
        let pointCount = 40
        let breadcrumb: [TripWaypoint] = (0..<pointCount).map { i in
            let angle = Double(i) / Double(pointCount) * 2 * .pi
            let radiusDegrees = 0.012
            return TripWaypoint(
                lat: center.lat + sin(angle) * radiusDegrees,
                lng: center.lng + cos(angle) * radiusDegrees * 1.8,
                timestamp: Double(i) * 30_000
            )
        }

        let trip = Trip(
            id: "test-trip-recap-video",
            name: "Kristiansand Loop",
            stops: [
                SavedPOIReference(identifier: "start", name: "Posebyen", categoryRawValue: nil, lat: center.lat, lng: center.lng, address: nil),
            ],
            routeGeometry: nil,
            distanceMeters: 7840,
            durationSeconds: 7273,
            breadcrumb: breadcrumb,
            photos: [],
            startedAt: 0,
            endedAt: 7_273_000
        )

        let data = TripRecapData(
            trip: trip,
            dominantCategory: nil,
            xpBefore: 120,
            xpAfter: 260,
            levelBefore: 2,
            levelAfter: 3
        )

        var lastProgress = 0.0
        let url = try await TripRecapVideoRenderer.render(trip: trip, data: data) { fraction in
            lastProgress = fraction
        }
        print("RECAP_VIDEO_PATH: \(url.path)")

        XCTAssertEqual(lastProgress, 1.0, accuracy: 0.001)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let sizeBytes = attributes[.size] as? Int ?? 0
        XCTAssertGreaterThan(sizeBytes, 200_000, "Rendered video is suspiciously small -- likely near-empty/broken")
    }
}
