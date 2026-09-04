import CoreLocation
import SwiftUI

/// Compact "get directions" preview for a single place -- distance/duration
/// for the currently-picked transport mode, with a small mode switcher.
/// Lives inline in whatever sheet/card is already showing one place
/// (`POIExplainSheet`, `MapScreen`'s map-feature card) rather than handing
/// off to Route Mode's full multi-stop flow. Reuses the exact same fetch
/// logic Route Mode uses (`RoutesAPI.directions` / `TransitDirections`),
/// just against a single origin→destination pair -- owns its own
/// `LocationManager`, matching every other screen's convention (there's no
/// shared/injected instance in this app; `HomeScreen`, `MapScreen`, etc.
/// each create their own).
struct DirectionsPreview: View {
    let destination: CLLocationCoordinate2D

    @State private var locationManager = LocationManager()
    @State private var profile: RouteProfile = .footWalking
    @State private var result: DirectionsResult?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(RouteProfile.allCases, id: \.self) { candidate in
                    modeButton(candidate)
                }
                Spacer()
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("directions.preview.loading").font(.footnote).foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(Theme.closedRed)
            } else if let result, let distance = result.distanceMeters, let duration = result.durationSeconds {
                HStack(spacing: 6) {
                    Text(formattedDistance(distance)).font(.subheadline.weight(.bold))
                    Text("·").foregroundStyle(.secondary)
                    Text(formattedDuration(duration)).font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Theme.navy)
            }
        }
        .task { await fetch() }
    }

    private func modeButton(_ candidate: RouteProfile) -> some View {
        let isSelected = profile == candidate
        return Button {
            guard !isSelected else { return }
            profile = candidate
            Haptics.light()
            Task { await fetch() }
        } label: {
            Image(systemName: candidate.icon)
                .font(.footnote.weight(.semibold))
                .frame(width: 34, height: 34)
                // Reversed from the original (every mode circled the same
                // way, selected or not, reading as no distinction at all
                // once both fills ended up equally dark) -- only the
                // selected mode gets a circle now, in gold (this component
                // is shared between the navy sheet and Map's still-light
                // inline card, so it needs a fill that reads on both).
                .foregroundStyle(isSelected ? Theme.navy : .secondary)
                .background {
                    if isSelected {
                        Circle().fill(Theme.gold)
                    }
                }
        }
    }

    private func fetch() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let origin = await locationManager.currentLocationOnce() else {
            errorMessage = String(localized: "directions.preview.noLocation")
            return
        }

        let coordinates = [
            PlaceCoordinate(lat: origin.latitude, lng: origin.longitude),
            PlaceCoordinate(lat: destination.latitude, lng: destination.longitude),
        ]

        do {
            result = profile == .transit
                ? try await TransitDirections.fetchMultiLeg(stops: coordinates)
                : try await RoutesAPI.directions(coordinates: coordinates, profile: profile)
        } catch is TransitDirectionsError {
            errorMessage = String(localized: "map.route.transitFailed")
        } catch {
            errorMessage = String(localized: "map.route.failed")
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let minutes = max(1, Int(seconds / 60))
        if minutes < 60 { return L("directions.preview.minutes", minutes) }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining > 0 ? L("directions.preview.hoursMinutes", hours, remaining) : L("directions.preview.hours", hours)
    }
}
