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
                    Text("directions.preview.loading").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            } else if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            } else if let result, let distance = result.distanceMeters, let duration = result.durationSeconds {
                HStack(spacing: 6) {
                    Text(formattedDistance(distance)).font(.subheadline.weight(.bold))
                    Text("·").foregroundStyle(Theme.secondaryText)
                    Text(formattedDuration(duration)).font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16))
        .task(id: profile) { await fetch() }
    }

    private func modeButton(_ candidate: RouteProfile) -> some View {
        let isSelected = profile == candidate
        return Button {
            guard !isSelected else { return }
            profile = candidate
            Haptics.light()
        } label: {
            Image(systemName: candidate.icon)
                .font(.footnote.weight(.semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(isSelected ? Theme.navy : Theme.secondaryText)
                .background {
                    if isSelected {
                        Circle().fill(Theme.gold)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: String.LocalizationValue(modeLabel(candidate))))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func modeLabel(_ profile: RouteProfile) -> String {
        switch profile {
        case .footWalking: "map.route.walking"
        case .drivingCar: "map.route.driving"
        case .cyclingRegular: "map.route.cycling"
        case .transit: "map.route.transit"
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
