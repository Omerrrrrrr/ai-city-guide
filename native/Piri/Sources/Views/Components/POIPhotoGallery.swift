import SwiftUI

/// Horizontal strip of every real photo available for a place — Wikipedia's
/// photo (if any) first per the user's explicit priority, then Tripadvisor's.
/// Never AI-generated or sourced elsewhere. Tapping one opens a full-screen
/// pager. Each thumbnail carries its own source label rather than one
/// blanket attribution, since a place can have photos from both providers
/// at once.
struct POIPhotoGallery: View {
    let photos: [POIPhoto]

    @Environment(AuthStore.self) private var authStore
    @State private var viewerIndex: PhotoIndex?

    var body: some View {
        if !photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            viewerIndex = PhotoIndex(value: index)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                CachedAsyncImage(url: URL(string: photo.url), maxPixelSize: 400) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color(.secondarySystemBackground)
                                }
                                .frame(width: 110, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                HStack(spacing: 4) {
                                    sourceLabel(photo.source)
                                    // Never for a paid account — it's
                                    // already getting Google's own photos
                                    // elsewhere in this same gallery
                                    // whenever Google has any; an "upgrade"
                                    // hint would be wrong, not just moot.
                                    if photo.source == .unsplash, authStore.user?.isPaidTier != true {
                                        lockBadge
                                    }
                                }
                                .padding(5)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .fullScreenCover(item: $viewerIndex) { wrapped in
                POIPhotoViewer(photos: photos, index: wrapped.value)
            }
        }
    }
}

/// Unsplash's API Terms (§9) require attributing both Unsplash and the
/// photographer by name, each linked — a generic "Unsplash" badge (what
/// Wikipedia/Tripadvisor use, and what this used to show for every source)
/// only satisfies "a link back," not "attribute ... the photographer."
/// Falls back to the plain badge when the photographer fields are missing
/// (shouldn't happen for a real Unsplash photo, but graceful regardless).
@ViewBuilder
private func attributionRow(for photo: POIPhoto) -> some View {
    if photo.source == .unsplash, let photographerName = photo.photographerName {
        HStack(spacing: 4) {
            Text("Photo by").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
            if let photographerUrl = photo.photographerUrl, let url = URL(string: photographerUrl) {
                Link(photographerName, destination: url)
                    .font(.system(size: 11, weight: .semibold))
            } else {
                Text(photographerName).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            }
            Text("on").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
            if let attributionUrl = photo.attributionUrl, let url = URL(string: attributionUrl) {
                Link("Unsplash", destination: url)
                    .font(.system(size: 11, weight: .semibold))
            } else {
                Text("Unsplash").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            }
        }
    } else if let attributionUrl = photo.attributionUrl, let url = URL(string: attributionUrl) {
        Link(destination: url) { sourceLabel(photo.source) }
    } else {
        sourceLabel(photo.source)
    }
}

private func sourceLabel(_ source: POIPhotoSource) -> some View {
    let label: String
    switch source {
    case .wikipedia: label = "Wikipedia"
    case .tripadvisor: label = "Tripadvisor"
    case .google: label = "Google"
    case .unsplash: label = "Unsplash"
    }
    return Text(label)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.55), in: Capsule())
}

/// Small upsell hint on a free-tier Unsplash photo: paid tiers get a real
/// Google Places photo of the place itself instead of this generic
/// category stock photo (see `/places/explain-poi`'s Google-photo
/// fallback) -- purely visual, doesn't gate anything on its own.
private var lockBadge: some View {
    Image(systemName: "lock.fill")
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.white)
        .padding(4)
        .background(.black.opacity(0.55), in: Circle())
}

private struct PhotoIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

private struct POIPhotoViewer: View {
    let photos: [POIPhoto]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { photoIndex, photo in
                    CachedAsyncImage(url: URL(string: photo.url), maxPixelSize: 1600) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Color.clear
                    }
                    .tag(photoIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                Text("\(index + 1) / \(photos.count)").foregroundStyle(.white)
                Spacer()
                if photos.indices.contains(index) {
                    attributionRow(for: photos[index])
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
}
