import SwiftUI

/// 2x2 grid of the trip's headline numbers.
struct RecapStatsCard: View {
    let trip: Trip

    private var distanceKm: Double { (trip.distanceMeters ?? 0) / 1000 }
    private var days: Int {
        guard let endedAt = trip.endedAt else { return 1 }
        let seconds = (endedAt - trip.startedAt) / 1000
        return max(1, Int(ceil(seconds / 86400)))
    }

    var body: some View {
        ZStack {
            Theme.navy.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                Text("tripRecap.stats.heading")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    statTile(icon: "point.topleft.down.curvedto.point.bottomright.up", value: distanceKm, format: { String(format: "%.1f", $0) }, unit: "km", labelKey: "tripRecap.stats.distance")
                    statTile(icon: "calendar", value: Double(days), format: { "\(Int($0))" }, unit: L("tripRecap.stats.unit.day"), labelKey: "tripRecap.stats.duration")
                    statTile(icon: "mappin.and.ellipse", value: Double(trip.stops.count), format: { "\(Int($0))" }, unit: L("tripRecap.stats.unit.place"), labelKey: "tripRecap.stats.visited")
                    statTile(icon: "photo.on.rectangle", value: Double(trip.photos.count), format: { "\(Int($0))" }, unit: L("tripRecap.stats.unit.photo"), labelKey: "tripRecap.stats.photos")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 100)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func statTile(icon: String, value: Double, format: @escaping (Double) -> String, unit: String, labelKey: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.gold)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                CountUpNumber(value: value, format: format)
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.gold)
            }
            Text(String(localized: String.LocalizationValue(labelKey)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1)))
    }
}
