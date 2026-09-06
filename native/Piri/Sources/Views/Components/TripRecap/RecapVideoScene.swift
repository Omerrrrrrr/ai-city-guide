import SwiftUI
import UIKit

/// One frame of the Trip Recap video, as a pure function of `t` (`0...1`,
/// the whole clip's timeline) -- rendered once per exported frame by
/// `TripRecapVideoRenderer` via `ImageRenderer`, so nothing here may depend
/// on implicit SwiftUI animation, `.onAppear`, timers, or any other
/// non-deterministic state. `mapImage`/`routePoints` are pre-computed once
/// (a real `MKMapSnapshotter` render, dark-styled, plus the trip's route
/// projected into that image's own pixel space) rather than re-fetched per
/// frame.
struct RecapVideoScene: View {
    let mapImage: UIImage
    let routePoints: [CGPoint]
    let heroImage: UIImage?
    let trip: Trip
    let data: TripRecapData
    let t: Double

    private var size: CGSize { RecapVideoTimeline.size }

    var body: some View {
        ZStack {
            Color.black
            mapLayer
            routeLayer
            flourishLayer
            statsLayer
            outroLayer
            brandMark
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: - Map

    private var mapLayer: some View {
        Image(uiImage: mapImage)
            .resizable()
            .frame(width: size.width, height: size.height)
    }

    // MARK: - Route

    private var routePath: Path {
        var path = Path()
        guard let first = routePoints.first else { return path }
        path.move(to: first)
        for point in routePoints.dropFirst() { path.addLine(to: point) }
        return path
    }

    private var routeProgress: Double {
        RecapVideoTimeline.progress(of: t, from: RecapVideoTimeline.routeStart, to: RecapVideoTimeline.routeEnd)
    }

    /// Index-based approximation of "where the line currently is" -- the
    /// route points are timestamped breadcrumb samples (roughly evenly
    /// spaced in time, not in distance), so walking the array by fraction
    /// is a close enough stand-in for true arc-length interpolation for a
    /// glow marker's position.
    private var cometPoint: CGPoint? {
        guard routePoints.count > 1 else { return routePoints.first }
        let index = Int((routeProgress * Double(routePoints.count - 1)).rounded())
        return routePoints[min(max(index, 0), routePoints.count - 1)]
    }

    @ViewBuilder
    private var routeLayer: some View {
        if routePoints.count > 1 {
            ZStack {
                routePath.trim(from: 0, to: routeProgress)
                    .stroke(Theme.gold.opacity(0.5), style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round))
                    .blur(radius: 16)

                routePath.trim(from: 0, to: routeProgress)
                    .stroke(Theme.gold, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))

                if let start = routePoints.first {
                    pin(at: start)
                }

                if routeProgress > 0, routeProgress < 1, let cometPoint {
                    Circle()
                        .fill(RadialGradient(colors: [.white, Theme.gold.opacity(0)], center: .center, startRadius: 0, endRadius: 22))
                        .frame(width: 44, height: 44)
                        .position(cometPoint)
                }

                if let end = routePoints.last {
                    let endFade = RecapVideoTimeline.progress(of: routeProgress, from: 0.985, to: 1)
                    if endFade > 0 {
                        pin(at: end).opacity(endFade)
                    }
                }
            }
        }
    }

    private func pin(at point: CGPoint) -> some View {
        ZStack {
            Circle().fill(Theme.gold).frame(width: 24, height: 24)
            Circle().fill(Theme.navy).frame(width: 11, height: 11)
        }
        .position(point)
    }

    // MARK: - Completion flourish

    private var flourishProgress: Double {
        RecapVideoTimeline.progress(of: t, from: RecapVideoTimeline.flourishStart, to: RecapVideoTimeline.flourishEnd)
    }

    @ViewBuilder
    private var flourishLayer: some View {
        if flourishProgress > 0, let end = routePoints.last {
            ZStack {
                Circle()
                    .stroke(Theme.gold.opacity(1 - flourishProgress), lineWidth: 3)
                    .frame(width: 26 + flourishProgress * 170, height: 26 + flourishProgress * 170)
                    .position(end)
                    .blur(radius: 1)

                ForEach(0..<10, id: \.self) { i in
                    let angle = Double(i) / 10.0 * 2 * Double.pi
                    let radius = flourishProgress * 100
                    let point = CGPoint(x: end.x + cos(angle) * radius, y: end.y + sin(angle) * radius)
                    Circle()
                        .fill(Theme.gold)
                        .frame(width: 6, height: 6)
                        .position(point)
                        .opacity(1 - flourishProgress)
                }
            }
        }
    }

    // MARK: - Stats

    private var statsProgress: Double {
        RecapVideoTimeline.progress(of: t, from: RecapVideoTimeline.statsStart, to: RecapVideoTimeline.statsEnd)
    }

    private var statsLayer: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.clear, Theme.navy.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                .frame(height: 520)
                .opacity(statsProgress)

            VStack(spacing: 18) {
                HStack(spacing: 36) {
                    statTile(value: trip.formattedDistance, label: String(localized: String.LocalizationValue("tripRecap.stats.distance")))
                    statTile(value: trip.formattedDuration, label: String(localized: String.LocalizationValue("tripRecap.stats.duration")))
                }

                if data.leveledUp {
                    Text(L("tripRecap.xp.leveledUp", data.levelAfter))
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Theme.gold)
                } else if data.xpDelta > 0 {
                    HStack(spacing: 4) {
                        Text("+")
                        Text("\(data.xpDelta)")
                        Text("tripRecap.xp.suffix")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 0.5, green: 0.85, blue: 0.6))
                }
            }
            .padding(.bottom, outroProgress > 0 ? 0 : 110)
            .opacity(statsProgress * (1 - outroProgress))
            .offset(y: (1 - statsProgress) * 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 46, weight: .heavy))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.system(size: 13, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.gold)
        }
    }

    // MARK: - Outro

    private var outroProgress: Double {
        RecapVideoTimeline.progress(of: t, from: RecapVideoTimeline.outroStart, to: 1)
    }

    @ViewBuilder
    private var outroLayer: some View {
        if outroProgress > 0 {
            ZStack {
                if let heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    Theme.navy
                }

                LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)

                VStack(spacing: 8) {
                    Text(trip.displayTitle)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                    Text(trip.dateLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.bottom, 190)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .opacity(outroProgress)
        }
    }

    // MARK: - Brand mark

    private var brandOpacity: Double {
        let fadeIn = RecapVideoTimeline.progress(of: t, from: 0, to: RecapVideoTimeline.introEnd)
        return fadeIn
    }

    private var brandMark: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("◈").foregroundStyle(Theme.gold)
                Text("Piri").foregroundStyle(.white)
            }
            .font(.system(size: 26, weight: .heavy))
            Capsule().fill(Theme.gold).frame(width: 28, height: 3)
        }
        .padding(.top, 76)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(brandOpacity)
    }
}

extension RecapVideoTimeline {
    static func progress(of t: Double, from start: Double, to end: Double) -> Double {
        guard end > start else { return t >= end ? 1 : 0 }
        return min(max((t - start) / (end - start), 0), 1)
    }
}
