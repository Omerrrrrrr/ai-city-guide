import AVKit
import Photos
import SwiftUI
import UIKit

/// The Trip Recap -- a real, shareable .mp4 (see `TripRecapVideoRenderer`),
/// not the swipeable story of static cards this used to be (replaced
/// entirely 2026-09, at the user's request, after a competitor's exported
/// recap clip set the bar). Generates once per presentation (no caching --
/// a `PendingTripRecap` is a one-shot payload from `endRoute()` anyway, see
/// `MapScreen.swift`), then loops the result in-place with Save/Share.
struct TripRecapView: View {
    let trip: Trip
    let xpBefore: Int
    let xpAfter: Int
    let levelBefore: Int
    let levelAfter: Int
    let myLifetimeTripCount: Int

    @Environment(FriendsStore.self) private var friendsStore
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case preparing
        case ready
        case failed
    }

    @State private var phase: Phase = .preparing
    @State private var progress: Double = 0
    @State private var videoURL: URL?
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var showingShare = false
    @State private var justSaved = false

    var body: some View {
        ZStack {
            Theme.navy.ignoresSafeArea()
            switch phase {
            case .preparing: preparingView
            case .ready: readyView
            case .failed: failedView
            }
        }
        .task { await generate() }
        .sheet(isPresented: $showingShare) {
            if let videoURL { ActivityShareSheet(items: [videoURL]) }
        }
    }

    private var preparingView: some View {
        VStack(spacing: 22) {
            ProgressView(value: progress)
                .tint(Theme.gold)
                .frame(width: 220)
            Text(String(localized: "tripRecap.generating"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var readyView: some View {
        VStack(spacing: 0) {
            Spacer()
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(RecapVideoTimeline.size.width / RecapVideoTimeline.size.height, contentMode: .fit)
                    .onAppear { player.play() }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)
            }
            Spacer()
            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button(String(localized: "common.done")) { dismiss() }
                .buttonStyle(.bordered)
                .tint(.white)

            Spacer()

            if justSaved {
                Text(String(localized: "tripRecap.saved"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.gold)
            }

            Button {
                Task { await saveToPhotos() }
            } label: {
                Label(String(localized: "common.save"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .tint(Theme.gold)

            Button {
                showingShare = true
            } label: {
                Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.gold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Theme.gold)
            Text(String(localized: "tripRecap.generationFailed"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(String(localized: "common.done")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.gold)
        }
    }

    private func generate() async {
        let data = await TripRecapData.build(
            trip: trip,
            xpBefore: xpBefore,
            xpAfter: xpAfter,
            levelBefore: levelBefore,
            levelAfter: levelAfter,
            myLifetimeTripCount: myLifetimeTripCount,
            myUserId: authStore.user?.id,
            friendsStore: friendsStore,
            token: authStore.token
        )
        // Video encoding is exactly the kind of work `beginBackgroundTask`
        // exists for -- without it, backgrounding the app mid-render (a
        // call comes in, the user switches apps) can get this process
        // suspended within seconds with nothing requesting extra time,
        // abandoning `AVAssetWriter` mid-write. The render already handles
        // `Task` cancellation cleanly (see `TripRecapVideoRenderer`,
        // hardened earlier this session for the sheet-dismiss case) -- this
        // just gives the system a controlled way to trigger that same
        // cleanup from backgrounding too, instead of an uncontrolled
        // suspension mid-write.
        let renderTask = Task {
            // `render` and the frame loop inside it are both `@MainActor`,
            // and this call itself already runs on the MainActor (`.task`
            // on a View, inherited by this unstructured `Task`), so
            // `onProgress` fires here with no actor hop needed -- a nested
            // `Task { @MainActor in ... }` per frame would just be 240
            // wasted Task allocations.
            try await TripRecapVideoRenderer.render(trip: trip, data: data) { fraction in
                progress = fraction
            }
        }
        let backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "TripRecapRender") {
            renderTask.cancel()
        }
        defer { UIApplication.shared.endBackgroundTask(backgroundTaskId) }

        do {
            let url = try await renderTask.value
            videoURL = url
            let item = AVPlayerItem(url: url)
            let queuePlayer = AVQueuePlayer()
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            player = queuePlayer
            phase = .ready
        } catch {
            phase = .failed
        }
    }

    private func saveToPhotos() async {
        guard let videoURL else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: videoURL, options: nil)
            }
            justSaved = true
        } catch {
            // Best-effort -- Share (which can also save, via the system
            // sheet's own "Save Video" action) is always still available.
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
