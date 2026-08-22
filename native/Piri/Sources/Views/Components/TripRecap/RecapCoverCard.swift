import SwiftUI

/// First card of the Trip Recap story -- trip name, dates, a schematic
/// (not literal-map) skyline treatment. `StoryContainer` owns the shared
/// progress-dot/close header, so this card is just its full-bleed content.
struct RecapCoverCard: View {
    let trip: Trip

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.086, green: 0.149, blue: 0.302), Theme.navy, Color(red: 0.03, green: 0.05, blue: 0.1)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RecapSkylineArt()
                .frame(height: 200)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 170)

            VStack(spacing: 22) {
                Text("tripRecap.cover.eyebrow")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2.2)
                    .foregroundStyle(Theme.gold)
                Text(trip.displayTitle)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                Text(trip.dateLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 32)

            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Text("tripRecap.swipeHint")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 34)
            }
        }
    }
}

/// Abstract skyline silhouette + dotted route arc -- a placeholder graphic
/// in the same spirit as the approved mockup, not a literal map render.
struct RecapSkylineArt: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.6))
                    path.addCurve(to: CGPoint(x: w, y: h * 0.5),
                                  control1: CGPoint(x: w * 0.25, y: h * 0.3),
                                  control2: CGPoint(x: w * 0.65, y: h * 0.65))
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.047, green: 0.094, blue: 0.188))

                ForEach(Array(RecapSkylineArt.buildings.enumerated()), id: \.offset) { _, b in
                    Rectangle()
                        .fill(Color(red: 0.047, green: 0.094, blue: 0.188))
                        .frame(width: b.width * w, height: b.height * h)
                        .position(x: b.x * w, y: h - (b.height * h / 2) - h * 0.08)
                }

                Path { path in
                    path.move(to: CGPoint(x: w * 0.1, y: h * 0.55))
                    path.addCurve(to: CGPoint(x: w * 0.9, y: h * 0.15),
                                  control1: CGPoint(x: w * 0.4, y: h * 0.05),
                                  control2: CGPoint(x: w * 0.6, y: h * 0.15))
                }
                .stroke(Theme.gold.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [1, 8]))

                Circle().fill(Theme.gold).frame(width: 9, height: 9).position(x: w * 0.1, y: h * 0.55)
                Circle().fill(Theme.gold).frame(width: 9, height: 9).position(x: w * 0.9, y: h * 0.15)
            }
        }
    }

    static let buildings: [(x: Double, width: Double, height: Double)] = [
        (0.16, 0.04, 0.42), (0.22, 0.03, 0.56), (0.37, 0.05, 0.32),
        (0.55, 0.035, 0.5), (0.68, 0.045, 0.36), (0.8, 0.03, 0.44),
    ]
}
