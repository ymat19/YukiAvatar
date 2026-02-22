# WebSocket Protocol Specification

The app runs a WebSocket server on **port 8765** (configurable). All communication is JSON text frames.

## Connection

```
ws://<iphone-ip>:8765
```

No authentication. LAN-only by design.

## Command → App (Client sends to iPhone)

### Speech + Expression (most common)

```json
{
  "speech": "Hello!",
  "expression": "happy",
  "audio": "<base64-encoded WAV>",
  "motion": "smallNod"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `speech` | string | No | Text to display in speech bubble |
| `expression` | string | No | Expression name (see Expression List) |
| `audio` | string | No | Base64-encoded WAV audio data |
| `motion` | string | No | Motion preset name (see Motion List) |
| `gesture` | string | No | DockKit built-in gesture (`nod`, `shake`) |
| `speechDuration` | number | No | How long to show speech bubble (seconds, default 5.0) |
| `interrupt` | boolean | No | If true, clear the speech queue before enqueuing |

When `audio` is present, the app plays it with lip-sync animation and dismisses the speech bubble after playback. When absent, the bubble auto-dismisses after `speechDuration` seconds.

Items are enqueued in a FIFO speech queue and processed sequentially. Each item can have its own expression and motion.

### Expression Only (no speech)

```json
{
  "expression": "thinking"
}
```

### DockKit Orientation Control

```json
// Rotation3D (absolute angle, radians)
{"pitch": 0, "yaw": 3.14, "roll": 0}

// Vector3D (alternative API)
{"pitch": 0, "yaw": 3.14, "roll": 0, "mode": "v3"}

// Angular velocity (rad/s × duration)
{"pitch": 0, "yaw": -1.5, "roll": 0, "mode": "velocity", "durationMs": 2100}
```

### Named Orientation

```json
{"orientation": "landscape"}
{"orientation": "portrait"}
```

### Music Mode

```json
{"musicPlaying": true}   // Triggers singing idle scene
{"musicPlaying": false}  // Returns to normal
```

### Commands

```json
{"command": "sleep"}       // Dim screen, stop camera, suspend tracking
{"command": "force_wake"}  // Wake from sleep/idle
```

## Queries → App (Client requests info)

### Capabilities

```json
{"query": "capabilities"}
```

Response:
```json
{
  "expressions": ["normal", "happy", "sad", ...],
  "motions": ["smallNod", "lookLeft", ...],
  "gestures": ["nod", "shake"],
  "speakers": [{"id": 24, "name": "WhiteCUL たのしい", "default": true}, ...],
  "voiceInput": true
}
```

### Queue Status

```json
{"query": "queue_status"}
```

Response:
```json
{"queue_length": 2, "is_processing": true}
```

### Debug Status

```json
{"query": "debug_status"}
```

```json
{"query": "silent_debug"}   // Same but doesn't trigger wake-up
```

### Voice Input Debug

```json
{"query": "voice_debug"}
```

## Events ← App (iPhone broadcasts to all clients)

| Event | Description |
|-------|-------------|
| `{"event": "playback_done"}` | Audio playback finished for current item |
| `{"event": "item_done", "queue_remaining": N}` | Speech queue item completed |
| `{"event": "queue_empty"}` | All queued items processed |
| `{"event": "voice_input", "text": "..."}` | User spoke (after wake word + silence detection) |
| `{"event": "sleep_done"}` | Sleep command executed |
| `{"event": "force_wake_done"}` | Wake command executed |
| `{"log": "..."}` | DockKit debug log |
| `{"voiceDebug": "..."}` | Voice input debug log |

## Expression List

29 expressions available (image must exist as `<name>.png` in Resources):

| Name | Visual Description |
|------|-------------------|
| `normal` | Default standing pose |
| `happy` | Peace sign, smile |
| `sad` | Teary eyes |
| `surprised` | Wide eyes, round mouth |
| `angry` | Arms crossed, frown |
| `shy` | Hand on cheek, blush |
| `smug` | Arms crossed, smirk |
| `love` | Heart eyes |
| `confused` | Half-closed eyes, sweat |
| `crying` | Sobbing, flailing |
| `excited` | Arms up, sparkles |
| `scared` | Panicking, white eyes |
| `sleepy` | Half-closed eyes |
| `wink` | Peace sign, one eye closed |
| `thinking` | Hand on cheek, contemplating |
| `rage` | Standing firm, furious eyebrows |
| `pout` | Sulking, puffed cheeks |
| `greeting` | Bowing, smile |
| `peace` | Double peace sign |
| `eat` | Eating pose |
| `explain` | Explaining gesture |
| `shh` | Shush pose, wink |
| `dizzy` | Spiral eyes, heavy sweat |
| `listening` | Phone pose, closed eyes |
| `sending` | Hands together, closed eyes |
| `sleeping` | Closed eyes (sleep mode) |
| `idle_snack` | Eating ice cream (idle) |
| `idle_singing` | Singing pose (idle) |
| `idle_bored` | Bored expression (idle) |

Internal-only (not settable via command): `blink`, `talking`, `talking_0/1/2`

## Motion Presets

| Name | Description |
|------|-------------|
| `smallNod` | Quick nod down and back |
| `lookLeft` | Glance left, return |
| `lookRight` | Glance right, return |
| `lookAround` | Look left then right |
| `thinking` | Slight tilt to one side |
| `excited` | Rapid nodding |
| `slowNodDown` | Slow downward tilt (dozing off) |
| `swaySinging` | Side-to-side sway |

## Audio Format

- **Format:** WAV (PCM)
- **Encoding:** Base64
- **Max message size:** 10 MB
- The app uses `AVAudioPlayer` for playback with speaker output
- Lip-sync is simple frame cycling (closed → half → open → half) at 120ms intervals
