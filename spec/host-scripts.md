# Host Scripts — Backend Control Tools

Scripts that run on your **host machine** (Mac, Linux, etc.) to control the iPhone avatar app via WebSocket.

## Prerequisites

- **Python 3.7+** (standard library only, no pip packages)
- **VOICEVOX** running on the host (default: `http://localhost:50021`)
  - Download: https://voicevox.hiroshiba.jp/
  - Any VOICEVOX-compatible engine works (SHAREVOX, COEIROINK, etc.)
- **curl** (for VOICEVOX API calls)
- iPhone app running and reachable on LAN

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `YUKI_IPHONE_IP` | (required) | iPhone's IP address on LAN |
| `YUKI_IPHONE_PORT` | `8765` | WebSocket server port |
| `VOICEVOX_URL` | `http://localhost:50021` | VOICEVOX API endpoint |

## Scripts

### `yuki_cmd.sh` — Main TTS + Expression Command

The primary script for sending speech with expression and motion.

```bash
# Simple speech
./yuki_cmd.sh "こんにちは" --expression happy

# With motion (DockKit)
./yuki_cmd.sh "こんにちは" --expression happy --motion smallNod

# Multiple sentences with per-sentence expressions
./yuki_cmd.sh \
  "おはようございます！" --expression greeting --motion smallNod \
  --- \
  "今日もがんばりましょう！" --expression excited

# Different display text (for English/technical terms in TTS)
# TTS reads hiragana, bubble shows kanji/English
./yuki_cmd.sh "えーぴーあいのせっていが完了しました" \
  --display "APIの設定が完了しました" \
  --expression happy

# Change VOICEVOX speaker voice
./yuki_cmd.sh "悲しいお知らせです" --expression sad --speaker 25

# Fire-and-forget (don't wait for playback to finish)
./yuki_cmd.sh "はい！" --expression happy --no-wait
```

**Flow:**
1. Sends text to VOICEVOX → receives WAV audio
2. Base64-encodes the WAV
3. Sends JSON `{speech, audio, expression, motion}` via WebSocket to iPhone
4. App plays audio with lip-sync, shows speech bubble, sets expression

**Options:**

| Option | Description |
|--------|-------------|
| `--expression <name>` | Expression to display (required for each sentence) |
| `--motion <name>` | DockKit motion preset |
| `--speaker <id>` | VOICEVOX speaker ID (default: 24) |
| `--display <text>` | Text for speech bubble (when TTS text differs) |
| `--no-wait` | Don't wait for playback completion |
| `---` | Separator between sentences |

### `ws_send.py` — Raw WebSocket Client

Low-level WebSocket client for sending arbitrary JSON commands.

```bash
# Send expression only
python3 ws_send.py '{"expression": "thinking"}'

# Query capabilities
python3 ws_send.py '{"query": "capabilities"}' --wait --timeout 5

# DockKit control
python3 ws_send.py '{"pitch": 0, "yaw": -1.5, "roll": 0, "mode": "velocity", "durationMs": 2100}'

# Music mode
python3 ws_send.py '{"musicPlaying": true}'

# Sleep/wake
python3 ws_send.py '{"command": "sleep"}'
python3 ws_send.py '{"command": "force_wake"}' --wait --timeout 5
```

**Features:**
- Pure Python, no dependencies (uses raw TCP + WebSocket framing)
- Supports large payloads (up to 2^63 bytes — needed for base64 audio)
- `--wait` flag listens for response events
- `--timeout N` sets response wait timeout (default: 5 seconds)

## VOICEVOX Speaker IDs

Common speakers (check your VOICEVOX installation for full list):

| ID | Name | Use Case |
|----|------|----------|
| 24 | WhiteCUL たのしい | Default — cheerful |
| 23 | WhiteCUL ノーマル | Calm explanation |
| 25 | WhiteCUL かなしい | Sad delivery |
| 26 | WhiteCUL びえーん | Crying |

Get full list: `curl http://localhost:50021/speakers | python3 -m json.tool`

## Integration with AI Agents

These scripts are designed to be called by AI agents (Claude, etc.) running on a host machine. Typical flow:

1. AI agent decides what to say and which expression to use
2. Calls `yuki_cmd.sh` with TTS text (hiragana for pronunciation) + `--display` (kanji for bubble)
3. Script handles VOICEVOX synthesis + WebSocket delivery
4. iPhone app plays audio, shows expression, moves DockKit stand

For voice input (user → AI), the app broadcasts `{"event": "voice_input", "text": "..."}` via WebSocket. Your backend listens for these events and processes them.
