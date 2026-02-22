import Foundation
import Speech
import AVFoundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.ymat19.HelloWorld", category: "VoiceInput")

/// Manages continuous voice input using SpeechAnalyzer.
/// Handles wake word detection ("雪ちゃん"), utterance capture, and silence detection.
@available(iOS 26.0, *)
class VoiceInputManager: ObservableObject {
    
    // MARK: - State
    
    enum VoiceInputState: String {
        case idle       // Listening for wake word
        case listening  // Wake word detected, capturing user speech
        case sending    // Silence detected, sending to gateway
    }
    
    @MainActor @Published var state: VoiceInputState = .idle
    @MainActor @Published var recognizedText: String = ""
    @MainActor @Published var isRunning: Bool = false
    @MainActor @Published var lastError: String?
    @MainActor @Published var isPaused: Bool = false
    @MainActor @Published var capturedUtterance: String = ""
    
    // MARK: - Audio Engine
    
    private let audioEngine = AVAudioEngine()
    private var audioTapInstalled = false
    
    // MARK: - SpeechAnalyzer
    
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var recognitionTask: Task<Void, Error>?
    private var analyzerFormat: AVAudioFormat?
    private var audioConverter: AVAudioConverter?
    
    /// Flag to suppress audio buffer feeding during pipeline reset
    private var isPipelineResetting = false
    
    // MARK: - Wake Word / Silence Detection
    
    private let wakeWords = ["雪ちゃん", "ゆきちゃん", "ユキちゃん"]
    private let silenceTimeout: TimeInterval = 2.0  // seconds of no new text = end of utterance
    private var silenceTimer: Timer?
    private var lastTranscriptUpdate = Date()
    
    // Debug: count audio buffers fed
    private var audioBufferCount: Int = 0
    
    // MARK: - Callbacks
    
    /// Called when a complete utterance is captured (after silence detection)
    @MainActor var onUtteranceCaptured: ((String) -> Void)?
    /// Called when wake word is detected (for interrupting playback)
    @MainActor var onWakeWordDetected: (() -> Void)?
    /// Called when state changes (for expression updates)
    @MainActor var onStateChanged: ((VoiceInputState) -> Void)?
    /// Called when recognized text changes (for UI bubble updates)
    @MainActor var onRecognizedTextChanged: ((String) -> Void)?
    /// Called for debug logging (broadcasts to WebSocket)
    @MainActor var onDebugLog: ((String) -> Void)?
    
    // MARK: - Start / Stop
    
