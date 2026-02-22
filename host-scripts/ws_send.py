"""
WebSocket client for sending commands to the Yuki Avatar app.

Usage:
    python3 ws_send.py '{"expression": "happy"}'
    python3 ws_send.py '{"speech": "Hello", "audio": "..."}' --wait --timeout 30

Environment:
    YUKI_IPHONE_IP   - iPhone IP address (required)
    YUKI_IPHONE_PORT - WebSocket port (default: 8765)
"""

import asyncio, os, sys, base64, struct, json

iPHONE_IP = os.environ.get("YUKI_IPHONE_IP")
if not iPHONE_IP:
    print("Error: YUKI_IPHONE_IP environment variable is required", file=sys.stderr)
    sys.exit(1)
iPHONE_PORT = int(os.environ.get("YUKI_IPHONE_PORT", "8765"))

def decode_ws_frame(data):
    """Decode a WebSocket frame, return (payload_str, remaining_bytes)"""
    if len(data) < 2:
        return None, data
    opcode = data[0] & 0x0f
    masked = (data[1] & 0x80) != 0
    length = data[1] & 0x7f
    offset = 2
    if length == 126:
        if len(data) < 4: return None, data
        length = struct.unpack('>H', data[2:4])[0]
        offset = 4
    elif length == 127:
        if len(data) < 10: return None, data
        length = struct.unpack('>Q', data[2:10])[0]
        offset = 10
    if masked:
        offset += 4
    if len(data) < offset + length:
        return None, data
    payload = data[offset:offset+length]
    if opcode == 0x01:  # text
        return payload.decode('utf-8', errors='replace'), data[offset+length:]
    return None, data[offset+length:]

def encode_ws_frame(data_bytes):
    """Encode a masked WebSocket text frame (supports payloads up to 2^63)"""
    frame = bytearray([0x81])  # FIN + text opcode
    length = len(data_bytes)
    mask_key = os.urandom(4)
    if length <= 125:
        frame.append(0x80 | length)
    elif length <= 65535:
        frame.append(0x80 | 126)
        frame.extend(struct.pack('>H', length))
    else:
        frame.append(0x80 | 127)
        frame.extend(struct.pack('>Q', length))
    frame.extend(mask_key)
    frame.extend(bytes(b ^ mask_key[i % 4] for i, b in enumerate(data_bytes)))
    return bytes(frame)

async def send(msg, wait_response=False, timeout=5):
    reader, writer = await asyncio.open_connection(iPHONE_IP, iPHONE_PORT)
    key = base64.b64encode(os.urandom(16)).decode()
    handshake = (
        f'GET / HTTP/1.1\r\n'
        f'Host: {iPHONE_IP}:{iPHONE_PORT}\r\n'
        f'Upgrade: websocket\r\n'
        f'Connection: Upgrade\r\n'
        f'Sec-WebSocket-Key: {key}\r\n'
        f'Sec-WebSocket-Version: 13\r\n'
        f'\r\n'
    )
    writer.write(handshake.encode())
    await writer.drain()
    await reader.read(1024)
    
    data = msg.encode()
    frame = encode_ws_frame(data)
    writer.write(frame)
    await writer.drain()
    log_msg = msg if len(msg) <= 200 else f"{msg[:80]}...({len(msg)} chars)"
    print(f'Sent: {log_msg}')
    
    if wait_response:
        buf = b''
        try:
            end_time = asyncio.get_event_loop().time() + timeout
            while asyncio.get_event_loop().time() < end_time:
                remaining = end_time - asyncio.get_event_loop().time()
                chunk = await asyncio.wait_for(reader.read(4096), timeout=remaining)
                if not chunk:
                    break
                buf += chunk
                while buf:
                    text, buf = decode_ws_frame(buf)
                    if text is None:
                        break
                    # Skip voiceDebug messages (noisy speech recognition partials)
                    try:
                        parsed = json.loads(text)
                        if 'voiceDebug' in parsed:
                            continue
                    except (json.JSONDecodeError, TypeError):
                        pass
                    print(f'Response: {text}')
        except (asyncio.TimeoutError, ConnectionError):
            pass
    
    writer.close()

if __name__ == '__main__':
    msg = sys.argv[1] if len(sys.argv) > 1 else 'normal'
    wait = '--wait' in sys.argv
    timeout = 5
    for i, a in enumerate(sys.argv):
        if a == '--timeout' and i+1 < len(sys.argv):
            timeout = float(sys.argv[i+1])
    asyncio.run(send(msg, wait_response=wait, timeout=timeout))
