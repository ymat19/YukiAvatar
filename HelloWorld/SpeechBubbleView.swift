import SwiftUI

enum BubbleStyle {
    case assistant          // 雪の発話（白背景）
    case previousAssistant  // 1つ前の雪の発話（暗い不透明背景）
    case user               // ユーザの発話（緑背景）
    case sending            // 送信中（青背景）
}

struct SpeechBubbleView: View {
    let text: String
    var style: BubbleStyle = .assistant
    
    private var backgroundColor: Color {
        switch style {
        case .assistant:
            return Color.white.opacity(0.95)
        case .previousAssistant:
            return Color(white: 0.15).opacity(0.85)
        case .user:
            return Color.green.opacity(0.85)
        case .sending:
            return Color.blue.opacity(0.75)
        }
    }
    
    private var textColor: Color {
        switch style {
        case .assistant:
            return .black
        case .previousAssistant:
            return Color(white: 0.7)
        case .user:
            return .white
        case .sending:
            return .white
        }
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .medium))
            .foregroundColor(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(backgroundColor)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
            .multilineTextAlignment(.leading)
            .lineLimit(6)
            .minimumScaleFactor(0.6)
    }
}
