import PhotosUI
import SwiftUI

/// Profile-photo picker -- same PhotosPicker → UIImage → JPEG-data-URI
/// pattern `UserPhotoSection.AddPOIPhotoSheet` uses for POI photos, but
/// resized to a small square first (an avatar never needs full camera
/// resolution, and staying well under Fastify's 1MB body limit / the
/// backend's own 700KB cap matters more here than for a one-off POI photo).
struct AvatarPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore

    @State private var galleryItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private static let maxDimension: CGFloat = 512

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Group {
                            if let selectedImage {
                                Image(uiImage: selectedImage).resizable().aspectRatio(contentMode: .fill)
                            } else if let avatarUrl = authStore.user?.avatarUrl {
                                DataURIImage(dataUri: avatarUrl)
                            } else {
                                Circle().fill(Color(.secondarySystemBackground))
                                    .overlay(Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(.secondary))
                            }
                        }
                        .frame(width: 140, height: 140)
                        .clipShape(Circle())
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    PhotosPicker(selection: $galleryItem, matching: .images) {
                        Label(String(localized: "profile.avatar.choosePhoto"), systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: galleryItem) { _, item in Task { await load(item) } }

                    if authStore.user?.avatarUrl != nil || selectedImage != nil {
                        Button(role: .destructive) {
                            selectedImage = nil
                            Task { await submit(dataUri: nil) }
                        } label: {
                            Label(String(localized: "profile.avatar.remove"), systemImage: "trash")
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.closedRed) }
                }
            }
            .navigationTitle(String(localized: "profile.avatar.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("common.save") { Task { await submitSelectedImage() } }
                            .disabled(selectedImage == nil)
                    }
                }
            }
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        selectedImage = image.resized(maxDimension: Self.maxDimension)
    }

    private func submitSelectedImage() async {
        guard let selectedImage, let jpeg = selectedImage.jpegData(compressionQuality: 0.7) else { return }
        await submit(dataUri: "data:image/jpeg;base64,\(jpeg.base64EncodedString())")
    }

    private func submit(dataUri: String?) async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await authStore.updateAvatar(dataUri)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension UIImage {
    /// Downscales so the longer side is at most `maxDimension`, preserving
    /// aspect ratio -- a no-op (returns `self`) if already smaller. Cropping
    /// to a square happens visually via `.clipShape(Circle())` at display
    /// time, not here, so the upload keeps whatever the user actually framed.
    func resized(maxDimension: CGFloat) -> UIImage {
        let longerSide = max(size.width, size.height)
        guard longerSide > maxDimension else { return self }
        let scale = maxDimension / longerSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
