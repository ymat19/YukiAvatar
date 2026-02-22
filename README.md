# Yuki Avatar — AI-Driven Physical Avatar System for iPhone

> **⚠️ This is a reference snapshot, not a maintained project.**
> The purpose of this repository is to serve as a codebase that you can show to an AI assistant (Claude, ChatGPT, Codex, etc.) to help you build a similar system. It is not intended to be cloned and run as-is.

## Screenshots

| Idle | Voice Input | Thinking | Speaking |
|------|-------------|----------|----------|
| ![Idle](docs/screenshots/01-idle.png) | ![Voice Input](docs/screenshots/02-voice-input.png) | ![Thinking](docs/screenshots/03-thinking.png) | ![Speaking](docs/screenshots/04-speaking.png) |

> Character art: [WhiteCUL立ち絵素材 by moiky](https://seiga.nicovideo.jp/seiga/im11047926) — not included in this repository. You must supply your own images.

## What Is This?

An iOS app that turns an iPhone (mounted on an [Insta360 Flow Pro](https://www.insta360.com/product/insta360-flow-pro) or any DockKit-compatible motorized stand) into a **physical AI avatar** with:

- 🎭 **29 expressions** — pre-composed character images swapped in real-time
- 🗣️ **Text-to-speech with lip sync** — audio streamed from a server, mouth animation synced to playback
- 💬 **Speech bubbles** — assistant and user speech displayed on screen
- 🎤 **Voice input** — on-device wake word detection + speech-to-text (iOS 26+ SpeechAnalyzer)
- 🤖 **DockKit motor control** — nod, shake, look around, custom velocity/rotation sequences
- 🌙 **Idle scenes** — sleeping, snacking, singing, thinking, bored (with burn-in protection)
- 📡 **WebSocket control** — all features controllable via JSON commands over LAN

## Architecture Overview

```
┌─────────────┐     WebSocket (8765)     ┌──────────────┐
│  AI Backend  │ ◄──────────────────────► │  iPhone App  │
│  (any host)  │   JSON commands + audio  │  (this code) │
└─────────────┘                           └──────┬───────┘
                                                 │ DockKit API
                                          ┌──────▼───────┐
                                          │ Motorized     │
                                          │ Phone Stand   │
                                          └──────────────┘
```

The app is the **display + motor controller**. Your AI backend synthesizes speech (e.g., VOICEVOX, ElevenLabs), encodes it as base64 WAV, and sends it along with expression/motion commands via WebSocket.

## File Overview

| File | Role |
|------|------|
| `ContentView.swift` | Main UI — composites expression images, speech bubbles, status bar; routes WebSocket commands |
| `WebSocketServer.swift` | LAN WebSocket server (port 8765) using Network.framework |
| `ExpressionManager.swift` | Expression enum (29 types), auto-blink, JSON command parser |
| `DockKitManager.swift` | DockKit accessory control — gestures, orientation, velocity, motion presets |
| `AudioPlayerManager.swift` | Base64 WAV playback + lip-sync timer |
| `SpeechQueueManager.swift` | FIFO queue for sequential speech items with expression/motion per item |
| `VoiceInputManager.swift` | iOS 26 SpeechAnalyzer — wake word → capture → send to backend |
| `IdleSceneManager.swift` | Time/activity-based idle animations with screen dimming |
| `SpeechBubbleView.swift` | Styled speech bubble (assistant/user/previous/sending) |
| `StatusBarView.swift` | Connection status pills (WebSocket, DockKit, mic, audio) |
| `CameraManager.swift` | AVCaptureSession for camera preview (DockKit requires active camera) |

See [`spec/`](spec/) for detailed documentation:
- [`architecture.md`](spec/architecture.md) — System diagram and data flow
- [`websocket-protocol.md`](spec/websocket-protocol.md) — Full WebSocket API reference
- [`host-scripts.md`](spec/host-scripts.md) — Backend control scripts
- [`voice-input.md`](spec/voice-input.md) — On-device voice input (iOS 26+)
- [`dockkit-integration.md`](spec/dockkit-integration.md) — Motorized stand control
- [`idle-scenes.md`](spec/idle-scenes.md) — Idle animation system

## Host Scripts (Backend Control)

The `host-scripts/` directory contains the backend tools that control the app:

| Script | Purpose |
|--------|---------|
| `yuki_cmd.sh` | Main command — TTS synthesis (VOICEVOX) + expression + motion, sent as one WebSocket message |
| `ws_send.py` | Raw WebSocket client for sending arbitrary JSON commands |

```bash
# Quick start
export YUKI_IPHONE_IP=192.168.0.28  # your iPhone's IP
./host-scripts/yuki_cmd.sh "こんにちは" --expression happy --motion smallNod
```

See [`spec/host-scripts.md`](spec/host-scripts.md) for full documentation.

## What's NOT Included

- **Character images** — The original uses [WhiteCUL](https://www.whitecul.com/) (copyrighted). You must supply your own PNG images named to match the `Expression` enum cases in `ExpressionManager.swift`.
- **TTS backend** — The app plays audio sent to it; you need your own speech synthesis pipeline.
- **AI orchestration** — The WebSocket protocol is documented in `spec/websocket-protocol.md`. Build your own controller.

## How to Use This Repository

1. **Show this code to your AI assistant** and describe what you want to build
2. The AI can understand the architecture from the code + specs and help you adapt it
3. Replace the expression images with your own character art
4. Build your own backend that speaks the WebSocket protocol
5. Optionally integrate DockKit for physical movement

## Requirements

- iOS 17.0+ (iOS 26+ for voice input features)
- Xcode 26+
- DockKit-compatible stand (optional, for motor control)
- A TTS engine on your network (VOICEVOX, ElevenLabs, etc.)

## Credits

- **Character art in screenshots:** [WhiteCUL立ち絵素材 by moiky](https://seiga.nicovideo.jp/seiga/im11047926) — used under the original distribution terms. The character image files are **not included** in this repository.
- **WhiteCUL:** A character from the [VOICEVOX](https://voicevox.hiroshiba.jp/) project

## License

MIT — The code is free to use. Character art is NOT included and must be sourced separately.
Screenshots contain WhiteCUL character art by moiky, used for demonstration purposes only.
