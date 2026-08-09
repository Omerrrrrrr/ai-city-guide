import SwiftUI

/// Horizontal strip of every photo Tripadvisor has on file for a place —
/// real traveler/management photos, not AI-generated or sourced elsewhere.
/// Tapping one opens a full-screen pager. Attribution is required by
/// Tripadvisor's display terms regardless, but also just honest about where
/// the photos came from.
struct TripAdvisorPhotoGallery: View {
    let photoUrls: [String]

    @State private var viewerIndex: PhotoIndex?

    var body: some View {
        if !photoUrls.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photoUrls.enumerated()), id: \.offset) { index, urlString in
                            Button {
                                viewerIndex = PhotoIndex(value: index)
                            } label: {
                                CachedAsyncImage(url: URL(string: urlString), maxPixelSize: 400) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color(.secondarySystemBackground)
                                }
                                .frame(width: 110, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Tripadvisor").font(.caption2).foregroundStyle(.secondary)
            }
            .fullScreenCover(item: $viewerIndex) { wrapped in
                TripAdvisorPhotoViewer(photoUrls: photoUrls, index: wrapped.value)
            }
        }
    }
}

private struct PhotoIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

private struct TripAdvisorPhotoViewer: View {
    let photoUrls: [String]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photoUrls.enumerated()), id: \.offset) { photoIndex, urlString in
                    CachedAsyncImage(url: URL(string: urlString), maxPixelSize: 1600) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Color.clear
                    }
                    .tag(photoIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                Text("\(index + 1) / \(photoUrls.count)").foregroundStyle(.white)
                Spacer()
                Text("Tripadvisor").font(.caption).foregroundStyle(.white.opacity(0.7))
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
