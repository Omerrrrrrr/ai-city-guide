import SwiftUI

/// The poster -- rendered standalone (no story chrome) via `ImageRenderer`
/// when the person taps Share, so what gets exported is exactly this
/// view's content, nothing from `StoryContainer`'s dots/close overlay.
struct RecapShareCard: View {
    let trip: Trip
    let data: TripRecapData
    var onShare: (() -> Void)?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.18, blue: 0.34), Theme.navy, Color(red: 0.02, green: 0.035, blue: 0.075), Color(red: 0.015, green: 0.025, blue: 0.05)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            RecapSkylineArt()
                .frame(height: 190)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 260)

            VStack(spacing: 14) {
                Text("tripRecap.share.eyebrow")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.gold)
                Text(trip.displayTitle)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(trip.dateLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack {
                Spacer()
                statStrip
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                if let onShare {
                    Button(action: onShare) {
                        Label("tripRecap.share.button", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.navy)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Theme.gold))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                footer
                    .padding(.bottom, 30)
            }
        }
    }

    private var statStrip: some View {
        HStack(spacing: 0) {
            statItem(value: "\(trip.stops.count)", unit: L("tripRecap.stats.unit.place"), label: "tripRecap.route.label")
            divider
            statItem(value: String(format: "%.1f", (trip.distanceMeters ?? 0) / 1000), unit: "km", label: "tripRecap.stats.distance")
            divider
            statItem(value: "+\(data.xpDelta)", unit: "xp", label: "tripRecap.share.xpLabel")
        }
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.14)))
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 34)
    }

    private func statItem(value: String, unit: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 20, weight: .heavy))
                Text(unit).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.gold)
            }
            .foregroundStyle(.white)
            Text(label).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.45)).tracking(0.4)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.north.circle")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
            Text("tripRecap.share.signature")
                .font(.system(size: 11.5, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}
