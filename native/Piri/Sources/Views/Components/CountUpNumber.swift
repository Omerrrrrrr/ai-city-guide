import SwiftUI

/// Animates a number counting up from 0 to `value` once, using SwiftUI's
/// built-in `.numericText()` content transition (iOS 16+) rather than a
/// hand-rolled `Animatable` modifier -- this is Apple's own mechanism for
/// animating digit changes and gets tabular-width digit crossfades for
/// free. Counts up exactly once per appearance (not on every re-render) by
/// gating the animated `setState` behind `.task(id: value)`.
struct CountUpNumber: View {
    let value: Double
    /// e.g. `{ "\(Int($0))" }` or `{ String(format: "%.1f", $0) }`.
    var format: (Double) -> String = { "\(Int($0))" }
    var delay: Double = 0.15
    var duration: Double = 1.0

    @State private var displayed: Double = 0

    var body: some View {
        Text(format(displayed))
            .contentTransition(.numericText(value: displayed))
            .task(id: value) {
                displayed = 0
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: duration)) {
                    displayed = value
                }
            }
    }
}
