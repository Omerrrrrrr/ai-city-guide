import UIKit
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

    /// A trip with only one stop and no breadcrumb/routeGeometry has
    /// nothing spatial to animate -- must fail fast (before ever touching
    /// `MKMapSnapshotter`/the network), not hang or crash.
    @MainActor
    func testThrowsBeforeSnapshottingWhenThereIsNoRealRoute() async {
        let trip = Trip(
            id: "test-trip-no-route",
            name: "Single Stop",
            stops: [
                SavedPOIReference(identifier: "only", name: "Only Stop", categoryRawValue: nil, lat: 58.1467, lng: 7.9956, address: nil),
            ],
            routeGeometry: nil,
            distanceMeters: nil,
            durationSeconds: nil,
            breadcrumb: [],
            photos: [],
            startedAt: 0,
            endedAt: 1000
        )
        let data = TripRecapData(trip: trip, dominantCategory: nil, xpBefore: 0, xpAfter: 0, levelBefore: 1, levelAfter: 1)

        do {
            _ = try await TripRecapVideoRenderer.render(trip: trip, data: data)
            XCTFail("Expected render to throw for a route with < 2 coordinates")
        } catch is TripRecapVideoRenderer.RenderError {
            // Expected.
        } catch {
            XCTFail("Expected RenderError, got \(error)")
        }
    }

    /// Cancelling the wrapping `Task` (e.g. the user dismissing the sheet
    /// mid-generation) must stop the ~240-frame loop promptly instead of
    /// burning through the rest of a render nobody will see.
    @MainActor
    func testCancellationStopsFrameLoopPromptly() async throws {
        let center = (lat: 58.1467, lng: 7.9956)
        let breadcrumb: [TripWaypoint] = (0..<20).map { i in
            TripWaypoint(lat: center.lat + Double(i) * 0.0005, lng: center.lng + Double(i) * 0.0005, timestamp: Double(i) * 1000)
        }
        let trip = Trip(
            id: "test-trip-cancel",
            name: "Cancel Me",
            stops: [],
            routeGeometry: nil,
            distanceMeters: 500,
            durationSeconds: 300,
            breadcrumb: breadcrumb,
            photos: [],
            startedAt: 0,
            endedAt: 300_000
        )
        let data = TripRecapData(trip: trip, dominantCategory: nil, xpBefore: 0, xpAfter: 10, levelBefore: 1, levelAfter: 1)

        let renderTask = Task { @MainActor in
            try await TripRecapVideoRenderer.render(trip: trip, data: data)
        }
        // Deliberately short -- well inside the map snapshot's own network
        // round trip, not after it. This is the harder (and, empirically,
        // previously broken) half of cancellation to get right: a plain
        // `Task.checkCancellation()` in the frame loop does nothing while
        // still stuck awaiting `MKMapSnapshotter`'s completion handler,
        // which has no idea Swift Task cancellation exists on its own --
        // see `snapshotMap`'s `withTaskCancellationHandler`. A first
        // version of this test that cancelled after 1.5s (long enough to
        // often land after the snapshot had already returned) passed by
        // accident, sometimes, without ever actually exercising this path.
        try await Task.sleep(nanoseconds: 150_000_000)
        renderTask.cancel()

        let start = Date()
        do {
            _ = try await renderTask.value
            XCTFail("Expected the render to throw after cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            // A `TripRecapVideoRenderer.RenderError` thrown from inside the
            // cancellation `catch` block (writer.cancelWriting()'s own
            // error surfacing) is also an acceptable outcome -- what
            // matters is that it stopped quickly, asserted below.
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 5, "Cancellation should stop the frame loop within a couple seconds, not run to completion")
    }

    /// Exercises the two paths the happy-path test above doesn't: a real
    /// (data-URI, fully offline) hero photo for the closing beat, and an
    /// XP gain that does NOT cross a level boundary (the "+N xp" line
    /// rather than the "leveled up" one).
    @MainActor
    func testRendersWithHeroPhotoAndNoLevelUp() async throws {
        let center = (lat: 58.1467, lng: 7.9956)
        let breadcrumb: [TripWaypoint] = (0..<20).map { i in
            let angle = Double(i) / 20.0 * 2 * .pi
            return TripWaypoint(
                lat: center.lat + sin(angle) * 0.008,
                lng: center.lng + cos(angle) * 0.008 * 1.8,
                timestamp: Double(i) * 20_000
            )
        }
        // A minimal valid 1x1 red PNG, inlined as a data: URI so this test
        // has no network dependency for the photo itself. Generated (not
        // hand-typed) via zlib/struct to guarantee a correct IDAT CRC --
        // a hand-typed version of this same idea previously decoded to
        // `nil` silently (libpng logged "IDAT: CRC error" but
        // `loadHeroImage` swallows a decode failure the same as "no
        // photo"), which meant this test wasn't actually exercising the
        // hero-photo code path it claimed to.
        let tinyRedPNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGO4IycHAALyARlzRAvLAAAAAElFTkSuQmCC"

        let trip = Trip(
            id: "test-trip-photo",
            name: "Photo Trip",
            stops: [],
            routeGeometry: nil,
            distanceMeters: 3200,
            durationSeconds: 1800,
            breadcrumb: breadcrumb,
            photos: [TripPhoto(uri: tinyRedPNG, timestamp: 0, lat: center.lat, lng: center.lng)],
            startedAt: 0,
            endedAt: 1_800_000
        )
        let data = TripRecapData(trip: trip, dominantCategory: nil, xpBefore: 100, xpAfter: 140, levelBefore: 2, levelAfter: 2)
        XCTAssertFalse(data.leveledUp)
        XCTAssertEqual(data.xpDelta, 40)

        // Fast, direct check on the fixture itself, independent of the
        // ~20s full render below -- catches a corrupt/mistyped data: URI
        // immediately instead of only noticing via silent "no hero photo"
        // fallback behavior (see this test's own history, in the comment
        // above `tinyRedPNG`).
        let base64Payload = String(tinyRedPNG.dropFirst("data:image/png;base64,".count))
        let decodedData = try XCTUnwrap(Data(base64Encoded: base64Payload), "Test fixture's base64 payload doesn't decode")
        XCTAssertNotNil(UIImage(data: decodedData), "Test fixture PNG doesn't decode to a UIImage")

        let url = try await TripRecapVideoRenderer.render(trip: trip, data: data)
        print("RECAP_VIDEO_PATH_PHOTO: \(url.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
