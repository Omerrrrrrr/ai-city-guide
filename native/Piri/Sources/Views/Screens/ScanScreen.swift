import PhotosUI
import SwiftUI

private enum ScanState {
    case camera
    case loading(UIImage?)
    case result(IdentifyResult, UIImage)
    case error(String, UIImage?)
}

/// Port of `mobile/app/(tabs)/scan.tsx`.
struct ScanScreen: View {
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(PlacesQuery.self) private var placesQuery

    @State private var camera = CameraController()
    @State private var locationManager = LocationManager()
    @State private var state: ScanState = .camera
    @State private var matchedPlace: Place?
    @State private var galleryItem: PhotosPickerItem?
    @State private var isCapturing = false

    var body: some View {
        Group {
            switch state {
            case .camera:
                cameraView
            case .loading(let image):
                loadingView(image)
            case .result(let result, let image):
                resultView(result, image)
            case .error(let message, let image):
                errorView(message, image)
            }
        }
        .task { await camera.requestAuthorizationAndStart() }
        .onDisappear { camera.stop() }
    }

    private var cameraView: some View {
        ZStack {
            if camera.isAuthorized {
                CameraPreviewView(session: camera.session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack {
                // A live camera feed is almost never pure white, so this
                // white-on-viewfinder text/icon design normally has enough
                // contrast without help -- but a bright scene (sky, snow, a
                // white wall/ceiling, direct glare) is a real, if
                // occasional, case where it wouldn't. A soft black
                // gradient behind just the control bars (not the whole
                // frame, so the viewfinder itself stays clear) is the same
                // fix virtually every camera app already uses, and costs
                // nothing when the feed is already dark enough to not need it.
                HStack {
                    Button {
                        camera.toggleFlash()
                    } label: {
                        Image(systemName: camera.isFlashOn ? "bolt.fill" : "bolt.slash")
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.black.opacity(0.35)))
                    }
                    Spacer()
                    Text("scan.pointAtPlace").foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .background(
                    LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                )

                viewfinder

                HStack {
                    PhotosPicker(selection: $galleryItem, matching: .images) {
                        Text("scan.gallery").foregroundStyle(.white).font(.system(size: 14, weight: .semibold))
                    }
                    .frame(width: 70)

                    Button {
                        Task { await capture() }
                    } label: {
                        Circle()
                            .fill(.white)
                            .frame(width: 60, height: 60)
                            .padding(8)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                    }
                    .disabled(isCapturing || !camera.isAuthorized)

                    Button {
                        camera.flipCamera()
                    } label: {
                        Text("scan.flip").foregroundStyle(.white).font(.system(size: 14, weight: .semibold))
                    }
                    .frame(width: 70)
                }
                .padding(.horizontal, 40)
                .padding(.top, 16)
                .padding(.bottom, 48)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                )
            }

            if !camera.isAuthorized {
                VStack(spacing: 16) {
                    Text("scan.permission.title").font(.system(size: 24, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    Text("scan.permission.body").foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                    Button {
                        if camera.isPermissionDenied {
                            camera.openSystemSettings()
                        } else {
                            Task { await camera.requestAuthorizationAndStart() }
                        }
                    } label: {
                        Text(camera.isPermissionDenied ? "scan.permission.openSettings" : "scan.permission.allow")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.navy)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(Theme.gold))
                    }
                }
                .padding(32)
            }
        }
        .onChange(of: galleryItem) { _, newItem in
            Task { await handleGalleryPick(newItem) }
        }
    }

    private var viewfinder: some View {
        GeometryReader { proxy in
            let corner: CGFloat = 28
            ZStack {
                cornerMark.position(x: corner / 2, y: corner / 2)
                cornerMark.rotationEffect(.degrees(90)).position(x: proxy.size.width - corner / 2, y: corner / 2)
                cornerMark.rotationEffect(.degrees(-90)).position(x: corner / 2, y: proxy.size.height - corner / 2)
                cornerMark.rotationEffect(.degrees(180)).position(x: proxy.size.width - corner / 2, y: proxy.size.height - corner / 2)
            }
        }
        .padding(48)
    }

