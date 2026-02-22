#!/bin/bash
# yuki_cmd.sh — Send speech + expression + motion to iPhone via WebSocket
#
# Requires: VOICEVOX running on localhost:50021, ws_send.py in same directory
#
# Single sentence:
#   yuki_cmd.sh "テキスト" [--expression happy] [--motion smallNod] [--speaker 24]
#
# Multiple sentences (use --- as separator):
#   yuki_cmd.sh "こんにちは" --expression happy --- "元気？" --expression normal --- "行こう！" --expression excited
#
# Options:
#   --expression <name>  Expression to show (see spec/websocket-protocol.md)
#   --motion <name>      DockKit motion preset
#   --speaker <id>       VOICEVOX speaker ID (default: 24)
#   --display <text>     Display text (different from TTS text, for kanji/English display)
#   --no-wait            Don't wait for playback completion
#   ---                  Separator between sentences (each gets its own expression/motion)
#
# Environment:
#   VOICEVOX_URL         VOICEVOX API endpoint (default: http://localhost:50021)
#   YUKI_IPHONE_IP       iPhone IP (passed through to ws_send.py)
#   YUKI_IPHONE_PORT     iPhone port (passed through to ws_send.py)
#
# Global --speaker applies to all segments unless overridden per-segment.

set -e

NO_WAIT=false
# Check for --no-wait flag
NEW_ARGS=()
for _a in "$@"; do
    if [ "$_a" = "--no-wait" ]; then
        NO_WAIT=true
    else
        NEW_ARGS+=("$_a")
    fi
done
set -- "${NEW_ARGS[@]}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOICEVOX="${VOICEVOX_URL:-http://localhost:50021}"
TMP_DIR="/tmp/voicevox"
DEFAULT_SPEAKER=24

# ── Parse arguments into segments ──

GLOBAL_SPEAKER="$DEFAULT_SPEAKER"
SEGMENTS=()   # Array of "TEXT|EXPRESSION|MOTION|SPEAKER|DISPLAY"
CUR_TEXT=""
CUR_EXPR=""
CUR_MOTION=""
CUR_SPEAKER=""
CUR_DISPLAY=""

flush_segment() {
    if [ -n "$CUR_TEXT" ]; then
        local spk="${CUR_SPEAKER:-$GLOBAL_SPEAKER}"
        local disp="${CUR_DISPLAY:-$CUR_TEXT}"
        SEGMENTS+=("${CUR_TEXT}|${CUR_EXPR}|${CUR_MOTION}|${spk}|${disp}")
    fi
    CUR_TEXT=""
    CUR_EXPR=""
    CUR_MOTION=""
    CUR_SPEAKER=""
    CUR_DISPLAY=""
}

# First pass: extract global --speaker if it appears before any text
ARGS=("$@")
FILTERED=()
i=0
while [ $i -lt ${#ARGS[@]} ]; do
    if [ "${ARGS[$i]}" = "--speaker" ] && [ -z "$CUR_TEXT" ] && [ ${#SEGMENTS[@]} -eq 0 ]; then
        GLOBAL_SPEAKER="${ARGS[$((i+1))]}"
        i=$((i+2))
    else
        FILTERED+=("${ARGS[$i]}")
        i=$((i+1))
    fi
done

# Second pass: parse segments
for arg in "${FILTERED[@]}"; do
    case "$arg" in
        ---)
            flush_segment
            ;;
        --expression)
            NEXT_IS="expression"
            ;;
        --motion)
            NEXT_IS="motion"
            ;;
        --speaker)
            NEXT_IS="speaker"
            ;;
        --display)
            NEXT_IS="display"
            ;;
        *)
            if [ "${NEXT_IS:-}" = "expression" ]; then
                CUR_EXPR="$arg"
                NEXT_IS=""
            elif [ "${NEXT_IS:-}" = "motion" ]; then
                CUR_MOTION="$arg"
                NEXT_IS=""
            elif [ "${NEXT_IS:-}" = "speaker" ]; then
                CUR_SPEAKER="$arg"
                NEXT_IS=""
            elif [ "${NEXT_IS:-}" = "display" ]; then
                CUR_DISPLAY="$arg"
                NEXT_IS=""
            elif [ -z "$CUR_TEXT" ]; then
                CUR_TEXT="$arg"
            fi
            ;;
    esac
done
flush_segment

if [ ${#SEGMENTS[@]} -eq 0 ]; then
    echo "Usage: $0 \"テキスト\" [--expression happy] [--motion smallNod] [--speaker 24]" >&2
    echo "  Multiple: $0 \"文1\" --expression happy --- \"文2\" --expression sad" >&2
    exit 1
fi

mkdir -p "$TMP_DIR"

TOTAL=${#SEGMENTS[@]}
echo "Processing $TOTAL segment(s)..." >&2

for idx in "${!SEGMENTS[@]}"; do
    IFS='|' read -r TEXT EXPRESSION MOTION SPEAKER DISPLAY <<< "${SEGMENTS[$idx]}"
    SEG_NUM=$((idx+1))
    echo "[$SEG_NUM/$TOTAL] \"$TEXT\" (expr=$EXPRESSION, motion=$MOTION, speaker=$SPEAKER)" >&2

    # 1. Generate audio query
    curl -sf -X POST --get \
        --data-urlencode "text=$TEXT" \
        --data-urlencode "speaker=$SPEAKER" \
        "$VOICEVOX/audio_query" -o "$TMP_DIR/query.json"

    # 2. Synthesize WAV
    curl -sf -X POST -H "Content-Type: application/json" \
        -d @"$TMP_DIR/query.json" \
        "$VOICEVOX/synthesis?speaker=$SPEAKER" -o "$TMP_DIR/iphone_voice.wav"

    # 3. Get WAV size (macOS: stat -f%z, Linux: stat -c%s)
    if stat -f%z "$TMP_DIR/iphone_voice.wav" &>/dev/null; then
        WAV_SIZE=$(stat -f%z "$TMP_DIR/iphone_voice.wav")
    else
        WAV_SIZE=$(stat -c%s "$TMP_DIR/iphone_voice.wav")
    fi
    echo "  WAV: $WAV_SIZE bytes" >&2

    # 4. Base64 encode (macOS: base64 -i, Linux: base64)
    if base64 -i "$TMP_DIR/iphone_voice.wav" &>/dev/null; then
        AUDIO_B64=$(base64 -i "$TMP_DIR/iphone_voice.wav")
    else
        AUDIO_B64=$(base64 -w0 "$TMP_DIR/iphone_voice.wav")
    fi

    # 5. Build JSON command
    JSON=$(python3 -c "
import json, sys
cmd = {'speech': sys.argv[1], 'audio': sys.argv[2]}
if sys.argv[3]: cmd['expression'] = sys.argv[3]
if sys.argv[4]: cmd['motion'] = sys.argv[4]
print(json.dumps(cmd, ensure_ascii=False))
" "$DISPLAY" "$AUDIO_B64" "$EXPRESSION" "$MOTION")

    echo "  Sending $(echo "$JSON" | wc -c | tr -d ' ') bytes..." >&2

    # 6. Send via WebSocket (wait only on last segment to get queue_empty)
    if [ $SEG_NUM -eq $TOTAL ] && [ "$NO_WAIT" = false ]; then
        python3 "$SCRIPT_DIR/ws_send.py" "$JSON" --wait --timeout 30
    else
        python3 "$SCRIPT_DIR/ws_send.py" "$JSON"
    fi
done
