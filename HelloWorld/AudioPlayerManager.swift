import Foundation
import AVFoundation
import Combine

/// Manages audio playback from base64-encoded WAV data received via WebSocket.
/// Also manages lip-sync animation timing.
class AudioPlayerManager: ObservableObject {
    @MainActor @Published var isPlaying = false
    @MainActor @Published var currentMouthFrame: Int = 0  // 0=closed, 1=half, 2=open
    
    private var audioPlayer: AVAudioPlayer?
    private var lipSyncTimer: Timer?
    private var sessionConfigured = false
    
    /// Called when playback finishes
    @MainActor var onPlaybackDone: (() -> Void)?
    
    /// Play audio from base64-encoded WAV data
    @MainActor
    func playAudioFromBase64(_ base64String: String) {
        guard let audioData = Data(base64Encoded: base64String) else {
            print("❄️ Audio: Failed to decode base64 (\(base64String.count) chars)")
            return
        }
        playAudio(data: audioData)
    }
    
    @MainActor
    private func playAudio(data: Data) {
        // Stop any current playback first (no callback for interrupted playback)
        if audioPlayer?.isPlaying == true {
            audioPlayer?.stop()
            stopLipSync()
        }
        do {
            let session = AVAudioSession.sharedInstance()
            if !sessionConfigured {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)
                sessionConfigured = true
            }
            // Ensure speaker output (can be reset by route changes)
            try session.overrideOutputAudioPort(.speaker)
            
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = AudioPlayerDelegateHandler.shared
            AudioPlayerDelegateHandler.shared.onFinish = { [weak self] in
                Task { @MainActor in
                    self?.stopLipSync()
                    self?.onPlaybackDone?()
                }
            }
            audioPlayer?.play()
            isPlaying = true
            startLipSync()
            print("❄️ Playing audio (\(data.count) bytes, \(String(format: "%.1f", audioPlayer?.duration ?? 0))s)")
        } catch {
            print("❄️ Audio play error: \(error)")
            isPlaying = false
        }
    }
    
    @MainActor
    private func startLipSync() {
        currentMouthFrame = 0
        var frameIndex = 0
        let sequence = [0, 1, 2, 1]
        lipSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                frameIndex += 1
                self?.currentMouthFrame = sequence[frameIndex % sequence.count]
            }
        }
    }
    
    @MainActor
    func stopLipSync() {
        lipSyncTimer?.invalidate()
        lipSyncTimer = nil
        currentMouthFrame = 0
        isPlaying = false
    }
}

/// AVAudioPlayerDelegate wrapper
class AudioPlayerDelegateHandler: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayerDelegateHandler()
    var onFinish: (() -> Void)?
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}
