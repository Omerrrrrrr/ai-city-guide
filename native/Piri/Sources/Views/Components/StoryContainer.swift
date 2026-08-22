import SwiftUI

/// Generic Instagram-Stories-style viewer: progress-dot header (each
/// segment fills in real time as its page's dwell timer runs), tap the
/// left/right half to go back/forward, long-press-and-hold to pause,
/// swipe down to dismiss. Not feature-specific -- takes plain `AnyView`
/// pages, so anything that wants a "story" moment (Trip Recap today,
/// something else later) can reuse it instead of rebuilding this
/// mechanism.
struct StoryContainer: View {
    let pages: [AnyView]
    var pageDuration: Double = 4.5
    var onDismiss: () -> Void

    @State private var index = 0
    @State private var progress: Double = 0
    @State private var paused = false
    @State private var lastTick = Date.now

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                    if i == index {
                        page
                    }
                }

                VStack {
                    progressHeader
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in paused = true }
                    .onEnded { value in
                        paused = false
                        let verticalDrag = value.translation.height
                        let horizontalDrag = abs(value.translation.width)
                        if verticalDrag > 80, horizontalDrag < 60 {
                            onDismiss()
                        } else if horizontalDrag < 12, abs(verticalDrag) < 12 {
                            if value.location.x < geo.size.width / 2 {
                                goToPrevious()
                            } else {
                                goToNext()
                            }
                        }
                    }
            )
        }
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { now in
            defer { lastTick = now }
            guard !paused else { return }
            progress += now.timeIntervalSince(lastTick) / pageDuration
            if progress >= 1 {
                goToNext()
            }
        }
        .onAppear { lastTick = .now }
        .statusBarHidden()
    }

    private var progressHeader: some View {
        HStack(spacing: 4) {
            ForEach(pages.indices, id: \.self) { i in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(Theme.gold)
                            .frame(width: proxy.size.width * fillAmount(for: i))
                    }
                }
                .frame(height: 3)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.white.opacity(0.16)))
            }
            .padding(.leading, 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func fillAmount(for i: Int) -> CGFloat {
        if i < index { return 1 }
        if i == index { return CGFloat(min(max(progress, 0), 1)) }
        return 0
    }

    private func goToNext() {
        guard index < pages.count - 1 else {
            onDismiss()
            return
        }
        index += 1
        progress = 0
    }

    private func goToPrevious() {
        guard index > 0 else { return }
        index -= 1
        progress = 0
    }
}
