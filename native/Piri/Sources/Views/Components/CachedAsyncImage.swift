import ImageIO
import SwiftUI

/// Decoded-image cache keyed by URL + target size, shared across every
/// `CachedAsyncImage` instance so re-appearing views (scrolling a list back
/// into view, revisiting a screen) don't redecode the same photo.
actor ImageDownsampleCache {
    static let shared = ImageDownsampleCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

/// Drop-in replacement for SwiftUI's `AsyncImage` that decodes at a capped
/// pixel size via ImageIO instead of at the source image's native
/// resolution. Curated place photos are pulled directly from sources like
/// Wikipedia Commons, some of which are 15-20MB / many-megapixel originals —
/// plain `AsyncImage` decodes those at full size on every appearance
/// regardless of how small the view displays them, which was blocking the
/// main thread badly enough that taps stopped registering after switching
/// cities (a screen full of place cards all decoding multi-megabyte images
/// at once).
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var maxPixelSize: CGFloat = 900
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        uiImage = nil
        guard let url else { return }
        let key = "\(url.absoluteString)#\(Int(maxPixelSize))"
        if let cached = await ImageDownsampleCache.shared.image(for: key) {
            uiImage = cached
            return
        }
        let targetSize = maxPixelSize
        let downsampled: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: targetSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ] as CFDictionary
            guard let cgThumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
            return UIImage(cgImage: cgThumbnail)
        }.value
        guard !Task.isCancelled else { return }
        if let downsampled {
            await ImageDownsampleCache.shared.set(downsampled, for: key)
        }
        uiImage = downsampled
    }
}
