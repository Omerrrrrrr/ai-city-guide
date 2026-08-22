import CoreLocation
import SwiftUI

/// The trip's most memorable frame -- its first captured photo, full-bleed,
/// captioned with whichever stop it was taken nearest to (by straight-line
/// distance). Falls back to the trip's first stop when there's no photo at
/// all, rather than inventing a "favorite by time spent" number the app
/// doesn't actually track.
struct RecapHighlightCard: View {
    let trip: Trip

    private var featuredPhoto: TripPhoto? { trip.photos.first }

    private var nearestStopName: String? {
        guard let photo = featuredPhoto, let plat = photo.lat, let plng = photo.lng else {
            return trip.stops.first?.name
        }
        let photoLocation = CLLocation(latitude: plat, longitude: plng)
        return trip.stops.min(by: { a, b in
            CLLocation(latitude: a.lat, longitude: a.lng).distance(from: photoLocation)
                < CLLocation(latitude: b.lat, longitude: b.lng).distance(from: photoLocation)
        })?.name
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let featuredPhoto {
                CachedAsyncImage(url: URL(string: featuredPhoto.uri), maxPixelSize: 1200) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Theme.navy
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                Theme.navy.ignoresSafeArea()
            }

            LinearGradient(colors: [.clear, .clear, .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text("tripRecap.highlight.badge")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.gold))

                    if let nearestStopName {
                        Text(nearestStopName)
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 46)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
