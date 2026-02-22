import DockKit
import Combine
import Spatial

class DockKitManager: ObservableObject {
    @Published var isConnected = false
    @Published var accessoryId = "none"
    
    private var connectedAccessory: DockAccessory?
    private var isAnimating = false
    
    /// Callback for sending log messages back via WebSocket
    var onLog: ((String) -> Void)?
    
    private func log(_ msg: String) {
        print("❄️ \(msg)")
        onLog?(msg)
    }
    
    func startMonitoring() {
        Task {
            do {
                log("DockKit: Starting accessory monitoring...")
                for try await event in try DockAccessoryManager.shared.accessoryStateChanges {
                    await MainActor.run {
                        switch event.state {
                        case .docked:
                            if let accessory = event.accessory {
                                self.connectedAccessory = accessory
                                self.accessoryId = "\(accessory.identifier)"
                                self.isConnected = true
                                self.log("DockKit: Connected - \(accessory.identifier)")
                            }
                        case .undocked:
                            self.isConnected = false
                            self.connectedAccessory = nil
                            self.accessoryId = "none"
                            self.log("DockKit: Disconnected")
                        @unknown default:
                            break
                        }
                    }
                }
            } catch {
                log("DockKit: Error monitoring - \(error)")
            }
        }
    }
    
    /// Always calls the API — no flag-based early return.
    /// Must be called immediately before every setAngularVelocity().
    private func ensureTrackingDisabled() async {
        do {
            try await DockAccessoryManager.shared.setSystemTrackingEnabled(false)
        } catch {
            log("DockKit: Failed to disable system tracking - \(error)")
        }
    }
    
    private func enableSystemTracking() async {
        do {
            try await DockAccessoryManager.shared.setSystemTrackingEnabled(true)
            log("DockKit: System tracking re-enabled")
        } catch {
            log("DockKit: Failed to enable system tracking - \(error)")
        }
    }
    
    func performGesture(_ gesture: String) {
        guard let accessory = connectedAccessory else {
            log("DockKit: No accessory connected")
            return
        }
        guard !isAnimating else {
            log("DockKit: Already animating, skipping")
            return
        }
        
        let animation: DockAccessory.Animation
        switch gesture.lowercased() {
        case "yes", "nod":
            animation = .yes
        case "no", "shake":
            animation = .no
        case "wakeup", "wake":
            animation = .wakeup
        case "kapow":
            animation = .kapow
        default:
            log("DockKit: Unknown gesture '\(gesture)'")
            return
        }
        
        isAnimating = true
        Task {
            do {
                await ensureTrackingDisabled()
                try await accessory.animate(motion: animation)
                log("DockKit: Gesture '\(gesture)' done")
                await enableSystemTracking()
            } catch {
                log("DockKit: Gesture error - \(error)")
                await enableSystemTracking()
            }
            isAnimating = false
        }
    }
    
    func setOrientation(_ orientation: String) {
        guard let accessory = connectedAccessory else {
            log("DockKit: No accessory for orientation")
            return
        }
        guard !isAnimating else {
            log("DockKit: Already animating, skipping orientation")
            return
        }
        
        isAnimating = true
        Task {
            do {
                await ensureTrackingDisabled()
                
                let rollAngle: Double
                switch orientation.lowercased() {
                case "landscape", "horizontal":
                    rollAngle = .pi / 2
                case "portrait", "vertical":
                    rollAngle = 0
                default:
                    log("DockKit: Unknown orientation '\(orientation)'")
                    await enableSystemTracking()
                    isAnimating = false
                    return
                }
                
                let rotation = Rotation3D(
                    eulerAngles: EulerAngles(
                        x: Angle2D(radians: 0),
                        y: Angle2D(radians: 0),
                        z: Angle2D(radians: rollAngle),
                        order: .xyz
                    )
                )
                
                log("DockKit: Setting orientation to \(orientation) (roll=\(rollAngle))...")
                let progress = try await accessory.setOrientation(rotation, duration: .seconds(2), relative: false)
                log("DockKit: Orientation progress: \(progress)")
                
                await enableSystemTracking()
            } catch {
                log("DockKit: Orientation error - \(error)")
                await enableSystemTracking()
            }
            isAnimating = false
        }
    }

