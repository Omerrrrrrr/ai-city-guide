import SwiftUI

/// One consistent visual language for "this specific piece of data came
/// from a real external source" — used wherever the POI card shows
/// something that isn't Piri's own voice: dietary tags (OpenStreetMap) and
/// the AI explanation body text itself, when it was actually grounded in a
/// real Wikipedia/Tripadvisor source rather than general knowledge. Before
/// this existed, only dietary tags had any source note at all, and the AI
/// body — the single place a "Trust Marker" matters most, per the 2026-08
/// visual-design research report — had none.
struct SourceCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
}