    @MainActor
    func start() async {
        guard !isRunning else { return }
        
        // Request permissions
        let speechAuth = await requestSpeechPermission()
        let micAuth = await requestMicrophonePermission()
        
        logger.info("Permissions: speech=\(speechAuth), mic=\(micAuth)")
        
        guard speechAuth && micAuth else {
            lastError = "Permissions not granted (speech: \(speechAuth), mic: \(micAuth))"
            logger.error("❄️ VoiceInput: \(self.lastError!)")
            return
        }
        
        do {
            try await startPipeline()
            isRunning = true
            lastError = nil
            logger.info("❄️ VoiceInput: Started successfully")
        } catch {
            lastError = error.localizedDescription
            logger.error("❄️ VoiceInput: Start failed: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    func stop() async {
        stopAudioEngine()
        silenceTimer?.invalidate()
        silenceTimer = nil
        inputContinuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognitionTask?.cancel()
        recognitionTask = nil
        analyzer = nil
        transcriber = nil
        audioConverter = nil
        isRunning = false
        state = .idle
        logger.info("❄️ VoiceInput: Stopped")
    }
    
    // MARK: - Permissions
    
    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    // MARK: - Pipeline Setup
    
    private func startPipeline() async throws {
        // Create transcriber for Japanese
        let locale = Locale(identifier: "ja-JP")
        let newTranscriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveTranscription
        )
        self.transcriber = newTranscriber
        
        // Ensure model is available
        try await ensureModelAvailable(transcriber: newTranscriber, locale: locale)
        
        // Create analyzer with the transcriber module
        let newAnalyzer = SpeechAnalyzer(modules: [newTranscriber])
        self.analyzer = newAnalyzer
        
        // Get best audio format
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [newTranscriber])
        self.analyzerFormat = format
        logger.info("❄️ VoiceInput: Analyzer format: \(String(describing: format))")
        
        // Create async stream for feeding audio
        let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = continuation
        
        // Start recognition task on a NON-MainActor context for immediate result delivery.
        // Only the UI update hops to MainActor, keeping the for-await loop unblocked.
        recognitionTask = Task.detached { [weak self] in
            guard let transcriber = await self?.transcriber else {
                logger.error("❄️ VoiceInput: recognitionTask - transcriber is nil!")
                return
            }
            logger.info("❄️ VoiceInput: recognitionTask started (detached), waiting for results...")
            var resultCount = 0
            do {
                for try await result in transcriber.results {
                    resultCount += 1
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    logger.info("❄️ VoiceInput: Result #\(resultCount) (final=\(isFinal)): \(text)")
                    await self?.handleTranscriptionResult(text: text, isFinal: isFinal)
                }
                logger.info("❄️ VoiceInput: recognitionTask - results stream ended after \(resultCount) results")
            } catch {
                if !Task.isCancelled {
                    logger.error("❄️ VoiceInput: recognitionTask error: \(error.localizedDescription)")
                }
            }
        }
        
        // Start the analyzer with the input sequence
        try await newAnalyzer.start(inputSequence: inputSequence)
        logger.info("❄️ VoiceInput: Analyzer started with input sequence")
        
        // Setup and start audio engine
        try setupAudioSession()
        try startAudioEngine()
        
        logger.info("❄️ VoiceInput: Pipeline fully started")
    }
    
    private func ensureModelAvailable(transcriber: SpeechTranscriber, locale: Locale) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        let supportedIds = supported.map { $0.identifier(.bcp47) }
        let localeId = locale.identifier(.bcp47)
        let isSupported = supportedIds.contains(localeId)
        logger.info("❄️ VoiceInput: Locale \(localeId) supported=\(isSupported)")
        
        guard isSupported else {
            throw NSError(domain: "VoiceInput", code: 1, userInfo: [NSLocalizedDescriptionKey: "Locale \(locale) not supported. Supported: \(supportedIds.joined(separator: ", "))"])
        }
        
        let installed = await SpeechTranscriber.installedLocales
        let installedIds = installed.map { $0.identifier(.bcp47) }
        let isInstalled = installedIds.contains(localeId)
        logger.info("❄️ VoiceInput: Locale \(localeId) installed=\(isInstalled). Installed locales: \(installedIds.joined(separator: ", "))")
        
