import Foundation
import Combine

enum IdleScene: String {
    case none
    case sleeping      // 3-5min
    case snack         // 5-15min random or ~15:00
    case singing       // 1-3min random low chance
    case thinking      // 5-10min random
    case bored         // 10-20min
    case greeting      // time-of-day trigger
}

class IdleSceneManager: ObservableObject {
    @Published var currentScene: IdleScene = .none
    @Published var isScreenDimmed = false
    @Published var isMusicPlaying = false
    
    private var timer: Timer?
    private var lastActivityTime = Date()
    private var lastGreetingHour: Int = -1
    private var sceneStartTime: Date?
    
    var onSetExpression: ((Expression) -> Void)?
    var onPerformMotion: ((String) -> Void)?
    var onDimScreen: ((Bool) -> Void)?
    var onEnforceBrightness: (() -> Void)?
    var onStopCamera: (() -> Void)?
    var onStartCamera: (() -> Void)?
    var onSuspendTracking: (() -> Void)?
    var onResumeTracking: (() -> Void)?
    
    // Burn-in protection: dim after 30min idle (daytime), 2min (night)
    private let daytimeDimSeconds: TimeInterval = 1800  // 30min
    private let nightDimSeconds: TimeInterval = 120      // 2min
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    func recordActivity() {
        lastActivityTime = Date()
        if currentScene != .none || isScreenDimmed {
            wakeFromIdle()
        }
    }
    
    func wakeFromIdle() {
        let wasScene = currentScene
        currentScene = .none
        sceneStartTime = nil
        
        if isScreenDimmed {
            isScreenDimmed = false
            onDimScreen?(false)
            onStartCamera?()
            onResumeTracking?()
        }
        
        onEnforceBrightness?()
        if wasScene != .none {
            onSetExpression?(.normal)
        }
    }
    
    private var isNightTime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 23 || hour < 7
    }
    
    private func evaluate() {
        let now = Date()
        let idleSeconds = now.timeIntervalSince(lastActivityTime)
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        
        // === Screen dimming (burn-in protection) ===
        let dimThreshold = isNightTime ? nightDimSeconds : daytimeDimSeconds
        if idleSeconds > dimThreshold && !isScreenDimmed {
            isScreenDimmed = true
            onDimScreen?(true)
            onStopCamera?()
            onSuspendTracking?()
            currentScene = .sleeping
            onSetExpression?(.sleeping)
            return
        }
        
        // Already dimmed — nothing to do
        if isScreenDimmed { return }
        
        // === Music playing → singing scene ===
        if isMusicPlaying {
            if currentScene != .singing {
                startScene(.singing)
            }
            return
        }
        
        // If music just stopped and we were singing, return to normal
        if !isMusicPlaying && currentScene == .singing {
            currentScene = .none
            sceneStartTime = nil
            onSetExpression?(.normal)
            return
        }
        
        // === Scene duration management ===
        if currentScene != .none {
            if let start = sceneStartTime {
                let sceneDuration = now.timeIntervalSince(start)
                let maxDuration: TimeInterval = {
                    switch currentScene {
                    case .sleeping: return 300   // 5min
                    case .snack: return 90       // 1.5min
                    case .singing: return 60     // 1min
                    case .thinking: return 45    // 45s
                    case .bored: return 120      // 2min
                    case .greeting: return 30    // 30s
                    case .none: return 0
                    }
                }()
                if sceneDuration > maxDuration {
                    currentScene = .none
                    sceneStartTime = nil
                    onSetExpression?(.normal)
                }
            }
            return
        }
        
        // === Time-of-day greeting ===
        if (7...9).contains(hour) || (12...13).contains(hour) || (17...19).contains(hour) {
            if lastGreetingHour != hour {
                lastGreetingHour = hour
                startScene(.greeting)
                return
            }
        }
        
        // === Idle-time based scenes (compressed to fit within 30min) ===
        
        // 15-30min: bored (restless before sleep)
        if idleSeconds > 900 && Int.random(in: 0..<3) == 0 {
            startScene(.bored)
            return
        }
        
        // 8-15min: snack (random or ~15:00)
        if idleSeconds > 480 {
            let minute = calendar.component(.minute, from: now)
            let isSnackTime = (hour == 15 && minute < 30)
            if isSnackTime || Int.random(in: 0..<6) == 0 {
                startScene(.snack)
                return
            }
        }
        
        // 5-8min: thinking
        if idleSeconds > 300 && Int.random(in: 0..<4) == 0 {
            startScene(.thinking)
            return
        }
        
        // 3-5min: sleeping (dozing off)
        if idleSeconds > 180 {
            startScene(.sleeping)
            return
        }
        
        // 1-3min: random singing (low chance)
        if idleSeconds > 60 && Int.random(in: 0..<30) == 0 {
            startScene(.singing)
            return
        }
    }
    
    private func startScene(_ scene: IdleScene) {
        currentScene = scene
        sceneStartTime = Date()
        
        switch scene {
        case .sleeping:
            onSetExpression?(.sleepy)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if self.currentScene == .sleeping {
                    self.onSetExpression?(.sleeping)
                    self.onPerformMotion?("slowNodDown")
                }
            }
        case .snack:
            onSetExpression?(.idle_snack)
        case .singing:
            onSetExpression?(.idle_singing)
            onPerformMotion?("swaySinging")
        case .thinking:
            onSetExpression?(.thinking)
            onPerformMotion?("thinking")
        case .bored:
            onSetExpression?(.idle_bored)
            onPerformMotion?("lookAround")
        case .greeting:
            onSetExpression?(.greeting)
            onPerformMotion?("smallNod")
        case .none:
            break
        }
    }
}
