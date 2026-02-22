import SwiftUI

/// Polished status bar showing connection states as pill-shaped indicators
struct StatusBarView: View {
    let isWSListening: Bool
    let wsClientCount: Int
    let isDockKitConnected: Bool
    let isAudioPlaying: Bool
    let voiceInputRunning: Bool
    let voiceInputPaused: Bool
    let voiceInputState: String

    var body: some View {
        HStack(spacing: 6) {
            // WebSocket
            StatusPill(
                icon: "network",
                label: wsClientCount > 0 ? "\(wsClientCount)" : nil,
                state: isWSListening ? (wsClientCount > 0 ? .active : .ready) : .error
            )

            // DockKit
            StatusPill(
                icon: "gyroscope",
                label: nil,
                state: isDockKitConnected ? .active : .inactive
            )

            // Microphone
            StatusPill(
                icon: "mic.fill",
                label: nil,
                state: micState
            )

            // Audio playback
            if isAudioPlaying {
                StatusPill(
                    icon: "speaker.wave.2.fill",
                    label: nil,
                    state: .active
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    private var micState: StatusPillState {
        guard voiceInputRunning else { return .error }
        if voiceInputPaused { return .paused }
        switch voiceInputState {
        case "listening": return .listening
        case "sending": return .processing
        default: return .ready
        }
    }
}

enum StatusPillState {
    case active      // green — connected / working
    case ready       // green dim — listening but no clients
    case inactive    // gray — not connected
    case error       // red — failed / stopped
    case listening   // yellow — mic listening
    case processing  // blue — sending to AI
    case paused      // orange — temporarily muted

    var color: Color {
        switch self {
        case .active: return .green
        case .ready: return .green.opacity(0.6)
        case .inactive: return .gray
        case .error: return .red
        case .listening: return .yellow
        case .processing: return .cyan
        case .paused: return .orange
        }
    }
}

struct StatusPill: View {
    let icon: String
    let label: String?
    let state: StatusPillState

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(state.color)

            Circle()
                .fill(state.color)
                .frame(width: 6, height: 6)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.7 : 1.0)

            if let label = label {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .onChange(of: state) { _, newState in
            updatePulse(newState)
        }
        .onAppear { updatePulse(state) }
    }

    private func updatePulse(_ s: StatusPillState) {
        switch s {
        case .listening, .processing:
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        default:
            withAnimation(.easeOut(duration: 0.3)) {
                isPulsing = false
            }
        }
    }
}
