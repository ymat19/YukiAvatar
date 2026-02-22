import SwiftUI
import os.log

private let cvLogger = Logger(subsystem: "com.ymat19.HelloWorld", category: "ContentView")

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var expressionManager = ExpressionManager()
    @StateObject private var webSocketServer = WebSocketServer()
    @StateObject private var dockKitManager = DockKitManager()
    @StateObject private var audioManager = AudioPlayerManager()
    @StateObject private var speechQueue = SpeechQueueManager()
    @StateObject private var idleSceneManager = IdleSceneManager()
    @State private var lastActivityTime = Date()
    @State private var speechText: String = ""
    @State private var previousSpeechText: String = ""
    @State private var speechDismissTask: Task<Void, Never>?

    private let defaultSpeechDuration: Double = 5.0
    @State private var savedBrightness: CGFloat = 0.5

    // Voice input (iOS 26+)
    @State private var voiceInputManager: AnyObject?
    @State private var voiceInputState: String = "idle"
    @State private var voiceInputRunning: Bool = false
    @State private var voiceInputPaused: Bool = false
    @State private var voiceRecognizedText: String = ""
    @State private var sendingFallbackTask: Task<Void, Never>?
    @State private var expressionResetTask: Task<Void, Never>?
    @State private var isWaitingForResponse: Bool = false

    // User speech bubble style based on voice input state
    private var userBubbleStyle: BubbleStyle {
        voiceInputState == "sending" ? .sending : .user
    }

    // Whether to show user speech bubble
    private var showUserBubble: Bool {
        (voiceInputState == "listening" || voiceInputState == "sending") && !voiceRecognizedText.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                if !idleSceneManager.isScreenDimmed {
                    CameraPreviewView(captureSession: cameraManager.captureSession)
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(0.01)

                    if isLandscape {
                        ZStack {
                            if let uiImage = UIImage(named: expressionManager.currentImageName) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                                    .clipped()
                                    .offset(x: (speechText.isEmpty && previousSpeechText.isEmpty && !showUserBubble) ? 0 : geometry.size.width * 0.15)
                            }
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    // User speech bubble (voice input)
                                    if showUserBubble {
                                        SpeechBubbleView(text: voiceRecognizedText, style: userBubbleStyle)
                                            .frame(maxWidth: geometry.size.width * 0.4)
                                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                    }
                                    // Previous assistant speech bubble (faded)
                                    if !previousSpeechText.isEmpty {
                                        SpeechBubbleView(text: previousSpeechText, style: .previousAssistant)
                                            .frame(maxWidth: geometry.size.width * 0.4)
                                            .scaleEffect(0.92)
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                    // Assistant speech bubble (雪's response)
                                    if !speechText.isEmpty {
                                        SpeechBubbleView(text: speechText, style: .assistant)
                                            .frame(maxWidth: geometry.size.width * 0.4)
                                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                    }
                                }
                                Spacer()
                            }
                            .padding(.leading, 67)
                            .padding(.trailing, 67)
                            .opacity((speechText.isEmpty && previousSpeechText.isEmpty && !showUserBubble) ? 0 : 1)
                        }
                    } else {
                        VStack(spacing: 0) {
                            Spacer(minLength: (speechText.isEmpty && previousSpeechText.isEmpty && !showUserBubble) ? 0 : 8)

                            // User speech bubble (voice input)
                            if showUserBubble {
                                HStack {
                                    Spacer()
                                    SpeechBubbleView(text: voiceRecognizedText, style: userBubbleStyle)
                                        .frame(maxWidth: geometry.size.width * 0.85)
                                    Spacer().frame(width: 20)
                                }
                                .padding(.horizontal, 20)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            }

                            // Previous assistant speech bubble (faded)
                            if !previousSpeechText.isEmpty {
                                SpeechBubbleView(text: previousSpeechText, style: .previousAssistant)
                                    .frame(maxWidth: geometry.size.width * 0.85)
                                    .padding(.horizontal, 20)
                                    .scaleEffect(0.92)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // Assistant speech bubble (雪's response)
                            SpeechBubbleView(text: speechText)
                                .frame(maxWidth: geometry.size.width * 0.85)
                                .padding(.horizontal, 20)
                                .opacity(speechText.isEmpty ? 0 : 1)

                            Spacer(minLength: (speechText.isEmpty && previousSpeechText.isEmpty && !showUserBubble) ? 0 : 8)
                            if let uiImage = UIImage(named: expressionManager.currentImageName) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            }
                        }
                    }

                    VStack {
                        HStack {
                            StatusBarView(
                                isWSListening: webSocketServer.isListening,
                                wsClientCount: webSocketServer.connectedClients,
                                isDockKitConnected: dockKitManager.isConnected,
                                isAudioPlaying: audioManager.isPlaying,
                                voiceInputRunning: voiceInputRunning,
                                voiceInputPaused: voiceInputPaused,
                                voiceInputState: voiceInputState
                            )
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        Spacer()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: speechText)
            .animation(.easeInOut(duration: 0.3), value: previousSpeechText)
            .animation(.easeInOut(duration: 0.2), value: voiceRecognizedText)
            .animation(.easeInOut(duration: 0.2), value: voiceInputState)
        }
        .ignoresSafeArea()
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            UIScreen.main.brightness = 1.0
            cameraManager.startSession()
            expressionManager.startAutoBlinking()
            dockKitManager.startMonitoring()
            dockKitManager.onLog = { msg in
                let escaped = msg.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                webSocketServer.broadcast("{\"log\": \"\(escaped)\"}")
            }
            
            // Audio manager setup
            audioManager.onPlaybackDone = {
                expressionManager.mouthFrame = 0
                if expressionManager.currentExpression == .talking {
                    expressionManager.setExpression(.normal)
                }
                webSocketServer.broadcast("{\"event\": \"playback_done\"}")
                speechQueue.currentItemDone()
            }
            
            // Speech queue setup
            speechQueue.onProcessItem = { [self] item in
                cvLogger.notice("❄️ onProcessItem: expr=\(item.expression ?? "nil", privacy: .public) speech=\(item.speech ?? "nil", privacy: .public)")
                // Cancel sending fallback timer — response arrived
                sendingFallbackTask?.cancel()
                expressionResetTask?.cancel()
                isWaitingForResponse = false
                // Mute mic during TTS playback to prevent feedback loop
                if #available(iOS 26.0, *), let manager = voiceInputManager as? VoiceInputManager {
                    manager.pauseListening()
                    self.voiceInputPaused = true
                }
                if let exprStr = item.expression,
                   let expr = Expression(rawValue: exprStr) {
                    expressionManager.setExpression(expr)
                }
                if let gesture = item.gesture {
                    dockKitManager.performGesture(gesture)
                }
                if let motion = item.motion {
                    dockKitManager.performMotion(motion)
                }
                if let speech = item.speech {
                    let hasAudio = item.audioBase64 != nil
                    setSpeech(speech, duration: hasAudio ? nil : item.speechDuration, autoDismiss: !hasAudio)
                }
                if let audioBase64 = item.audioBase64 {
                    audioManager.playAudioFromBase64(audioBase64)
                } else {
                    let delay = item.speechDuration ?? defaultSpeechDuration
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(delay))
                        speechQueue.currentItemDone()
                    }
                }
            }
            speechQueue.onItemDone = { remaining in
                let resp = "{\"event\": \"item_done\", \"queue_remaining\": \(remaining)}"
                webSocketServer.broadcast(resp)
            }
            speechQueue.onQueueEmpty = { [self] in
                speechDismissTask?.cancel()
                sendingFallbackTask?.cancel()
                speechDismissTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled {
                        previousSpeechText = ""
                        speechText = ""
                    }
                }
                webSocketServer.broadcast("{\"event\": \"queue_empty\"}")
                // Resume mic after TTS playback ends
                if #available(iOS 26.0, *), let manager = voiceInputManager as? VoiceInputManager {
                    manager.resumeListening()
                    self.voiceInputPaused = false
                }
                // Reset expression to normal after delay (課題⑥)
                expressionResetTask?.cancel()
                expressionResetTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    if !Task.isCancelled {
                        expressionManager.setExpression(.normal)
                    }
                }
            }
            
            webSocketServer.onCommand = { command in
                Task { @MainActor in
                    handleWebSocketCommand(command)
                }
            }
            webSocketServer.start(port: 8765)
            setupIdleSceneManager()
            
            // Start voice input (iOS 26+)
            setupVoiceInput()
        }
        .onDisappear {
            cameraManager.stopSession()
            expressionManager.stopAutoBlinking()
            webSocketServer.stop()
            idleSceneManager.stop()
            speechDismissTask?.cancel()
            sendingFallbackTask?.cancel()
            expressionResetTask?.cancel()
            teardownVoiceInput()
        }
        .onTapGesture { wakeUp() }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .onChange(of: audioManager.currentMouthFrame) { _, newFrame in
            expressionManager.mouthFrame = newFrame
        }
        .onChange(of: voiceRecognizedText) { oldVal, newVal in
            let escaped = newVal.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let oldEscaped = oldVal.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let show = (voiceInputState == "listening" || voiceInputState == "sending") && !newVal.isEmpty
            webSocketServer.broadcast("{\"uiDebug\": \"voiceRecognizedText: \\\"\(oldEscaped)\\\" → \\\"\(escaped)\\\" showBubble=\(show)\"}")
        }
        .onChange(of: voiceInputState) { oldVal, newVal in
            let show = (newVal == "listening" || newVal == "sending") && !voiceRecognizedText.isEmpty
            webSocketServer.broadcast("{\"uiDebug\": \"voiceInputState: \\\"\(oldVal)\\\" → \\\"\(newVal)\\\" showBubble=\(show)\"}")
        }
    }


    private func setSpeech(_ text: String, duration: Double?, autoDismiss: Bool = true) {
        speechDismissTask?.cancel()
        // Save current speech as previous (for history display)
        if !speechText.isEmpty && speechText != "考え中..." && text != speechText {
            previousSpeechText = speechText
        }
        speechText = text
        
        if !text.isEmpty && autoDismiss {
            let dismissAfter = duration ?? defaultSpeechDuration
            speechDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(dismissAfter))
                if !Task.isCancelled {
                    speechText = ""
                }
            }
        }
    }

    private func wakeUp() {
        lastActivityTime = Date()
        idleSceneManager.recordActivity()
        UIScreen.main.brightness = 1.0
    }

    // MARK: - Voice Input Setup (iOS 26+)

    private func setupVoiceInput() {
        if #available(iOS 26.0, *) {
            let manager = VoiceInputManager()
            self.voiceInputManager = manager
            
            // Observe state changes
            manager.onStateChanged = { [self] newState in
                self.voiceInputState = newState.rawValue
                switch newState {
                case .listening:
                    self.wakeUp()
                    sendingFallbackTask?.cancel()
                    if let expr = Expression(rawValue: "listening") {
                        expressionManager.setExpression(expr)
                    }
                case .sending:
                    self.wakeUp()
                    if let expr = Expression(rawValue: "sending") {
                        expressionManager.setExpression(expr)
                    }
                    // Fallback: if no speech arrives within 30s, revert to normal
                    sendingFallbackTask?.cancel()
                    sendingFallbackTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(30))
                        if !Task.isCancelled {
                            if expressionManager.currentExpression == .sending {
                                expressionManager.setExpression(.normal)
                            }
                            if isWaitingForResponse {
                                isWaitingForResponse = false
                                speechText = ""
                            }
                        }
                    }
                case .idle:
                    // Clear user bubble text when returning to idle
                    // Don't reset expression to normal — keep sending expression
                    // until first speech queue item sets its own expression
                    voiceRecognizedText = ""
                }
            }
            
            // Wake word detected — interrupt playback
            manager.onWakeWordDetected = { [self] in
                wakeUp()
                // Stop current audio playback
                audioManager.stopLipSync()
                speechQueue.clearQueue()
                previousSpeechText = ""
                speechText = ""
                expressionResetTask?.cancel()
                print("❄️ VoiceInput: Wake word interrupt — playback stopped")
            }
            
            // Utterance captured — send to gateway via WebSocket broadcast
            manager.onUtteranceCaptured = { [self] utterance in
                // Show "考え中..." bubble while waiting for response
                isWaitingForResponse = true
                speechText = "考え中..."
                speechDismissTask?.cancel()
                let escaped = utterance
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let json = "{\"event\": \"voice_input\", \"text\": \"\(escaped)\"}"
                webSocketServer.broadcast(json)
                print("❄️ VoiceInput: Sent utterance to WebSocket: \(utterance)")
            }
            
            // Recognized text update — update user bubble
            manager.onRecognizedTextChanged = { [self] text in
                voiceRecognizedText = text
            }
            
            // Debug log — broadcast to WebSocket
            manager.onDebugLog = { [self] msg in
                let escaped = msg
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let json = "{\"voiceDebug\": \"\(escaped)\"}"
                webSocketServer.broadcast(json)
            }
            
            Task { @MainActor in
                await manager.start()
                self.voiceInputRunning = manager.isRunning
                self.voiceInputPaused = manager.isPaused
            }
        }
    }

    private func teardownVoiceInput() {
        if #available(iOS 26.0, *) {
            if let manager = voiceInputManager as? VoiceInputManager {
                Task { @MainActor in
                    await manager.stop()
                }
            }
        }
    }

    // MARK: - WebSocket Command Handler
    
    private func handleWebSocketCommand(_ command: String) {
        // Silent debug - don't wake up
        if let data = command.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["query"] as? String == "silent_debug" {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: Date())
            let idleSec = Int(Date().timeIntervalSince(self.lastActivityTime))
            var resp: [String: Any] = [
                "isScreenDimmed": self.idleSceneManager.isScreenDimmed,
                "currentScene": self.idleSceneManager.currentScene.rawValue,
                "currentExpression": self.expressionManager.currentImageName,
                "brightness": UIScreen.main.brightness,
                "hour": hour,
                "idleSeconds": idleSec
            ]
            resp["voiceInputState"] = voiceInputState
            resp["voiceInputRunning"] = voiceInputRunning
            if let d = try? JSONSerialization.data(withJSONObject: resp),
               let s = String(data: d, encoding: .utf8) {
                self.webSocketServer.broadcast(s)
            }
            return
        }
        self.wakeUp()
        
        // Handle capabilities query
        if let data = command.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["query"] as? String == "capabilities" {
            let caps: [String: Any] = [
                "expressions": Expression.allCases.filter { $0 != .talking && $0 != .blink }.map { $0.rawValue },
                "motions": dockKitManager.availableMotions,
                "gestures": ["nod", "shake"],
                "speakers": [
                    ["id": 24, "name": "WhiteCUL たのしい", "default": true],
                    ["id": 23, "name": "WhiteCUL ノーマル"],
                    ["id": 25, "name": "WhiteCUL かなしい"],
                    ["id": 26, "name": "WhiteCUL びえーん"]
                ],
                "voiceInput": voiceInputRunning
            ]
            if let capsData = try? JSONSerialization.data(withJSONObject: caps),
               let capsStr = String(data: capsData, encoding: .utf8) {
                webSocketServer.broadcast(capsStr)
            }
            return
        }
        
        // Handle voice_debug query
        if let data = command.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["query"] as? String == "voice_debug" {
            if #available(iOS 26.0, *), let manager = voiceInputManager as? VoiceInputManager {
                let status = manager.getDebugStatus()
                if let data = try? JSONSerialization.data(withJSONObject: status),
                   let str = String(data: data, encoding: .utf8) {
                    webSocketServer.broadcast(str)
                }
            } else {
                webSocketServer.broadcast("{\"error\": \"VoiceInputManager not available\"}")
            }
            return
        }
        
        // Handle queue_status query
        if let data = command.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["query"] as? String == "queue_status" {
            let status = speechQueue.getStatus()
            let resp: [String: Any] = [
                "queue_length": status.queueLength,
                "is_processing": status.isProcessing
            ]
            if let data = try? JSONSerialization.data(withJSONObject: resp),
               let str = String(data: data, encoding: .utf8) {
                webSocketServer.broadcast(str)
            }
            return
        }
        
        // Handle debug_status query
        if let data = command.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["query"] as? String == "debug_status" {
            let resp: [String: Any] = [
                "isScreenDimmed": idleSceneManager.isScreenDimmed,
                "currentScene": idleSceneManager.currentScene.rawValue,
                "currentExpression": expressionManager.currentImageName,
                "brightness": UIScreen.main.brightness
            ]
            if let data = try? JSONSerialization.data(withJSONObject: resp),
               let str = String(data: data, encoding: .utf8) {
                webSocketServer.broadcast(str)
            }
            return
        }
        
        // Handle force_wake / sleep commands
        if let data = command.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cmd = json["command"] as? String {
            if cmd == "force_wake" {
                idleSceneManager.isScreenDimmed = false
                idleSceneManager.currentScene = .none
                expressionManager.setExpression(.normal)
                expressionManager.startAutoBlinking()
                UIScreen.main.brightness = 1.0
                cameraManager.startSession()
                dockKitManager.resumeTracking()
                webSocketServer.broadcast("{\"event\": \"force_wake_done\"}")
                return
            }
            if cmd == "sleep" {
                savedBrightness = UIScreen.main.brightness
                UIScreen.main.brightness = 0.01
                expressionManager.setExpression(.sleeping)
                expressionManager.stopAutoBlinking()
                idleSceneManager.isScreenDimmed = true
                idleSceneManager.currentScene = .sleeping
                cameraManager.stopSession()
                dockKitManager.suspendTracking()
                webSocketServer.broadcast("{\"event\": \"sleep_done\"}")
                return
            }
        }
        
        cvLogger.notice("❄️ handleWebSocketCommand: processing")
        let result = expressionManager.handleCommand(command)
        // Handle musicPlaying state
        if let music = result.musicPlaying {
            idleSceneManager.isMusicPlaying = music
            if music {
                idleSceneManager.recordActivity()
                idleSceneManager.currentScene = .none
                idleSceneManager.currentScene = .singing
                expressionManager.setExpression(.idle_singing)
                dockKitManager.performMotion("swaySinging")
            } else {
                idleSceneManager.currentScene = .none
                expressionManager.setExpression(.normal)
            }
        }
        cvLogger.notice("❄️ handleCommand result: expr=\(result.expression?.rawValue ?? "nil", privacy: .public) speech=\(result.speech != nil ? "yes" : "no", privacy: .public) audio=\(result.audioBase64 != nil ? "yes" : "no", privacy: .public)")
        let isQueued = result.speech != nil || result.audioBase64 != nil
        if let gesture = result.gesture, !isQueued {
            dockKitManager.performGesture(gesture)
        }
        if let orientation = result.orientation {
            dockKitManager.setOrientation(orientation)
        }
        if let raw = result.rawOrientation {
            dockKitManager.setRawOrientation(pitch: raw.pitch, yaw: raw.yaw, roll: raw.roll)
        }
        if let v3 = result.v3Orientation {
            dockKitManager.setRawOrientationV3(pitch: v3.pitch, yaw: v3.yaw, roll: v3.roll)
        }
        if let vel = result.velocity {
            dockKitManager.setRawVelocity(pitch: vel.pitch, yaw: vel.yaw, roll: vel.roll, durationMs: vel.durationMs)
        }
        if let motion = result.motion, !isQueued {
            dockKitManager.performMotion(motion)
        }
        if result.speech != nil || result.audioBase64 != nil {
            let interrupt = {
                if let data = command.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return json["interrupt"] as? Bool ?? false
                }
                return false
            }()
            let item = SpeechItem(
                speech: result.speech,
                expression: result.expression?.rawValue,
                motion: result.motion,
                gesture: result.gesture,
                audioBase64: result.audioBase64,
                speechDuration: result.speechDuration,
                interrupt: interrupt
            )
            speechQueue.enqueue(item)
        }
        if result.diagnostic {
            dockKitManager.getDiagnostics()
        }
    }

    private func setupIdleSceneManager() {
        idleSceneManager.onSetExpression = { [self] expr in
            expressionManager.setExpression(expr)
        }
        idleSceneManager.onPerformMotion = { [self] motion in
            dockKitManager.performMotion(motion)
        }
        idleSceneManager.onEnforceBrightness = {
            UIScreen.main.brightness = 1.0
        }
        idleSceneManager.onDimScreen = { [self] dim in
            if dim {
                savedBrightness = UIScreen.main.brightness
                UIScreen.main.brightness = 0.01
                expressionManager.stopAutoBlinking()
            } else {
                UIScreen.main.brightness = 1.0
                expressionManager.startAutoBlinking()
            }
        }
        idleSceneManager.onStopCamera = { [self] in
            cameraManager.stopSession()
        }
        idleSceneManager.onStartCamera = { [self] in
            cameraManager.startSession()
        }
        idleSceneManager.onSuspendTracking = { [self] in
            dockKitManager.suspendTracking()
        }
        idleSceneManager.onResumeTracking = { [self] in
            dockKitManager.resumeTracking()
        }
        idleSceneManager.start()
    }
}