    func setRawOrientation(pitch: Double, yaw: Double, roll: Double, duration: Double = 2.0) {
        guard let accessory = connectedAccessory else {
            log("DockKit: No accessory for raw orientation")
            return
        }
        guard !isAnimating else {
            log("DockKit: Already animating, skipping raw orientation")
            return
        }
        
        isAnimating = true
        Task {
            do {
                await ensureTrackingDisabled()
                let rotation = Rotation3D(
                    eulerAngles: EulerAngles(
                        x: Angle2D(radians: yaw),
                        y: Angle2D(radians: pitch),
                        z: Angle2D(radians: roll),
                        order: .xyz
                    )
                )
                
                log("DockKit: Raw orientation pitch=\(pitch) yaw=\(yaw) roll=\(roll)")
                let progress = try await accessory.setOrientation(rotation, duration: .seconds(duration), relative: false)
                log("DockKit: Raw orientation progress: \(progress)")
                
                await enableSystemTracking()
            } catch {
                log("DockKit: Raw orientation error - \(error)")
                await enableSystemTracking()
            }
            isAnimating = false
        }
    }

    func setRawOrientationV3(pitch: Double, yaw: Double, roll: Double, duration: Double = 2.0) {
        guard let accessory = connectedAccessory else {
            log("DockKit: No accessory for V3 orientation")
            return
        }
        guard !isAnimating else {
            log("DockKit: Already animating, skipping V3")
            return
        }
        isAnimating = true
        Task {
            do {
                await ensureTrackingDisabled()
                let vector = Vector3D(x: pitch, y: yaw, z: roll)
                log("DockKit: V3 orientation pitch=\(pitch) yaw=\(yaw) roll=\(roll)")
                let progress = try await accessory.setOrientation(vector, duration: .seconds(duration), relative: false)
                log("DockKit: V3 progress: \(progress)")
                await enableSystemTracking()
            } catch {
                log("DockKit: V3 error - \(error)")
                await enableSystemTracking()
            }
            isAnimating = false
        }
    }
    
    func setRawVelocity(pitch: Double, yaw: Double, roll: Double, durationMs: Int = 1000) {
        guard let accessory = connectedAccessory else {
            log("DockKit: No accessory for velocity")
            return
        }
        guard !isAnimating else {
            log("DockKit: Already animating, skipping velocity")
            return
        }
        isAnimating = true
        Task {
            do {
                await ensureTrackingDisabled()
                let vector = Vector3D(x: pitch, y: yaw, z: roll)
                log("DockKit: Velocity pitch=\(pitch) yaw=\(yaw) roll=\(roll) for \(durationMs)ms")
                try await accessory.setAngularVelocity(vector)
                try await Task.sleep(for: .milliseconds(durationMs))
                await ensureTrackingDisabled()
                try await accessory.setAngularVelocity(Vector3D(x: 0, y: 0, z: 0))
                log("DockKit: Velocity done")
                await enableSystemTracking()
            } catch {
                log("DockKit: Velocity error - \(error)")
                await ensureTrackingDisabled()
                try? await accessory.setAngularVelocity(Vector3D(x: 0, y: 0, z: 0))
                await enableSystemTracking()
            }
            isAnimating = false
        }
    }

    // MARK: - Motion Presets (Phase 1B)
    
    var availableMotions: [String] {
        ["smallNod", "lookLeft", "lookRight", "lookAround", "thinking", "excited", "slowNodDown", "swaySinging"]
    }
    
