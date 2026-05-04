import std/[unittest, sequtils, sha1, base64]
import nimmax/websocket

suite "WebSocket Frame Encoding":
  test "encode small text frame":
    let frame = encodeFrame(wsText, "Hello")
    check frame.len > 0
    check (frame[0] and 0x80'u8) != 0
    check (frame[0] and 0x0F'u8) == byte(wsText)
    check frame[1] == 5'u8
    check cast[string](frame[2 .. ^1]) == "Hello"

  test "encode small binary frame":
    let data = @[1'u8, 2'u8, 3'u8]
    let frame = encodeFrame(wsBinary, data)
    check frame.len > 0
    check (frame[0] and 0x80'u8) != 0
    check (frame[0] and 0x0F'u8) == byte(wsBinary)
    check frame[1] == 3'u8
    check frame[2 .. ^1] == data

  test "encode continuation frame (fin=false)":
    let frame = encodeFrame(wsText, "data", fin = false)
    check (frame[0] and 0x80'u8) == 0
    check (frame[0] and 0x0F'u8) == byte(wsText)

  test "encode frame with 126 extended length":
    var payload = newString(200)
    for i in 0 ..< 200: payload[i] = 'A'
    let frame = encodeFrame(wsText, payload)
    check frame[1] == 126'u8
    let extLen = int(frame[2]) shl 8 or int(frame[3])
    check extLen == 200

  test "encode frame with 127 extended length":
    var payload = newString(70000)
    for i in 0 ..< 70000: payload[i] = 'B'
    let frame = encodeFrame(wsBinary, payload)
    check frame[1] == 127'u8

  test "encode ping frame":
    let frame = encodeFrame(wsPing, "ping")
    check (frame[0] and 0x0F'u8) == byte(wsPing)

  test "encode pong frame":
    let frame = encodeFrame(wsPong, "pong")
    check (frame[0] and 0x0F'u8) == byte(wsPong)

  test "encode close frame":
    let frame = encodeFrame(wsClose, "")
    check (frame[0] and 0x0F'u8) == byte(wsClose)

suite "WebSocket Close Frame":
  test "encode close frame with code":
    let frame = encodeCloseFrame(1000)
    check frame.len >= 4
    let code = int(frame[2]) shl 8 or int(frame[3])
    check code == 1000

  test "encode close frame with code and reason":
    let frame = encodeCloseFrame(1001, "Going Away")
    check frame.len >= 4
    let code = int(frame[2]) shl 8 or int(frame[3])
    check code == 1001

  test "encode close frame with normal closure":
    let frame = encodeCloseFrame(1000, "")
    check frame.len >= 4
    let code = int(frame[2]) shl 8 or int(frame[3])
    check code == 1000

suite "WebSocket Handshake Key Generation":
  test "accept key is correct sha1+base64":
    let key = "dGhlIHNhbXBsZSBub25jZQ=="
    let acceptKey = encode(secureHash(key & "258EAFA5-E914-47DA-95CA-5AB9E6FE45D5").Sha1Digest)
    let expected = "IG/rnRztVh9ehYxKwV08UDJZHn8="
    check acceptKey == expected

suite "WebSocket Opcode Values":
  test "opcode values match RFC 6455":
    check int(wsContinuation) == 0x0
    check int(wsText) == 0x1
    check int(wsBinary) == 0x2
    check int(wsClose) == 0x8
    check int(wsPing) == 0x9
    check int(wsPong) == 0xA

suite "WebSocket Ready State":
  test "initial state is connecting":
    check int(wsConnecting) == 0
    check int(wsOpen) == 1
    check int(wsClosing) == 2
    check int(wsClosed) == 3
