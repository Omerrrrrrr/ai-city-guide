import Foundation

/// RN's `ImagePicker` hands `attachTripPhoto` (`mobile/app/(tabs)/map.tsx`) a
/// local file `uri` for free; native has no equivalent picker output for the
/// camera-capture path, so this writes the captured/picked JPEG to disk
/// itself and returns a stable `file://` URL for `TripPhoto.uri`.
enum TripPhotoStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TripPhotos", isDirectory: true)
    }

    static func save(_ data: Data) -> URL? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