    func performMotion(_ motionName: String) {
        guard connectedAccessory != nil else {
            log("DockKit: No accessory for motion")
            return
        }
        guard !isAnimating else {
            log("DockKit: Already animating, skipping motion '\(motionName)'")
            return
        }
        
        switch motionName.lowercased() {
        case "lookleft":
            runMotionSequence([
                (pitch: 0, yaw: 0.4, roll: 0, durationMs: 600),
                (pitch: 0, yaw: -0.4, roll: 0, durationMs: 600),
            ])
        case "lookright":
            runMotionSequence([
                (pitch: 0, yaw: -0.4, roll: 0, durationMs: 600),
                (pitch: 0, yaw: 0.4, roll: 0, durationMs: 600),
            ])
        case "smallnod":
            runMotionSequence([
                (pitch: -0.5, yaw: 0, roll: 0, durationMs: 600),
                (pitch: 0.8, yaw: 0, roll: 0, durationMs: 500),
                (pitch: -0.3, yaw: 0, roll: 0, durationMs: 400),
            ])
        case "lookaround":
            runMotionSequence([
                (pitch: 0, yaw: 0.4, roll: 0, durationMs: 600),
                (pitch: 0, yaw: -0.8, roll: 0, durationMs: 1000),
                (pitch: 0, yaw: 0.4, roll: 0, durationMs: 600),
            ])
        case "thinking":
            runMotionSequence([
                (pitch: 0, yaw: 0.2, roll: 0, durationMs: 1500),
            ])
        case "excited":
            runMotionSequence([
                (pitch: -0.5, yaw: 0, roll: 0, durationMs: 350),
                (pitch: 0.5, yaw: 0, roll: 0, durationMs: 350),
                (pitch: -0.5, yaw: 0, roll: 0, durationMs: 350),
                (pitch: 0.5, yaw: 0, roll: 0, durationMs: 350),
            ])
        case "slownoddown":
            runMotionSequence([
                (pitch: 0.15, yaw: 0, roll: 0, durationMs: 3000),
            ])
        case "swaysinging":
            runMotionSequence([
                (pitch: 0, yaw: 0.3, roll: 0, durationMs: 1200),
                (pitch: 0, yaw: -0.6, roll: 0, durationMs: 2400),
                (pitch: 0, yaw: 0.6, roll: 0, durationMs: 2400),
                (pitch: 0, yaw: -0.3, roll: 0, durationMs: 1200),
            ])
        default:
            log("DockKit: Unknown motion '\(motionName)'")
        }
    }
    
    private func runMotionSequence(_ steps: [(pitch: Double, yaw: Double, roll: Double, durationMs: Int)]) {
        guard let accessory = connectedAccessory else { return }
        isAnimating = true
        Task {
            do {
                for step in steps {
                    await ensureTrackingDisabled()
                    let vector = Vector3D(x: step.pitch, y: step.yaw, z: 0)
                    try await accessory.setAngularVelocity(vector)
                    try await Task.sleep(for: .milliseconds(step.durationMs))
                }
                await ensureTrackingDisabled()
                try await accessory.setAngularVelocity(Vector3D(x: 0, y: 0, z: 0))
                log("DockKit: Motion sequence done")
                await enableSystemTracking()
            } catch {
                log("DockKit: Motion sequence error - \(error)")
                await ensureTrackingDisabled()
                try? await accessory.setAngularVelocity(Vector3D(x: 0, y: 0, z: 0))
                await enableSystemTracking()
            }
            isAnimating = false
        }
    }

    private var isSleeping = false

    func suspendTracking() {
        isSleeping = true
        Task {
            do {
                try await DockAccessoryManager.shared.setSystemTrackingEnabled(false)
                log("DockKit: Tracking suspended for sleep")
            } catch {
                log("DockKit: Failed to suspend tracking - \(error)")
            }
        }
    }
    
    func resumeTracking() {
        isSleeping = false
        Task {
            do {
                try await DockAccessoryManager.shared.setSystemTrackingEnabled(true)
                log("DockKit: Tracking resumed from sleep")
            } catch {
                log("DockKit: Failed to resume tracking - \(error)")
            }
        }
    }
    
    func getDiagnostics() {
        guard let accessory = connectedAccessory else {
            log("DockKit Diag: No accessory")
            return
        }
        Task {
            do {
                let limits = try accessory.limits
                log("DockKit Diag: Limits yaw=\(limits.yaw) pitch=\(limits.pitch) roll=\(limits.roll)")
            } catch {
                log("DockKit Diag: Limits error - \(error)")
            }

            do {
                for try await state in accessory.motionStates {
                    log("DockKit Diag: Position=\(state.angularPositions) Velocity=\(state.angularVelocities)")
                    break
                }
            } catch {
                log("DockKit Diag: MotionState error - \(error)")
            }
        }
    }
}
