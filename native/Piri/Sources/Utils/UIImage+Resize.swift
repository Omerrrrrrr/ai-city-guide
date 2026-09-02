import UIKit

extension UIImage {
    /// Downscales so the longer side is at most `maxDimension`, preserving
    /// aspect ratio -- a no-op (returns `self`) if already smaller. Shared by
    /// every flow that uploads a photo as base64 JSON (`AvatarPickerSheet`,
    /// `ScanScreen`) -- a real device's full camera-sensor resolution (e.g.
    /// 4032x3024) JPEG-compresses to well over Fastify's default 1MB body
    /// limit even at reduced quality, confirmed live 2026-09-02 ("Request
    /// body is too large" on every real camera scan, `ScanScreen` skipped
    /// this resize step entirely before this fix).
    func resized(maxDimension: CGFloat) -> UIImage {
        let longerSide = max(size.width, size.height)
        guard longerSide > maxDimension else { return self }
        let scale = maxDimension / longerSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
