import SwiftUI

/// Port of `mobile/components/place-image.tsx`.
struct PlaceImageView: View {
    let place: Place
    var cornerRadius: CGFloat = 0

    var body: some View {
        Group {
            if place.image.verified, let url = URL(string: place.imageUrl) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        // `.fill`-mode AsyncImage sizes itself from the image's own aspect
        // ratio when only one dimension is constrained by the caller (e.g.
        // `.frame(height: 340)` alone) — reporting a wider-than-screen ideal
        // width upward that stretches every ancestor container (ScrollView
        // included) rather than actually filling the given frame. Forcing
        // both dimensions to expand here means callers only ever need to
        // constrain the dimension(s) they care about.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Text(Categories.emoji(for: place.category))
                .font(.system(size: 28))
        }
    }
}

/// Port of `mobile/components/skeleton.tsx`'s `SkeletonBox` — a plain pulsing
/// placeholder used while data is loading.
struct SkeletonBox: View {
    var cornerRadius: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.secondarySystemBackground))
            .opacity(pulse ? 0.5 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
