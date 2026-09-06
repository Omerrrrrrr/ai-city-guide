import AVFoundation
import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Renders the Trip Recap as a real, shareable .mp4 -- replaced the old
/// swipeable-story-of-static-cards flow entirely (2026-09, at the user's
/// explicit request after seeing a competitor's exported recap clip).
///
/// Two-pass pipeline, both passes deliberately using the highest-level
/// AVFoundation API available for the job rather than hand-rolling the
/// fiddlier alternative:
/// 1. `AVAssetWriter` + `ImageRenderer`: draws `RecapVideoScene` once per
///    frame (a pure function of `t`, see that type's own doc comment) into
///    a `CVPixelBuffer` and appends it -- a plain video-only track, no
///    audio input at all, since manually building a PCM `CMSampleBuffer`
///    is a much easier place to introduce a subtle, hard-to-debug bug than
///    the composition step below.
/// 2. `AVMutableComposition` + `AVAssetExportSession`: lays the pass-1
///    video over a synthesized short completion chime (silence
///    everywhere else on the audio track), mirroring the standard
///    "overlay audio onto an existing video" recipe rather than anything
///    novel.
enum TripRecapVideoRenderer {
    struct RenderError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Renders and returns the finished video's file URL (in
    /// `FileManager.default.temporaryDirectory` -- the caller owns
    /// deleting it once shared/saved). `onProgress` is called on the main
    /// actor with a `0...1` fraction covering the (dominant) frame-render
    /// pass only, for a real progress indicator rather than an indefinite
    /// spinner during what can be several real seconds of work.
    @MainActor
    static func render(trip: Trip, data: TripRecapData, onProgress: @escaping (Double) -> Void = { _ in }) async throws -> URL {
        let coordinates = routeCoordinates(for: trip)
        guard coordinates.count > 1 else {
            throw RenderError(message: "Not enough route points to render a recap video")
        }

        async let mapResult = snapshotMap(coordinates: coordinates)
        async let heroImage = loadHeroImage(for: trip)
        let (mapImage, routePoints) = try await mapResult

        let videoOnlyURL = try await renderFrames(
            mapImage: mapImage,
            routePoints: routePoints,
            heroImage: await heroImage,
            trip: trip,
            data: data,
            onProgress: onProgress
        )

        let finalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trip-recap-\(trip.id)-\(Int(Date().timeIntervalSince1970)).mp4")
        try await muxChime(into: videoOnlyURL, finalURL: finalURL)
        try? FileManager.default.removeItem(at: videoOnlyURL)
        return finalURL
    }

    // MARK: - Route data

    /// The real recorded path (breadcrumb) when there is one, since that's
    /// what the user actually walked/drove/cycled -- falls back to the
    /// planned route geometry, then to a straight line between stops, for
    /// older or live-tracking-less trips that still have *something*
    /// spatial to show.
    private static func routeCoordinates(for trip: Trip) -> [CLLocationCoordinate2D] {
        if trip.breadcrumb.count > 1 {
            return trip.breadcrumb.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        }
        if let geometry = trip.routeGeometry, geometry.count > 1 {
            return geometry.compactMap { pair in
                guard pair.count == 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
            }
        }
        return trip.stops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    private static func boundingRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0
        let maxLng = lngs.max() ?? 0

        let paddingFactor = 1.5 // 25% padding on every side
        var latDelta = max((maxLat - minLat) * paddingFactor, 0.01)
        var lngDelta = max((maxLng - minLng) * paddingFactor, 0.01)

        // Match the video's own portrait aspect so the snapshot's route
        // isn't squeezed/stretched relative to what actually gets drawn.
        let targetAspect = RecapVideoTimeline.size.width / RecapVideoTimeline.size.height
        let currentAspect = lngDelta / latDelta
        if currentAspect > targetAspect {
            latDelta = lngDelta / targetAspect
        } else {
            lngDelta = latDelta * targetAspect
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        )
    }

    // MARK: - Map snapshot

    private static func snapshotMap(coordinates: [CLLocationCoordinate2D]) async throws -> (UIImage, [CGPoint]) {
        let options = MKMapSnapshotter.Options()
        options.region = boundingRegion(for: coordinates)
        options.size = RecapVideoTimeline.size
        options.scale = 1
        options.showsBuildings = true
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        if #available(iOS 16.0, *) {
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            configuration.pointOfInterestFilter = .excludingAll
            options.preferredConfiguration = configuration
        }