    private var cornerMark: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 28))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 28, y: 0))
        }
        .stroke(Theme.gold, lineWidth: 3)
        .frame(width: 28, height: 28)
    }

    private func loadingView(_ image: UIImage?) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill).ignoresSafeArea().blur(radius: 6)
            }
            Rectangle().fill(Theme.navy.opacity(image == nil ? 1 : 0.7)).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().tint(Theme.gold)
                Text("scan.looking").foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private func errorView(_ message: String, _ image: UIImage?) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill).ignoresSafeArea().blur(radius: 8)
            }
            Rectangle().fill(Theme.navy.opacity(0.82)).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.white.opacity(0.9))
                Text(message).foregroundStyle(.white.opacity(0.9)).multilineTextAlignment(.center)
                Button {
                    reset()
                } label: {
                    Text("common.tryAgain")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Theme.gold))
                }
            }
            .padding(32)
        }
    }

    private func resultView(_ result: IdentifyResult, _ image: UIImage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Text(result.title).font(.system(size: 26, weight: .heavy))
                    Text(result.subtitle).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                    Divider()
                    Text(result.explanation).font(.system(size: 16))
                    ForEach(result.highlights, id: \.self) { highlight in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(Theme.gold).frame(width: 7, height: 7).padding(.top, 8)
                            Text(highlight).font(.system(size: 15))
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))

                HStack(spacing: 12) {
                    ShareLink(item: L("scan.shareMessage", result.title, result.subtitle, result.explanation)) {
                        Text("common.share")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.3), lineWidth: 1.5))
                    }
                    NavigationLink(destination: AIScreen(initialQuery: L("scan.askMoreQuery", result.title))) {
                        Text("scan.askMore")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.navy))
                    }
                }

                if let matchedPlaceId = result.matchedPlaceId {
                    if let matchedPlace {
                        NavigationLink(destination: PlaceDetailScreen(placeId: matchedPlace.id)) {
                            matchedPlaceCard(matchedPlace)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: PlaceDetailScreen(placeId: matchedPlaceId)) {
                            Text("scan.viewDetailsInPiri")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.gold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.gold.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold, lineWidth: 1.5))
                        }
                    }
                }

                Button("scan.scanAnother") { reset() }
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(20)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Button("scan.scanAgainHeader") { reset() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .piriGlassSurface()
        }
        .task {
            if let matchedPlaceId = result.matchedPlaceId {
                matchedPlace = try? await PlacesAPI.fetchPlace(id: matchedPlaceId)
            }
        }
    }

    private func matchedPlaceCard(_ place: Place) -> some View {
        let status = PlaceHours.openStatus(for: place)
        let open = PlaceHours.isOpen(status)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                PlaceImageView(place: place).frame(height: 150)
                Text("scan.inPiri")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(10)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(place.name).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(status.shortLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(open ? Color(red: 0.43, green: 0.98, blue: 0.69) : Color(red: 1, green: 0.65, blue: 0.63))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill((open ? Color.green : Color.red).opacity(0.2)))
                Text("scan.viewFullDetails").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gold)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.navy)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.gold, lineWidth: 1.5))
    }

    private func reset() {
        state = .camera
        matchedPlace = nil
    }

    private func capture() async {
        guard !isCapturing else { return }
        Haptics.medium()
        isCapturing = true
        defer { isCapturing = false }

        guard let data = await camera.capturePhoto(), let image = UIImage(data: data) else {
            state = .error(String(localized: "scan.errorPhoto"), nil)
            return
        }
        await process(image: image)
    }

    private func handleGalleryPick(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        galleryItem = nil
        await process(image: image)
    }

    private func process(image: UIImage) async {
        state = .loading(image)
        let location = await locationManager.currentLocationOnce()
        guard let jpeg = image.jpegData(compressionQuality: 0.6) else {
            state = .error(String(localized: "scan.errorIdentify"), image)
            return
        }

        let profile = userProfileStore.profile
        let request = IdentifyRequest(
            imageBase64: jpeg.base64EncodedString(),
            mimeType: "image/jpeg",
            lat: location?.latitude,
            lng: location?.longitude,
            locale: Locale.current.language.languageCode?.identifier,
            userProfile: PersonalizationProfile(
                name: profile.name,
                profession: profile.professionText,
                interests: profile.interestsText,
                faith: profile.faith?.rawValue,
                budget: profile.budget?.rawValue,
                groupType: profile.groupType?.rawValue,
                pace: profile.pace?.rawValue
            )
        )

        do {
            let result = try await PlacesAPI.identify(request)
            state = .result(result, image)
        } catch {
            state = .error(error.localizedDescription, image)
        }
    }
}
