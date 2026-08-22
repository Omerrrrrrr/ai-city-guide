import SwiftUI

/// Schematic route card -- stop dots are laid out at the *real* relative
/// lat/lng positions of `trip.stops` (normalized into the card's frame),
/// not an invented squiggle, so the shape actually reflects the trip even
/// though it isn't a real map tile underneath.
struct RecapRouteCard: View {
    let trip: Trip

    private var normalizedStops: [(name: String, point: CGPoint)] {
        guard !trip.stops.isEmpty else { return [] }
        let lats = trip.stops.map(\.lat)
        let lngs = trip.stops.map(\.lng)
        let latRange = (lats.max() ?? 0) - (lats.min() ?? 0)
        let lngRange = (lngs.max() ?? 0) - (lngs.min() ?? 0)
        let minLat = lats.min() ?? 0
        let minLng = lngs.min() ?? 0
        return trip.stops.map { stop in
            let nx = lngRange > 0.00001 ? (stop.lng - minLng) / lngRange : 0.5
            // Latitude increases northward but screen y increases downward.
            let ny = latRange > 0.00001 ? 1 - (stop.lat - minLat) / latRange : 0.5
            return (stop.name, CGPoint(x: nx, y: ny))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 78)

            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.039, green: 0.082, blue: 0.149))
                .overlay(routeMap)
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)

            bottomSheet
        }
        .background(Theme.navy.ignoresSafeArea())
    }

    private var routeMap: some View {
        GeometryReader { geo in
            let stops = normalizedStops
            let pad: CGFloat = 32
            let w = geo.size.width - pad * 2
            let h = geo.size.height - pad * 2

            ZStack {
                if stops.count > 1 {
                    Path { path in
                        for (i, stop) in stops.enumerated() {
                            let pt = CGPoint(x: pad + stop.point.x * w, y: pad + stop.point.y * h)
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(Theme.gold.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [1, 8]))
                }

                ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                    let pt = CGPoint(x: pad + stop.point.x * w, y: pad + stop.point.y * h)
                    let isEndpoint = i == 0 || i == stops.count - 1
                    Circle()
                        .fill(isEndpoint ? Theme.gold : .white.opacity(0.9))
                        .frame(width: isEndpoint ? 11 : 8, height: isEndpoint ? 11 : 8)
                        .position(pt)
                }
            }
        }
    }

    private var bottomSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("tripRecap.route.label")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.45))
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                CountUpNumber(value: Double(trip.stops.count))
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundStyle(.white)
                Text("tripRecap.route.unit")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.gold)
            }

            FlowChips(names: Array(trip.stops.prefix(4).map(\.name)), overflow: max(0, trip.stops.count - 4))
        }
        .padding(24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.043, green: 0.075, blue: 0.161))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct FlowChips: View {
    let names: [String]
    let overflow: Int

    var body: some View {
        // Simple wrap-capable row -- trip stop counts are small (single
        // digits), so a plain HStack with wrap via LazyVGrid-style flow
        // isn't needed; this fits comfortably on one or two lines via
        // native line wrapping inside a Text-free chip row.
        FlexibleChipRow(items: names + (overflow > 0 ? [L("tripRecap.route.more", overflow)] : []))
    }
}

private struct FlexibleChipRow: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Chip(text: item)
            }
        }
    }
}

private struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.08)).overlay(Capsule().stroke(.white.opacity(0.12))))
    }
}
