import SwiftUI

/// The first real photo available for a place — Wikipedia's (if any) per the
/// user's explicit priority, then Tripadvisor's, never AI-generated — shown
/// full-bleed as a hero, with any remaining photos as a filmstrip of small
/// thumbnails below it. Tapping either opens the same full-screen pager at
/// the right index. Each thumbnail (and the hero) carries its own source
/// label rather than one blanket attribution, since a place can have photos
/// from both providers at once. Only ever embedded by `POIExplainSheet`
/// (verified — no other call site), so the hero's full-bleed sizing doesn't
/// need to guard against some other, more constrained context.
struct POIPhotoGallery<Trailing: View>: View {
    let photos: [POIPhoto]
    /// `true` only for `POIExplainSheet`'s real full-screen presentation --
    /// see `POIExplainContent.extendsPhotoUnderStatusBar`'s own doc comment.
    var extendsHeroUnderStatusBar: Bool = false
    /// Appended as extra tiles at the end of the same filmstrip row as the
    /// Tripadvisor/Wikipedia thumbnails -- lets `POIExplainContent` fold its
    /// user-submitted-photos strip and "add a photo" button into this one
    /// strip instead of a second, separately-labeled row underneath it.
    @ViewBuilder let trailing: () -> Trailing

    @Environment(AuthStore.self) private var authStore
    @State private var viewerIndex: PhotoIndex?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hero = photos.first {
                heroPhoto(hero, index: 0)
                    .ignoresSafeArea(edges: extendsHeroUnderStatusBar ? .top : [])
            }
            // Always shown, even with zero official photos -- `trailing`
            // (the user-submitted strip + add-photo button) needs to stay
            // reachable regardless, so a place with no Tripadvisor/Wikipedia
            // photo at all doesn't lose its only way to contribute one.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated().dropFirst()), id: \.element.id) { index, photo in
                        thumbnail(photo, index: index)
                    }
                    trailing()
                }
                .padding(.horizontal, 20)
            }
        }
        .fullScreenCover(item: $viewerIndex) { wrapped in
            POIPhotoViewer(photos: photos, index: wrapped.value)
        }
    }

    private func heroPhoto(_ photo: POIPhoto, index: Int) -> some View {
        Button {
            viewerIndex = PhotoIndex(value: index)
        } label: {
            ZStack(alignment: .bottomLeading) {
                // System-adaptive, not `Theme.cardFill`/`Theme.navyLight` --
                // this gallery is shared by `POIExplainSheet` (forced dark)
                // and `MapScreen.mapFeatureCard`'s translucent inline card,
                // which stays on the system's own Light/Dark rendering. A
                // hardcoded navy placeholder here looked like a stray dark
                // box floating in that still-light glass card.
                CachedAsyncImage(url: URL(string: photo.url), maxPixelSize: 800) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color(.secondarySystemBackground)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipped()

                photoBadges(photo).padding(10)
            }
        }
        .buttonStyle(.plain)
    }

    private func thumbnail(_ photo: POIPhoto, index: Int) -> some View {
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

                photoBadges(photo).padding(5)
            }
        }
        .buttonStyle(.plain)
    }

    private func photoBadges(_ photo: POIPhoto) -> some View {
        HStack(spacing: 4) {
            sourceLabel(photo.source)
            // Never for a paid account — it's already getting Google's own
            // photos elsewhere in this same gallery whenever Google has
            // any; an "upgrade" hint would be wrong, not just moot.
            if photo.source == .unsplash, authStore.user?.isPaidTier != true {
                lockBadge
            }
        }
    }
}

extension POIPhotoGallery where Trailing == EmptyView {
    init(photos: [POIPhoto], extendsHeroUnderStatusBar: Bool = false) {
        self.photos = photos
        self.extendsHeroUnderStatusBar = extendsHeroUnderStatusBar
        self.trailing = { EmptyView() }
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

    // Live-reported bugs, both traced to the same cause: the close button's
    // tap target used to be exactly the glyph's own tiny frame (no padding,
    // no contentShape), which read as "the X doesn't work" as often as "hard
    // to tap." A drag-to-dismiss gesture is the requested second way out.
    @State private var dragOffset: CGFloat = 0
    private let dismissDragThreshold: CGFloat = 120

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
                .opacity(Double(1 - min(abs(dragOffset) / 600, 0.6)))
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
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Vertical-dominant only, so a horizontal swipe
                        // between photos in the pager still works normally.
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        if abs(value.translation.height) > dismissDragThreshold {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                        }
                    }
            )

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
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }
}
