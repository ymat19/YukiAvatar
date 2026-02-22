import AVFoundation
import Combine

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    @Published var isRunning = false

    private let videoOutput = AVCaptureVideoDataOutput()
    private let outputQueue = DispatchQueue(label: "camera.output")

    private var isConfigured = false

    func startSession() {
        guard !captureSession.isRunning else { return }

        if !isConfigured {
            captureSession.sessionPreset = .medium

            // Use front camera
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                print("❄️ Front camera not available")
                return
            }

            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }

            // Add video data output - needed for DockKit to detect faces
            videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                print("❄️ Video data output added")
            }
            isConfigured = true
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.isRunning = true
                print("❄️ Camera session started")
            }
        }
    }

    func stopSession() {
        guard captureSession.isRunning else { return }
        captureSession.stopRunning()
        isRunning = false
    }

    // AVCaptureVideoDataOutputSampleBufferDelegate
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Just receiving frames is enough for DockKit system tracking
    }
}
