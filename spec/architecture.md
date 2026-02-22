# Architecture Overview

## System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        AI Backend (Host)                        │
│                                                                 │
│  ┌──────────┐    ┌─────────┐    ┌──────────────────────────┐   │
│  │ AI Agent │───►│  TTS    │───►│ WebSocket Client Script  │   │
│  │ (Claude) │    │(VOICEVOX│    │ (sends JSON + base64 WAV │   │
│  │          │◄───│  etc.)  │    │  to iPhone app)          │   │
│  └──────────┘    └─────────┘    └────────────┬─────────────┘   │
│                                              │                  │
└──────────────────────────────────────────────┼──────────────────┘
                                   WebSocket (LAN:8765)
┌──────────────────────────────────────────────┼──────────────────┐
│                     iPhone App               │                  │
│                                              ▼                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    ContentView                          │   │
│  │  ┌──────────────┐  ┌───────────────┐  ┌─────────────┐  │   │
│  │  │ Expression   │  │ Speech Queue  │  │ WebSocket   │  │   │
│  │  │ Manager      │  │ Manager       │  │ Server      │  │   │
│  │  │ (29 faces)   │  │ (FIFO queue)  │  │ (port 8765) │  │   │
│  │  └──────┬───────┘  └───────┬───────┘  └──────┬──────┘  │   │
│  │         │                  │                  │         │   │
│  │  ┌──────▼───────┐  ┌──────▼────────┐         │         │   │
│  │  │ Auto-blink   │  │ Audio Player  │         │         │   │
│  │  │ Timer        │  │ + Lip Sync    │         │         │   │
│  │  └──────────────┘  └───────────────┘         │         │   │
│  │                                              │         │   │
│  │  ┌──────────────┐  ┌───────────────┐         │         │   │
│  │  │ DockKit      │  │ Voice Input   │◄────────┘         │   │
│  │  │ Manager      │  │ Manager       │ (events out)      │   │
│  │  │ (motor ctrl) │  │ (iOS 26+)     │                   │   │
│  │  └──────────────┘  └───────────────┘                   │   │
│  │                                                        │   │
│  │  ┌──────────────┐  ┌───────────────┐                   │   │
│  │  │ Idle Scene   │  │ Camera        │                   │   │
│  │  │ Manager      │  │ Manager       │                   │   │
│  │  └──────────────┘  └───────────────┘                   │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                │
└────────────────────────────────────────────────────────────────┘
                         │ DockKit Framework
                  ┌──────▼──────┐
                  │ Motorized   │
                  │ Phone Stand │
                  │ (optional)  │
                  └─────────────┘
```

## Data Flow

### Inbound (Backend → App)

1. Backend sends JSON via WebSocket (speech text + base64 audio + expression + motion)
2. `WebSocketServer` receives and calls `ContentView.handleWebSocketCommand()`
3. `ExpressionManager.handleCommand()` parses JSON into `CommandResult`
4. If speech/audio present → `SpeechQueueManager.enqueue()` (FIFO)
5. Queue processes items sequentially:
   - Set expression
   - Trigger DockKit motion/gesture
   - Show speech bubble
   - Play audio with lip-sync
   - On `playback_done` → process next item
6. When queue empties → dismiss speech bubbles, reset expression

### Outbound (App → Backend)

1. Voice input: wake word detection → speech capture → silence timeout
2. `VoiceInputManager` broadcasts `{"event": "voice_input", "text": "..."}` via WebSocket
3. Backend processes and sends response (new speech/expression command)

### Idle Flow

1. `IdleSceneManager` evaluates every 15 seconds
2. Based on idle time: thinking (5min) → snack (8min) → bored (15min) → sleeping (30min)
3. Night mode: screen dims after 2 minutes
4. Any WebSocket command or screen tap → wake from idle

## Key Design Decisions

- **WebSocket server on the phone** (not client): The phone is the always-on display device. Multiple backends can connect simultaneously.
- **Base64 audio over WebSocket**: Simpler than HTTP streaming. 10MB message limit is sufficient for sentence-length TTS.
- **Speech queue**: Prevents overlapping audio. Each item carries its own expression, enabling per-sentence emotion changes.
- **DockKit system tracking toggle**: Must disable tracking before velocity commands, re-enable after. Otherwise the auto-tracking fights manual control.
- **Camera required for DockKit**: `AVCaptureSession` must be active even if not displayed, as DockKit needs camera access for tracking features.

## Expression Image System

The app loads images by name from the app bundle:

```
Resources/
  normal.png
  happy.png
  sad.png
  talking_0.png  (mouth closed, for lip-sync)
  talking_1.png  (mouth half-open)
  talking_2.png  (mouth open)
  blink.png      (auto-blink overlay)
  ...
```

To create your own avatar:
1. Design a base character pose
2. Create 29 expression variants (see `Expression` enum in `ExpressionManager.swift`)
3. Create 3 talking frames for lip-sync (`talking_0`, `talking_1`, `talking_2`)
4. Create 1 blink frame
5. Export as PNG, named to match the enum cases
6. Place in `HelloWorld/Resources/`
