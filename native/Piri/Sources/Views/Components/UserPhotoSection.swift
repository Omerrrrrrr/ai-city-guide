import CoreLocation
import PhotosUI
import SwiftUI

/// User-submitted photos for a POI (Apple Guideline 1.2 UGC) -- separate
/// from `POIPhotoGallery`'s Wikipedia/Tripadvisor/Unsplash strip since
/// these carry a different identity (an uploader, a caption, report/block
/// actions) rather than just a licensed-source attribution.
struct UserPhotoSection: View {
    let poiName: String
    let coordinate: CLLocationCoordinate2D
    @Binding var photos: [UserSubmittedPhoto]

    @Environment(AuthStore.self) private var authStore
    @State private var viewerIndex: PhotoIndexWrap?
    @State private var showingAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("poiPhotos.userSubmitted.title").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            viewerIndex = PhotoIndexWrap(value: index)
                        } label: {
                            DataURIImage(dataUri: photo.photoUrl)
                                .frame(width: 90, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    addButton
                }
            }
        }
        .fullScreenCover(item: $viewerIndex) { wrapped in
            UserPhotoViewer(photos: $photos, index: wrapped.value)
        }
        .sheet(isPresented: $showingAdd) {
            AddPOIPhotoSheet(poiName: poiName, coordinate: coordinate) {
                Task { await refresh() }
            }
        }
    }

    private var addButton: some View {
        Button {
            Haptics.light()
            showingAdd = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "camera.fill").font(.title3)
                Text("poiPhotos.add").font(.caption2)
            }
            .frame(width: 90, height: 90)
            .foregroundStyle(Theme.gold)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func refresh() async {
        guard let token = authStore.token else { return }
        photos = (try? await PhotosAPI.fetchPhotos(name: poiName, lat: coordinate.latitude, lng: coordinate.longitude, token: token)) ?? photos
    }
}

private struct PhotoIndexWrap: Identifiable {
    let value: Int
    var id: Int { value }
}

/// Full-screen pager for user-submitted photos, with report/block actions
/// scoped to whichever photo is currently on screen. Mutates the shared
/// `photos` binding directly (rather than owning its own copy) so a block
/// immediately drops that uploader's photos from both this pager and the
/// strip behind it -- matching the backend's own visibility filter in
/// `GET /poi/photos`.
private struct UserPhotoViewer: View {
    @Binding var photos: [UserSubmittedPhoto]
    @State var index: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore

    @State private var showingReportReason = false
    @State private var reportReason = ""
    @State private var showingBlockConfirm = false
    @State private var actionError: String?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if photos.isEmpty {
                Color.clear.onAppear { dismiss() }
            } else {
                TabView(selection: $index) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { photoIndex, photo in
                        VStack(spacing: 12) {
                            Spacer()
                            DataURIImage(dataUri: photo.photoUrl)
                                .aspectRatio(contentMode: .fit)
                            if let caption = photo.caption, !caption.isEmpty {
                                Text(caption).foregroundStyle(.white).font(.footnote).padding(.horizontal)
                            }
                            Spacer()
                        }
                        .tag(photoIndex)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            HStack {
                Text("\(min(index + 1, photos.count)) / \(photos.count)").foregroundStyle(.white)
                Spacer()
                if photos.indices.contains(index), photos[index].userId != authStore.user?.id {
                    Menu {
                        Button {
                            reportReason = ""
                            showingReportReason = true
                        } label: {
                            Label("poiPhotos.report", systemImage: "flag")
                        }
                        Button(role: .destructive) {
                            showingBlockConfirm = true
                        } label: {
                            Label("poiPhotos.block", systemImage: "hand.raised")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(.white)
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
        .alert("poiPhotos.report.title", isPresented: $showingReportReason) {
            TextField("poiPhotos.report.reasonPlaceholder", text: $reportReason)
            Button("common.cancel", role: .cancel) {}
            Button("poiPhotos.report.submit") { Task { await report() } }
        }
        .alert("poiPhotos.block.confirmTitle", isPresented: $showingBlockConfirm) {
            Button("common.cancel", role: .cancel) {}
            Button("poiPhotos.block.confirm", role: .destructive) { Task { await block() } }
        } message: {
            Text("poiPhotos.block.confirmMessage")
        }
        .alert("common.error", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("common.ok") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private func report() async {
        guard let token = authStore.token, photos.indices.contains(index) else { return }
        let trimmed = reportReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await PhotosAPI.reportPhoto(photoId: photos[index].id, reason: trimmed, token: token)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func block() async {
        guard let token = authStore.token, photos.indices.contains(index) else { return }
        let blockedUserId = photos[index].userId
        do {
            try await PhotosAPI.blockUser(id: blockedUserId, token: token)
            photos.removeAll { $0.userId == blockedUserId }
            if index >= photos.count { index = max(0, photos.count - 1) }
        } catch {
            actionError = error.localizedDescription
        }
    }
}

/// Pick-and-upload sheet -- the only way to submit a new UGC photo.
/// `onUploaded` fires only on an approved submission (a rejection keeps
/// the sheet open with `rejectionReason` shown, since the user should
/// know why rather than have it vanish silently).
private struct AddPOIPhotoSheet: View {
    let poiName: String
    let coordinate: CLLocationCoordinate2D
    let onUploaded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore

    @State private var galleryItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var caption = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var rejectionReason: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 240)
                    }
                    PhotosPicker(selection: $galleryItem, matching: .images) {
                        Label(
                            selectedImage == nil ? String(localized: "poiPhotos.choosePhoto") : String(localized: "poiPhotos.changePhoto"),
                            systemImage: "photo.on.rectangle"
                        )
                    }
                    .onChange(of: galleryItem) { _, item in Task { await load(item) } }
                }
                Section {
                    TextField(String(localized: "poiPhotos.captionPlaceholder"), text: $caption, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.closedRed) }
                }
                if let rejectionReason {
                    Section { Text(rejectionReason).foregroundStyle(Theme.closedRed) }
                }
            }
            .navigationTitle(String(localized: "poiPhotos.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("poiPhotos.submit") { Task { await submit() } }
                            .disabled(selectedImage == nil)
                    }
                }
            }
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        selectedImage = UIImage(data: data)
    }

    private func submit() async {
        guard let token = authStore.token, let selectedImage, let jpeg = selectedImage.jpegData(compressionQuality: 0.6) else { return }
        isSubmitting = true
        errorMessage = nil
        rejectionReason = nil
        defer { isSubmitting = false }

        let dataUri = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = PhotoUploadRequest(
            poiName: poiName,
            lat: coordinate.latitude,
            lng: coordinate.longitude,
            photoUrl: dataUri,
            caption: trimmedCaption.isEmpty ? nil : trimmedCaption
        )

        do {
            let response = try await PhotosAPI.uploadPhoto(request, token: token)
            if response.status == "rejected" {
                rejectionReason = response.moderationReason ?? String(localized: "poiPhotos.rejectedGeneric")
            } else {
                onUploaded()
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
