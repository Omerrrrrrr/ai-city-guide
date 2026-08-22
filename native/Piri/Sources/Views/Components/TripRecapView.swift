import SwiftUI
import UIKit

/// The Trip Recap story -- assembles `TripRecapData` (best-effort async
/// friends/leaderboard fetch included) then hands 7 cards to
/// `StoryContainer`. Owns the Share card's export: renders `RecapShareCard`
/// standalone via `ImageRenderer` (no story chrome baked in, since the
/// dots/close overlay lives only in `StoryContainer`) and hands the result
/// to a plain `UIActivityViewController` -- more reliably renders a
/// programmatically-drawn image than `ShareLink(item: Image(uiImage:))` in
/// practice, and nothing in the app already wraps one to reuse.
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

    @State private var data: TripRecapData?
    @State private var posterImage: UIImage?
    @State private var showingShare = false

    var body: some View {
        Group {
            if let data {
                StoryContainer(pages: pages(for: data), onDismiss: { dismiss() })
            } else {
                ZStack {
                    Theme.navy.ignoresSafeArea()
                    ProgressView().tint(Theme.gold)
                }
            }
        }
        .task {
            data = await TripRecapData.build(
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
        }
        .sheet(isPresented: $showingShare) {
            if let posterImage {
                ActivityShareSheet(items: [posterImage])
            }
        }
    }

    private func pages(for data: TripRecapData) -> [AnyView] {
        [
            AnyView(RecapCoverCard(trip: trip)),
            AnyView(RecapRouteCard(trip: trip)),
            AnyView(RecapStatsCard(trip: trip)),
            AnyView(RecapHighlightCard(trip: trip)),
            AnyView(RecapXPCard(data: data)),
            AnyView(RecapSocialCard(data: data)),
            AnyView(RecapShareCard(trip: trip, data: data, onShare: { exportAndShare(data: data) })),
        ]
    }

    private func exportAndShare(data: TripRecapData) {
        let renderer = ImageRenderer(content: RecapShareCard(trip: trip, data: data, onShare: nil).frame(width: 390, height: 844))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return }
        posterImage = uiImage
        showingShare = true
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
