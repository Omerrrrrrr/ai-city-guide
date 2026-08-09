import MapKit
import SwiftUI

/// Wraps the real `MKLookAroundViewController` instead of SwiftUI's
/// `LookAroundPreview` — `LookAroundPreview` only shows a static thumbnail
/// that requires a tap before it becomes navigable, but embedding the actual
/// view controller makes the small card itself pannable/rotatable right
/// away, exactly like the full-screen experience just shown smaller.
private struct LookAroundInteractiveView: UIViewControllerRepresentable {
    let scene: MKLookAroundScene

    func makeUIViewController(context: Context) -> MKLookAroundViewController {
        let controller = MKLookAroundViewController(scene: scene)
        controller.isNavigationEnabled = true
        controller.showsRoadLabels = true
        return controller
    }

    func updateUIViewController(_ uiViewController: MKLookAroundViewController, context: Context) {
        if uiViewController.scene !== scene {
            uiViewController.scene = scene
        }
    }
}

/// Small, directly pannable Look Around card with a corner button that opens
/// a larger full-screen version — the small card no longer requires a tap
/// just to start looking around, but tapping the expand button still
/// continues into a bigger, dedicated view for closer exploration.
///
/// `MKLookAroundViewController` already draws its own "Etrafa Bak" /
/// "Look Around" attribution badge (top-leading, required by Apple's usage
/// guidelines) — a second custom badge there duplicated/overlapped it, so
/// the expand affordance lives in the opposite corner with a distinct icon.
struct LookAroundCard: View {
    let scene: MKLookAroundScene
    var height: CGFloat = 160

    @State private var showingFullscreen = false

    var body: some View {
        LookAroundInteractiveView(scene: scene)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showingFullscreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .padding(8)
                        .background(.black.opacity(0.55), in: Circle())
                        .foregroundStyle(.white)
                }
                .padding(8)
            }
            .fullScreenCover(isPresented: $showingFullscreen) {
                ZStack(alignment: .topTrailing) {
                    LookAroundInteractiveView(scene: scene).ignoresSafeArea()
                    Button {
                        showingFullscreen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding()
                }
            }
    }
}
