import SwiftUI
import Combine
import os.log

private let exprLogger = Logger(subsystem: "com.ymat19.HelloWorld", category: "Expression")

enum Expression: String, CaseIterable {
    case normal
    case talking
    case blink
    case happy
    case sad
    case surprised
    case angry
    case shy
    case smug
    case love
    case confused
    case crying
    case excited
    case scared
    case sleepy
    case wink
    case thinking
    case rage
    case pout
    case greeting
    case peace
    case eat
    case explain
    case shh
    case dizzy
    case sleeping
    case idle_snack
    case idle_singing
    case idle_bored
    case listening
    case sending

    var imageName: String { rawValue }
}

struct CommandResult {
    var expression: Expression?
    var gesture: String?
    var orientation: String?
    var duration: Double?
    var rawOrientation: (pitch: Double, yaw: Double, roll: Double)?
    var v3Orientation: (pitch: Double, yaw: Double, roll: Double)?
    var velocity: (pitch: Double, yaw: Double, roll: Double, durationMs: Int)?
    var speech: String?
    var speechDuration: Double?
    var motion: String?
    var diagnostic: Bool = false
    var audioBase64: String?
    var musicPlaying: Bool?
}

class ExpressionManager: ObservableObject {
    @Published var currentExpression: Expression = .normal
    @Published var isBlinking = false
    /// Lip-sync mouth frame: 0=closed, 1=half-open, 2=open
    @Published var mouthFrame: Int = 0

    private var blinkTimer: Timer?
    private var autoBlinkEnabled = true

    /// Image name considering lip-sync override
    var currentImageName: String {
        if mouthFrame > 0 && (currentExpression == .normal || currentExpression == .talking) {
            return "talking_\(mouthFrame)"
        }
        return currentExpression.imageName
    }

    func startAutoBlinking() {
        autoBlinkEnabled = true
        scheduleNextBlink()
    }

    func stopAutoBlinking() {
        autoBlinkEnabled = false
        blinkTimer?.invalidate()
    }

    private func scheduleNextBlink() {
        guard autoBlinkEnabled else { return }
        let interval = Double.random(in: 2.5...5.0)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performBlink()
            }
        }
    }

    private func performBlink() {
        guard currentExpression == .normal && mouthFrame == 0 else {
            scheduleNextBlink()
            return
        }
        let returnTo = currentExpression
        isBlinking = true
        currentExpression = .blink
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.isBlinking = false
            if self?.currentExpression == .blink {
                self?.currentExpression = returnTo
            }
            self?.scheduleNextBlink()
        }
    }

    func setExpression(_ expression: Expression, caller: String = #function, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        exprLogger.notice("❄️ Expression: \(self.currentExpression.rawValue, privacy: .public) → \(expression.rawValue, privacy: .public) [\(fileName, privacy: .public):\(line, privacy: .public) \(caller, privacy: .public)]")
        currentExpression = expression
    }

    func handleCommand(_ command: String) -> CommandResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Simple expression name
        if let expr = Expression(rawValue: trimmed) {
            setExpression(expr)
            return CommandResult(expression: expr)
        }

        // JSON command
        if let data = command.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var result = CommandResult()

            if let exprStr = json["expression"] as? String,
               let expr = Expression(rawValue: exprStr) {
                // Only set expression immediately if NOT queued (no speech/audio).
                // When speech/audio is present, expression will be set by SpeechQueueManager.onProcessItem
                // to avoid premature expression flash before the audio plays.
                let hasAudio = json["audio"] != nil || json["speech"] != nil
                if !hasAudio {
                    setExpression(expr)
                }
                result.expression = expr
            }
            if let g = json["gesture"] as? String { result.gesture = g }
            if let o = json["orientation"] as? String { result.orientation = o }
            if let d = json["duration"] as? Double { result.duration = d }
            if let p = json["pitch"] as? Double,
               let y = json["yaw"] as? Double,
               let r = json["roll"] as? Double {
                let mode = json["mode"] as? String ?? "rotation3d"
                if mode == "v3" {
                    result.v3Orientation = (pitch: p, yaw: y, roll: r)
                } else if mode == "velocity" {
                    let ms = json["durationMs"] as? Int ?? 1000
                    result.velocity = (pitch: p, yaw: y, roll: r, durationMs: ms)
                } else {
                    result.rawOrientation = (pitch: p, yaw: y, roll: r)
                }
            }

            if let s = json["speech"] as? String { result.speech = s }
            if let sd = json["speechDuration"] as? Double { result.speechDuration = sd }
            if let m = json["motion"] as? String { result.motion = m }
            if json["diag"] as? Bool == true { result.diagnostic = true }
            if let audio = json["audio"] as? String { result.audioBase64 = audio }
            if let music = json["musicPlaying"] as? Bool { result.musicPlaying = music }
            return result
        }

        return CommandResult()
    }
}
