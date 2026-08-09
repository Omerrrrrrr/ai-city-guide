import AVFoundation
import Observation
import UIKit

/// AVFoundation replacement for `expo-camera`'s `CameraView` in
/// `mobile/app/(tabs)/scan.tsx`. Owns the capture session; `CameraPreviewView`
/// (a thin `UIViewRepresentable`) just displays whatever this is running.
@Observable
final class CameraController: NSObject {
    private(set) var isAuthorized = false
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var isFlashOn = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.piriapp.piri.camera-session")
    private var photoContinuation: CheckedContinuation<Data?, Never>?

    func requestAuthorizationAndStart() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            isAuthorized = false
        }

        guard isAuthorized else { return }
        configureSessionIfNeeded()
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureSessionIfNeeded() {
        guard session.inputs.isEmpty else { return }
        sessionQueue.async { [weak self] in
            self?.buildSession(position: .back)
        }
    }

    private func buildSession(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
    }

    func flipCamera() {
        position = position == .back ? .front : .back
        let newPosition = position
        sessionQueue.async { [weak self] in
            self?.buildSession(position: newPosition)
        }
    }

    func toggleFlash() {
        isFlashOn.toggle()
    }

    func capturePhoto() async -> Data? {
        await withCheckedContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            if photoOutput.supportedFlashModes.contains(.on) {
                settings.flashMode = isFlashOn ? .on : .off
            }
            sessionQueue.async { [photoOutput] in
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        photoContinuation?.resume(returning: data)
        photoContinuation = nil
    }
}
