import SwiftUI

/// Horizontal strip of every real photo available for a place — Wikipedia's
/// photo (if any) first per the user's explicit priority, then Tripadvisor's.
/// Never AI-generated or sourced elsewhere. Tapping one opens a full-screen
/// pager. Each thumbnail carries its own source label rather than one
/// blanket attribution, since a place can have photos from both providers
/// at once.
struct POIPhotoGallery: View {
    let photos: [POIPhoto]

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

                                sourceLabel(photo.source)
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

private func sourceLabel(_ source: POIPhotoSource) -> some View {
    Text(source == .wikipedia ? "Wikipedia" : "Tripadvisor")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.55), in: Capsule())
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
                    let photo = photos[index]
                    if let attributionUrl = photo.attributionUrl, let url = URL(string: attributionUrl) {
                        Link(destination: url) {
                            sourceLabel(photo.source)
                        }
                    } else {
                        sourceLabel(photo.source)
                    }
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
