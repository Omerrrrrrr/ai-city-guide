import SwiftUI

/// Displays a user-submitted photo, which is either a `data:` URI (base64,
/// no network fetch -- the interim storage before R2 was wired up, or
/// whenever R2 isn't configured server-side, see r2.ts) or a real R2
/// `https://` URL. Branches per-instance since old rows and new rows can
/// legitimately differ in which one they hold.
struct DataURIImage: View {
    let dataUri: String

    var body: some View {
        if dataUri.hasPrefix("data:") {
            Base64Image(dataUri: dataUri)
        } else {
            CachedAsyncImage(url: URL(string: dataUri), maxPixelSize: 900) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(.secondarySystemBackground)
            }
        }
    }
}

private struct Base64Image: View {
    let dataUri: String

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color(.secondarySystemBackground)
            }
        }
        .task(id: dataUri) {
            uiImage = await Self.decode(dataUri)
        }
    }

    private static func decode(_ dataUri: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let commaIndex = dataUri.firstIndex(of: ",") else { return nil }
            let base64 = dataUri[dataUri.index(after: commaIndex)...]
            guard let data = Data(base64Encoded: String(base64)) else { return nil }
            return UIImage(data: data)
        }.value
    }
}
