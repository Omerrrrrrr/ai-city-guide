import SwiftUI

/// Compact badge row surfacing OSM-sourced dietary tags (halal/kosher/
/// vegetarian/vegan) on the main POI explain card — folded in here instead
/// of kept as the map's separate, non-interactive dietary-pin card, so any
/// restaurant tap shows dietary awareness when OSM has it, not just pins
/// already surfaced through the map's dietary filter.
struct DietaryTagsRow: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        let key: String = "diet.\(tag)"
                        Text(String(localized: String.LocalizationValue(key)))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGreen).opacity(0.18), in: Capsule())
                            .foregroundStyle(Color(.systemGreen))
                    }
                }
                // Every other externally-sourced fact on this card
                // (Tripadvisor's rating, each photo) already names its
                // source inline — this was the one silent exception, just
                // an unlabeled row of green pills. Small and secondary on
                // purpose (a "trust marker," not a citation), matching the
                // 2026-08 visual-design research report's Phase 2 finding.
                Text("dietaryTags.source").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
