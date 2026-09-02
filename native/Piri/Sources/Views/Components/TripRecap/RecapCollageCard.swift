import SwiftUI

/// A photo collage -- one large frame plus up to three smaller ones below,
/// with a "+N" tile standing in for the rest -- shown only when a trip has
/// enough photos (2+, see `TripRecapView.pages`) for a collage to say more
/// than `RecapHighlightCard`'s single hero photo already does.
struct RecapCollageCard: View {
    let trip: Trip

    private var photos: [TripPhoto] { trip.photos }

    var body: some View {
        ZStack {
            Theme.navy.ignoresSafeArea()

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    Text("tripRecap.collage.badge")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.gold))

                    if let hero = photos.first {
                        collageTile(hero, height: 220)
                    }

                    if photos.count > 1 {
                        let rest = Array(photos.dropFirst().prefix(3))
                        let remaining = photos.count - 1 - rest.count
                        HStack(spacing: 8) {
                            ForEach(Array(rest.enumerated()), id: \.offset) { index, photo in
                                if index == rest.count - 1, remaining > 0 {
                                    moreTile(count: remaining, photo: photo)
                                } else {
                                    collageTile(photo, height: 90)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 60)
            }
        }
    }

    private func collageTile(_ photo: TripPhoto, height: CGFloat) -> some View {
        CachedAsyncImage(url: URL(string: photo.uri), maxPixelSize: 800) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Theme.navy.opacity(0.5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func moreTile(count: Int, photo: TripPhoto) -> some View {
        ZStack {
            collageTile(photo, height: 90)
            RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.55))
            Text("+\(count)").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
        }
    }
}