        if !isInstalled {
            logger.info("❄️ VoiceInput: Downloading Japanese speech model...")
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await downloader.downloadAndInstall()
            }
            logger.info("❄️ VoiceInput: Model download complete")
        } else {
            logger.info("❄️ VoiceInput: Japanese model already installed")
        }
        
        // Reserve the locale (required before use!)
        let allocated = await AssetInventory.reservedLocales
        let alreadyReserved = allocated.contains { $0.identifier(.bcp47) == localeId }
        if !alreadyReserved {
            logger.info("❄️ VoiceInput: Reserving locale \(localeId)...")
            try await AssetInventory.reserve(locale: locale)
            logger.info("❄️ VoiceInput: Locale reserved successfully")
        } else {
            logger.info("❄️ VoiceInput: Locale already reserved")
        }
    }
    
    // MARK: - Audio Session & Engine
    
    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Use playAndRecord to allow both mic input and speaker output
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        logger.info("❄️ VoiceInput: Audio session configured (playAndRecord, default mode for speaker output (AEC disabled, wake word NGワード対策))")
    }
    
    private func startAudioEngine() throws {
        guard !audioTapInstalled else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        logger.info("❄️ VoiceInput: Input format: sampleRate=\(inputFormat.sampleRate) channels=\(inputFormat.channelCount)")
        
        if let analyzerFmt = analyzerFormat {
            logger.info("❄️ VoiceInput: Analyzer format: sampleRate=\(analyzerFmt.sampleRate) channels=\(analyzerFmt.channelCount)")
        }
        
        audioBufferCount = 0
        
        // Use smaller buffer size (1024 instead of 4096) for more frequent audio delivery,
        // which helps SpeechAnalyzer produce partial results more incrementally.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        audioTapInstalled = true
        logger.info("❄️ VoiceInput: Audio engine started (bufferSize=1024)")
    }
    
    private func stopAudioEngine() {
        guard audioTapInstalled else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioTapInstalled = false
    }
    
    // MARK: - Audio Buffer Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Skip feeding audio while pipeline is being reset
        guard !isPipelineResetting else { return }
        guard let analyzerFormat = analyzerFormat, let continuation = inputContinuation else { return }
        
        do {
            let convertedBuffer = try convertBuffer(buffer, to: analyzerFormat)
            continuation.yield(AnalyzerInput(buffer: convertedBuffer))
            audioBufferCount += 1
            if audioBufferCount % 100 == 0 {
                logger.info("❄️ VoiceInput: Fed \(self.audioBufferCount) audio buffers to analyzer")
            }
        } catch {
            logger.error("❄️ VoiceInput: Buffer conversion error: \(error.localizedDescription)")
        }
    }
    
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else { return buffer }
        
        if audioConverter == nil || audioConverter?.outputFormat != format {
            audioConverter = AVAudioConverter(from: inputFormat, to: format)
            audioConverter?.primeMethod = .none
            logger.info("❄️ VoiceInput: Created converter: \(inputFormat.sampleRate)Hz -> \(format.sampleRate)Hz")
        }
        
        guard let converter = audioConverter else {
            throw NSError(domain: "VoiceInput", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
        }
        
        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledLength.rounded(.up))
        
        guard let conversionBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frameCapacity) else {
            throw NSError(domain: "VoiceInput", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create conversion buffer"])
        }
        
        var nsError: NSError?
        var bufferProcessed = false
        
        let status = converter.convert(to: conversionBuffer, error: &nsError) { _, inputStatusPointer in
            defer { bufferProcessed = true }
            inputStatusPointer.pointee = bufferProcessed ? .noDataNow : .haveData
            return bufferProcessed ? nil : buffer
        }
        
        guard status != .error else {
            throw nsError ?? NSError(domain: "VoiceInput", code: 4, userInfo: [NSLocalizedDescriptionKey: "Conversion failed"])
        }
        
        return conversionBuffer
    }
    
    // MARK: - Pipeline Reset (for clearing stale transcription text)
    
    /// Resets the SpeechAnalyzer pipeline (transcriber + analyzer + async stream) without
    /// touching the audio engine tap. This clears all accumulated transcription text so that
    /// wake words from the previous cycle are not re-detected.
    ///
    /// Called after sending→idle transition to prevent duplicate wake word detection.
    private func resetPipeline() async {
        logger.info("❄️ VoiceInput: Resetting analyzer pipeline...")
        
        // 1. Stop feeding audio buffers to old continuation
        isPipelineResetting = true
        
        // 2. Finish the old input stream — this tells the analyzer no more data is coming
        inputContinuation?.finish()
        inputContinuation = nil
        
        // 3. Finalize and close the old analyzer
        if let oldAnalyzer = analyzer {
            do {
                try await oldAnalyzer.finalizeAndFinishThroughEndOfInput()
                logger.info("❄️ VoiceInput: Old analyzer finalized")
            } catch {
                logger.warning("❄️ VoiceInput: Old analyzer finalize error (non-fatal): \(error.localizedDescription)")
            }
        }
        
        // 4. Cancel old recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // 5. Clear old references
        analyzer = nil
        transcriber = nil
        // Keep audioConverter — format doesn't change, converter can be reused
        
        // 6. Build new pipeline
        do {
            let locale = Locale(identifier: "ja-JP")
            let newTranscriber = SpeechTranscriber(
                locale: locale,
                preset: .progressiveTranscription
            )
            self.transcriber = newTranscriber
            
            // Model is already reserved — skip ensureModelAvailable to reduce overhead
            
            let newAnalyzer = SpeechAnalyzer(modules: [newTranscriber])
            self.analyzer = newAnalyzer
            
            // Reuse existing analyzerFormat (doesn't change)
            
            // Create new async stream
            let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.inputContinuation = continuation
            
            // Start new recognition task (detached, non-MainActor)
            recognitionTask = Task.detached { [weak self] in
                guard let transcriber = await self?.transcriber else { return }
                logger.info("❄️ VoiceInput: New recognitionTask started (detached)")
                var resultCount = 0
                do {
                    for try await result in transcriber.results {
                        resultCount += 1
                        let text = String(result.text.characters)
                        let isFinal = result.isFinal
                        logger.info("❄️ VoiceInput: Result #\(resultCount) (final=\(isFinal)): \(text)")
                        await self?.handleTranscriptionResult(text: text, isFinal: isFinal)
                    }
                    logger.info("❄️ VoiceInput: recognitionTask ended after \(resultCount) results")
                } catch {
                    if !Task.isCancelled {
                        logger.error("❄️ VoiceInput: recognitionTask error: \(error.localizedDescription)")
                    }
                }
            }
            
            // Start the new analyzer
            try await newAnalyzer.start(inputSequence: inputSequence)
            
            // 7. Resume feeding audio buffers
            isPipelineResetting = false
            
            logger.info("❄️ VoiceInput: Pipeline reset complete ✅")
        } catch {
            logger.error("❄️ VoiceInput: Pipeline reset failed: \(error.localizedDescription)")
            isPipelineResetting = false
            // If reset failed, try full restart as fallback
            await MainActor.run {
                Task {
                    await self.restart()
                }
            }
        }
    }
    
    // MARK: - Transcription Result Handling
    
    @MainActor

    /// Trim leading punctuation and whitespace left after wake word removal
    private func trimLeadingPunctuation(_ s: String) -> String {
        let trimChars = CharacterSet(charactersIn: "\u{3002}\u{3001},.!\u{FF01}?\u{FF1F} \u{3000}")
        var result = s
        while let first = result.unicodeScalars.first, trimChars.contains(first) {
            result = String(result.unicodeScalars.dropFirst())
        }
        return result
    }

    private func handleTranscriptionResult(text: String, isFinal: Bool) {
        recognizedText = text
        lastTranscriptUpdate = Date()
        
        // Broadcast to WebSocket for debugging
        onDebugLog?("🎤 [\(state.rawValue)] \(isFinal ? "FINAL" : "partial"): \(text)")
        
        switch state {
        case .idle:
            // Looking for wake word (try all variants)
            if let matchedWord = wakeWords.first(where: { text.contains($0) }) {
                logger.info("❄️ VoiceInput: Wake word detected ('\(matchedWord)')! Text: \(text)")
                transitionTo(.listening)
                onWakeWordDetected?()
                
                // Extract text after wake word as start of utterance
                if let range = text.range(of: matchedWord) {
                    let afterWake = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    capturedUtterance = trimLeadingPunctuation(afterWake)
                } else {
                    capturedUtterance = ""
                }
                onRecognizedTextChanged?(capturedUtterance)
                startSilenceTimer()
            }
            
        case .listening:
            // Accumulate text (the transcriber gives us the full current segment)
            // Try to find any wake word variant and extract text after it
            var foundAfterWake: String? = nil
            for word in wakeWords {
                if let range = text.range(of: word) {
                    foundAfterWake = trimLeadingPunctuation(String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces))
                    break
                }
            }
            capturedUtterance = foundAfterWake ?? text
            onRecognizedTextChanged?(capturedUtterance)
            resetSilenceTimer()
            
        case .sending:
            // Ignore results while sending
            break
        }
    }
    
    // MARK: - State Transitions
    
    @MainActor
    private func transitionTo(_ newState: VoiceInputState) {
        let oldState = state
        state = newState
        logger.info("❄️ VoiceInput: \(oldState.rawValue) → \(newState.rawValue)")
        onStateChanged?(newState)
    }
    
    // MARK: - Silence Detection
    
    @MainActor
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.onSilenceDetected()
            }
        }
    }
    
    @MainActor
    private func resetSilenceTimer() {
        startSilenceTimer()
    }
    
    /// Characters considered "punctuation-only" — if the captured utterance consists
    /// entirely of these after trimming whitespace, we keep listening instead of sending.
    /// This prevents premature sends when SpeechAnalyzer emits "。" before the user finishes.
    private static let punctuationOnlySet = CharacterSet(charactersIn: "。、．，.,:;!！?？…─―　 ")
    
    @MainActor
    private func onSilenceDetected() {
        guard state == .listening else { return }
        
        let utterance = capturedUtterance.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if utterance.isEmpty {
            logger.info("❄️ VoiceInput: Empty utterance, continuing to listen")
            onDebugLog?("🎤 Empty utterance, keep listening")
            resetSilenceTimer()
            return
        }
        
        // If the utterance is only punctuation, the user is likely still speaking.
        // SpeechAnalyzer sometimes emits "。" before the real content arrives.
        // Keep listening and restart the silence timer.
        let strippedOfPunctuation = utterance.unicodeScalars.filter {
            !Self.punctuationOnlySet.contains($0)
        }
        if strippedOfPunctuation.isEmpty {
            logger.info("❄️ VoiceInput: Punctuation-only utterance (\"\(utterance)\"), continuing to listen")
            onDebugLog?("🎤 Punctuation-only, keep listening: \"\(utterance)\"")
            resetSilenceTimer()
            return
        }
        
        logger.info("❄️ VoiceInput: Utterance captured: \(utterance)")
        transitionTo(.sending)
        onUtteranceCaptured?(utterance)
        
        // Return to idle after sending, then reset the analyzer pipeline
        // to clear stale transcription text and prevent duplicate wake word detection.
        //
        // IMPORTANT: Cancel the old recognitionTask BEFORE transitioning to idle.
        // Otherwise, stale results from the old pipeline arrive during idle state
        // and re-trigger wake word detection (confirmed 2026-02-18 08:27 debug log).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if self.state == .sending {
                // 1. Cancel old recognition task first to stop stale results
                self.recognitionTask?.cancel()
                self.recognitionTask = nil
                
                // 2. Now safe to transition to idle — no more results will arrive
                self.transitionTo(.idle)
                self.capturedUtterance = ""
                self.recognizedText = ""
                self.onRecognizedTextChanged?("")
                
                // 3. Reset analyzer pipeline (builds new recognitionTask)
                await self.resetPipeline()
            }
        }
    }
    
    // MARK: - Pause / Resume (for muting during TTS playback)
    
    /// Pause voice input processing (stop feeding audio to analyzer).
    /// Call when TTS playback starts to prevent feedback loop.
    @MainActor
    func pauseListening() {
        guard isRunning, !isPipelineResetting else { return }
        isPipelineResetting = true
        isPaused = true
        silenceTimer?.invalidate()
        silenceTimer = nil
        logger.info("❄️ VoiceInput: Paused (TTS playback)")
    }
    
    /// Resume voice input processing after TTS playback ends.
    /// Resets the pipeline to clear any stale transcription text.
    @MainActor
    func resumeListening() {
        guard isRunning, isPipelineResetting else { return }
        logger.info("❄️ VoiceInput: Resuming (TTS done)")
        isPaused = false
        Task {
            await self.resetPipeline()
            logger.info("❄️ VoiceInput: Resumed ✅")
        }
    }
    
    // MARK: - Debug Status
    
    @MainActor
    func getDebugStatus() -> [String: Any] {
        return [
            "state": state.rawValue,
            "isRunning": isRunning,
            "audioBufferCount": audioBufferCount,
            "recognizedText": recognizedText,
            "capturedUtterance": capturedUtterance,
            "lastError": lastError ?? "none"
        ]
    }
    
    // MARK: - Restart (for recovery)
    
    @MainActor
    func restart() async {
        await stop()
        try? await Task.sleep(for: .seconds(1))
        await start()
    }
}