        let snapshotter = MKMapSnapshotter(options: options)
        return try await withCheckedThrowingContinuation { continuation in
            snapshotter.start { snapshot, error in
                if let snapshot {
                    let points = coordinates.map { snapshot.point(for: $0) }
                    continuation.resume(returning: (snapshot.image, points))
                } else {
                    continuation.resume(throwing: error ?? RenderError(message: "MKMapSnapshotter returned no snapshot"))
                }
            }
        }
    }

    private static func loadHeroImage(for trip: Trip) async -> UIImage? {
        guard let photo = trip.photos.first, let url = URL(string: photo.uri) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Pass 1: frame-by-frame video-only render

    @MainActor
    private static func renderFrames(
        mapImage: UIImage,
        routePoints: [CGPoint],
        heroImage: UIImage?,
        trip: Trip,
        data: TripRecapData,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("trip-recap-video-only-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let width = Int(RecapVideoTimeline.size.width)
        let height = Int(RecapVideoTimeline.size.height)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: pixelBufferAttributes)

        guard writer.canAdd(videoInput) else { throw RenderError(message: "Cannot add video input") }
        writer.add(videoInput)

        guard writer.startWriting() else {
            throw writer.error ?? RenderError(message: "startWriting failed")
        }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(RecapVideoTimeline.totalDuration * Double(RecapVideoTimeline.frameRate))
        let renderer = ImageRenderer(content: RecapVideoScene(mapImage: mapImage, routePoints: routePoints, heroImage: heroImage, trip: trip, data: data, t: 0))
        renderer.scale = 1

        for frameIndex in 0..<totalFrames {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            let t = totalFrames > 1 ? Double(frameIndex) / Double(totalFrames - 1) : 1
            renderer.content = RecapVideoScene(mapImage: mapImage, routePoints: routePoints, heroImage: heroImage, trip: trip, data: data, t: t)

            guard let cgImage = renderer.cgImage,
                  let pixelBuffer = makePixelBuffer(from: cgImage, width: width, height: height, pool: adaptor.pixelBufferPool) else {
                continue
            }
            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: RecapVideoTimeline.frameRate)
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            onProgress(Double(frameIndex + 1) / Double(totalFrames))
        }

        videoInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? RenderError(message: "Video render did not complete")
        }
        return outputURL
    }

    private static func makePixelBuffer(from cgImage: CGImage, width: Int, height: Int, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var pixelBufferOut: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBufferOut)
        }
        if pixelBufferOut == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ]
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attributes as CFDictionary, &pixelBufferOut)
        }
        guard let pixelBuffer = pixelBufferOut else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    // MARK: - Pass 2: mux the completion chime over the rendered video

    private static func muxChime(into videoURL: URL, finalURL: URL) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let composition = AVMutableComposition()

        guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw RenderError(message: "Rendered asset has no video track")
        }
        let videoDuration = try await videoAsset.load(.duration)
        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        try compositionVideoTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceVideoTrack, at: .zero)

        if let chimeURL = synthesizeChime() {
            defer { try? FileManager.default.removeItem(at: chimeURL) }
            let chimeAsset = AVURLAsset(url: chimeURL)
            if let chimeTrack = try? await chimeAsset.loadTracks(withMediaType: .audio).first {
                let chimeDuration = try await chimeAsset.load(.duration)
                let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                let insertAt = CMTime(seconds: RecapVideoTimeline.chimeOffsetSeconds, preferredTimescale: 600)
                try? compositionAudioTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: chimeDuration), of: chimeTrack, at: insertAt)
            }
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw RenderError(message: "Could not create export session")
        }
        try? FileManager.default.removeItem(at: finalURL)
        export.outputURL = finalURL
        export.outputFileType = .mp4

        await export.export()
        guard export.status == .completed else {
            throw export.error ?? RenderError(message: "Final export did not complete")
        }
    }

    /// A short, original, synthesized "success sparkle" -- three sine
    /// tones in a quick ascending major-ish arpeggio with a fast
    /// exponential decay envelope, not a sourced/licensed sound effect
    /// (avoids any question of where a bundled audio asset's rights came
    /// from). Returns `nil` (silently skipping the chime, not failing the
    /// whole export) if writing the temp file fails for any reason.
    private static func synthesizeChime() -> URL? {
        let sampleRate = 44100.0
        let duration = 0.6
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData?[0] else { return nil }

        struct Note { let frequency: Double; let start: Double; let length: Double }
        let notes = [
            Note(frequency: 659.25, start: 0.00, length: 0.35), // E5
            Note(frequency: 830.61, start: 0.07, length: 0.35), // G#5
            Note(frequency: 987.77, start: 0.14, length: 0.42), // B5
        ]

        for note in notes {
            let startFrame = Int(note.start * sampleRate)
            let lengthFrames = Int(note.length * sampleRate)
            for i in 0..<lengthFrames {
                let frame = startFrame + i
                guard frame < Int(frameCount) else { break }
                let elapsed = Double(i) / sampleRate
                let envelope = exp(-elapsed * 6.5)
                let sample = sin(2.0 * .pi * note.frequency * elapsed) * envelope * 0.18
                channelData[frame] += Float(sample)
            }
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recap-chime-\(UUID().uuidString).caf")
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        } catch {
            return nil
        }
    }
}
