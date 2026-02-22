# Voice Input System (iOS 26+)

## Overview

On-device voice input using Apple's `SpeechAnalyzer` API (iOS 26+). Enables hands-free interaction with wake word detection, speech capture, and silence-based utterance segmentation.

This feature is **optional** — the app works without it on iOS 17+. Voice input requires iOS 26.

## Flow

```
     ┌──────┐   wake word    ┌───────────┐   silence    ┌─────────┐
     │ IDLE │ ──────────────► │ LISTENING │ ───────────► │ SENDING │
     └──────┘                 └───────────┘              └────┬────┘
        ▲                                                     │
        │                    1 second delay                    │
        └─────────────────────────────────────────────────────┘
                        + pipeline reset
```

### States

| State | Expression | Behavior |
|-------|-----------|----------|
| `idle` | (no change) | Passively listening for wake word in transcription stream |
| `listening` | `listening` | User speech bubble shown, capturing utterance |
| `sending` | `sending` | Utterance sent to backend via WebSocket, waiting for response |

### Wake Word

Default: **「雪ちゃん」** (also matches 「ゆきちゃん」「ユキちゃん」)

Customize by modifying the `wakeWords` array in `VoiceInputManager.swift`.

### Silence Detection

After the last transcription update, a **2-second timer** starts. If no new text arrives, the utterance is considered complete.

Punctuation-only results (e.g., just "。") do not trigger send — the timer resets.

### Pipeline Reset

After each utterance cycle (sending → idle), the `SpeechAnalyzer` pipeline is fully rebuilt:
1. Cancel old recognition task
2. Finalize old analyzer
3. Create new `SpeechTranscriber` + `SpeechAnalyzer`
4. Create new `AsyncStream` for audio input
5. Resume audio buffer feeding

This prevents stale transcription text from the previous cycle causing false wake word detection.

### TTS Feedback Prevention

When the app plays audio (TTS response), voice input is **paused**:
- `pauseListening()` — stops feeding audio buffers to analyzer
- `resumeListening()` — resets pipeline and resumes

This prevents the avatar's own speech from being recognized as user input.

## Audio Pipeline

```
Microphone → AVAudioEngine (inputNode, 1024 buffer)
           → Format conversion (to SpeechAnalyzer optimal format)
           → AsyncStream<AnalyzerInput>
           → SpeechAnalyzer
           → SpeechTranscriber.results (AsyncSequence)
           → handleTranscriptionResult()
```

- Audio session: `.playAndRecord` with `.defaultToSpeaker`
- Buffer size: 1024 frames (for responsive partial results)
- Format converter: auto-created when input format ≠ analyzer format

## WebSocket Events

Voice input events broadcast to all WebSocket clients:

```json
// User spoke after wake word
{"event": "voice_input", "text": "今日の天気を教えて"}

// Debug logs
{"voiceDebug": "🎤 [idle] partial: こんにちは雪ちゃん"}
```

## Requirements

- iOS 26.0+
- Microphone permission
- Speech recognition permission
- Japanese speech model (auto-downloaded if needed)
