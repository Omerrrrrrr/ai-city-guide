import CoreLocation
import SwiftUI

/// Premium tier (Adım 4) rich POI data -- Google Places-backed rating,
/// price level, hours, and photo, gated behind `basic`/`pro`. Self-
/// contained (owns its own fetch state and paywall sheet) so any surface
/// can just drop this in with the POI's identity, same shape
/// `UserPhotoSection` uses for UGC photos.
///
/// **Not currently instantiated anywhere** (2026-08-23) -- `POIExplainSheet`
/// used to render this, but per the user's explicit request its two jobs
/// were absorbed into the main explain flow instead: Google's photos now
/// fold straight into `POIPhotoGallery` and its editorial summary/reviews
/// ground the AI body text server-side (`/places/explain-poi`), so a
/// second "Google details" card on that screen was redundant. This struct
/// (and its backing `POST /places/premium-details` route) is kept for a
/// possible future surface — e.g. `MapScreen`'s map-feature card — but
/// don't assume it's wired anywhere until you've actually grepped for a
/// call site; a stale assumption exactly like that already caused a false
/// "this is live" memory once this session.
struct PremiumDetailsSection: View {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let address: String?

    @Environment(AuthStore.self) private var authStore

    @State private var details: PremiumPlaceDetails?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var quotaExceeded = false
    @State private var showingPaywall = false

    var body: some View {
        Group {
            // Signed-out accounts can't call an authenticated endpoint at
            // all -- rather than a dead-end "sign in first" prompt here,
            // this section just doesn't render (the free-tier "Yükselt"
            // pitch already lives in ProfileScreen for a signed-in account,
            // and a signed-out one has no tier to upgrade yet anyway).
            if authStore.isSignedIn {
                content
            }
        }
        .sheet(isPresented: $showingPaywall) { PaywallScreen() }
    }

    @ViewBuilder
    private var content: some View {
        if let details {
            detailsCard(details)
        } else if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "premiumDetails.loading")).font(.footnote).foregroundStyle(.secondary)
            }
        } else if quotaExceeded {
            Text(String(localized: "premiumDetails.quotaExceeded")).font(.footnote).foregroundStyle(Theme.closedRed)
        } else if let errorMessage {
            Text(errorMessage).font(.footnote).foregroundStyle(Theme.closedRed)
        } else {
            // Locked teaser rather than a "fetch and see" button — a free
            // account will always 403 here, so the lock icon tells them
            // that up front instead of implying a free preview is coming.
            // Tapping still calls fetch(): a paid account gets the real
            // card, a free one gets routed straight to the paywall.
            Button {
                Task { await fetch() }
            } label: {
                Label(String(localized: "premiumDetails.locked"), systemImage: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
        }
    }

    private func detailsCard(_ details: PremiumPlaceDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let photoUrl = details.photoUrl, let url = URL(string: photoUrl) {
                CachedAsyncImage(url: url, maxPixelSize: 700) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(.secondarySystemBackground)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 10) {
                if let rating = details.rating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").foregroundStyle(Theme.gold)
                        Text(String(format: "%.1f", rating))
                        if let count = details.userRatingCount {
                            Text("(\(count))").foregroundStyle(.secondary)
                        }
                    }
                }
                if let priceLevel = details.priceLevel {
                    Text(priceLevelSymbol(priceLevel))
                }
                if let openNow = details.openNow {
                    Text(String(localized: openNow ? "premiumDetails.openNow" : "premiumDetails.closedNow"))
                        .foregroundStyle(openNow ? Theme.openGreen : Theme.closedRed)
                }
            }
            .font(.footnote.weight(.semibold))

            if let summary = details.editorialSummary {
                Text(summary).font(.footnote).foregroundStyle(.secondary)
            }
            if let hours = details.weekdayDescriptions {
                ForEach(hours, id: \.self) { line in
                    Text(line).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Google's `priceLevel` is a `PRICE_LEVEL_*` enum string, not a
    /// number -- `$`/`$$$` symbols read faster here than the raw name.
    private func priceLevelSymbol(_ level: String) -> String {
        switch level {
        case "PRICE_LEVEL_FREE": return String(localized: "premiumDetails.priceLevel.free")
        case "PRICE_LEVEL_INEXPENSIVE": return "$"
        case "PRICE_LEVEL_MODERATE": return "$$"
        case "PRICE_LEVEL_EXPENSIVE": return "$$$"
        case "PRICE_LEVEL_VERY_EXPENSIVE": return "$$$$"
        default: return ""
        }
    }

    private func fetch() async {
        guard let token = authStore.token else { return }
        isLoading = true
        errorMessage = nil
        quotaExceeded = false
        defer { isLoading = false }

        do {
            details = try await PlacesAPI.premiumDetails(
                PremiumDetailsRequest(name: name, lat: coordinate.latitude, lng: coordinate.longitude, address: address),
                token: token
            )
        } catch let APIError.server(status, _) where status == 403 {
            showingPaywall = true
        } catch let APIError.server(status, _) where status == 429 {
            quotaExceeded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
