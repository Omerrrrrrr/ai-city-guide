import SwiftUI

/// One-time "gezi özeti" shown right after a trip ends — `Trip` already
/// carries route geometry, distance/duration, breadcrumb, and photos; this
/// turns them into a payoff moment instead of the trip silently just
/// becoming a row in the Trips list. See the 2026-08-16 visual-design
/// research report, Phase 3 ("Gezi Özeti: Piri'nin Wrapped'i").
struct TripSummarySheet: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss

    private var dominantCategory: (icon: String, label: String)? { trip.dominantCategory }

    private var shareText: String {
        var lines = [L("tripSummary.share.headline", trip.displayTitle)]
        lines.append(L("tripSummary.share.stats", trip.formattedDistance, trip.formattedDuration, String(trip.stops.count)))
        if let dominantCategory {
            lines.append(L("tripSummary.share.dominant", dominantCategory.label))
        }
        lines.append(String(localized: "trips.share.signature"))
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    statsGrid
                    if let dominantCategory {
                        dominantCategoryCard(dominantCategory)
                    }
                    if !trip.photos.isEmpty {
                        photoCollage
                    }
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .background(Theme.navy.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up").foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .foregroundStyle(Theme.gold)
                        .fontWeight(.bold)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("✦").font(.system(size: 40)).foregroundStyle(Theme.gold)
            Text("tripSummary.title").font(.system(size: 30, weight: .heavy)).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(trip.displayTitle).font(.system(size: 16)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            statCard(value: trip.formattedDistance, labelKey: "trips.stat.distance")
            statCard(value: trip.formattedDuration, labelKey: "trips.stat.duration")
            statCard(value: "\(trip.stops.count)", labelKey: "trips.stat.stops")
        }
    }

    private func statCard(value: String, labelKey: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            Text(String(localized: String.LocalizationValue(labelKey)))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.08)))
    }

    private func dominantCategoryCard(_ category: (icon: String, label: String)) -> some View {
        HStack(spacing: 14) {
            Image(systemName: category.icon)
                .font(.system(size: 22))
                .foregroundStyle(Theme.navy)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.gold))
            VStack(alignment: .leading, spacing: 2) {
                Text("tripSummary.dominantCategory").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).textCase(.uppercase)
                Text(category.label).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.08)))
    }

    private var photoCollage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("tripSummary.photos").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).textCase(.uppercase)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(trip.photos) { photo in
                    CachedAsyncImage(url: URL(string: photo.uri), maxPixelSize: 300) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.white.opacity(0.08)
                    }
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
