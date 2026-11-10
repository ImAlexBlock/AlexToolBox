import XCTest
@testable import HeadsetControl

final class OpoProtocolTests: XCTestCase {

    // MARK: 帧编码

    /// 文档 §5.1 的表是实测抓包得来的，编码必须逐字节吻合。
    func testNoiseModeFramesMatchCapturedBytes() {
        let expected: [NoiseMode: String] = [
            .off:          "aa0a00000404000300010101",
            .reduction:    "aa0a00000404000300010102",
            .transparency: "aa0a00000404000300010104",
            .adaptive:     "aa0b0000040400040001010008",
        ]
        for (mode, wire) in expected {
            let tlv = OpoFrame.tlv(cmd: OpoCommand.setNoiseReduction, seq: 0, payload: mode.payload)
            XCTAssertEqual(OpoFrame.encode(tlv: tlv).hex, wire, "mode \(mode.title)")
        }
    }

    func testPollFrameMatchesCapturedBytes() {
        // 实测发送：查询当前档位
        let tlv = OpoFrame.tlv(cmd: OpoCommand.pollDeviceInfo, seq: 0x62, payload: [0x01, 0x01])
        XCTAssertEqual(OpoFrame.encode(tlv: tlv).hex, "aa0900000c016202000101")
    }

    func testLeb128() {
        XCTAssertEqual(OpoFrame.leb128(0).hex, "00")
        XCTAssertEqual(OpoFrame.leb128(127).hex, "7f")
        XCTAssertEqual(OpoFrame.leb128(128).hex, "8001")
        XCTAssertEqual(OpoFrame.leb128(300).hex, "ac02")
    }

    // MARK: 模式位图

    /// 白名单 protocolIndex → 位图。idx ≥ 8 时位数组增长到 2 字节。
    func testModePayloadBitmask() {
        XCTAssertEqual(NoiseMode.off.payload, [0x01, 0x01, 0x01])
        XCTAssertEqual(NoiseMode.reduction.payload, [0x01, 0x01, 0x02])
        XCTAssertEqual(NoiseMode.transparency.payload, [0x01, 0x01, 0x04])
        XCTAssertEqual(NoiseMode.adaptive.payload, [0x01, 0x01, 0x00, 0x08])
    }

    /// 耳机回的是实际子模式，必须归一到 UI 的四个档。
    func testReportedSubmodeMapping() {
        let cases: [(Int, NoiseMode)] = [
            (0, .off), (3, .off),
            (1, .reduction), (4, .reduction), (5, .reduction), (6, .reduction), (7, .reduction),
            (2, .transparency), (8, .transparency),
            (11, .adaptive),
        ]
        for (index, expected) in cases {
            XCTAssertEqual(NoiseMode.matching(reportedIndex: index), expected, "idx \(index)")
        }
        XCTAssertNil(NoiseMode.matching(reportedIndex: 9))
        XCTAssertNil(NoiseMode.matching(reportedIndex: 10))
    }

    // MARK: 拆帧

    func testDecodeSingleFrame() throws {
        let decoder = OpoFrameDecoder()
        // 实测 ACK：cmd 0x8404 = 1028 的响应，seq 回显，payload 一个状态字节
        let packets = decoder.append("aa080000048461010000".bytes)
        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(OpoPacket(tlv: packets[0]))
        XCTAssertEqual(packet.command, 0x8404)
        XCTAssertEqual(packet.sequence, 0x61)
        XCTAssertEqual(packet.payload, [0x00])
    }

    /// 实测里一次读回过两帧（24 字节），缓冲区必须能连续吐包。
    func testDecodeTwoFramesInOneRead() {
        let decoder = OpoFrameDecoder()
        // 实测出现过的事件帧 + ACK 帧挤在同一次读取里
        let combined = "aa0c00000402ff05000301010800" + "aa080000048461010000"
        let packets = decoder.append(combined.bytes)
        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual(OpoPacket(tlv: packets[0])?.command, 0x0204)
        XCTAssertEqual(OpoPacket(tlv: packets[1])?.command, 0x8404)
    }

    /// 字节被 TCP/串口式地切开时，必须等够再出包。
    func testDecodeIncrementalFeed() throws {
        let wire = "aa0c00000402ff05000301010800".bytes
        let decoder = OpoFrameDecoder()
        var packets: [[UInt8]] = []
        for byte in wire {
            packets += decoder.append([byte])
        }
        XCTAssertEqual(packets.count, 1)
        // TLV = 04 02 ff 05 00 | 03 01 01 08 00
        XCTAssertEqual(OpoPacket(tlv: packets[0])?.payload, [0x03, 0x01, 0x01, 0x08, 0x00])
    }

    func testDecodeSkipsGarbageBeforeSync() {
        let decoder = OpoFrameDecoder()
        let packets = decoder.append("deadbeef".bytes + "aa080000048461010000".bytes)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(OpoPacket(tlv: packets[0])?.command, 0x8404)
    }

    /// 分片帧（status 1/2/3）要拼回一个 TLV。
    /// 帧头 = AA | LEB128(payload+3) | status | 00 | FSN
    func testDecodeFragmentedFrame() throws {
        let decoder = OpoFrameDecoder()
        // 完整 TLV = 04 04 01 03 00 | 01 01 02，切成 5 + 3 两片
        let first = "aa080100000404010300"          // status=1 首片，FSN=0
        let last = "aa06030001010102"               // status=3 末片，FSN=1
        var packets = decoder.append(first.bytes)
        XCTAssertTrue(packets.isEmpty, "首片不应单独出包")
        packets = decoder.append(last.bytes)
        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(OpoPacket(tlv: packets[0]))
        XCTAssertEqual(packet.command, 0x0404)
        XCTAssertEqual(packet.payload, [0x01, 0x01, 0x02])
    }

    /// 三片：首/中/末。
    func testDecodeThreeFragmentFrame() throws {
        let decoder = OpoFrameDecoder()
        var packets = decoder.append("aa050100000404".bytes)
        packets += decoder.append("aa06020001010300".bytes)
        XCTAssertTrue(packets.isEmpty, "首片和中片都不应出包")
        packets += decoder.append("aa06030002010102".bytes)
        XCTAssertEqual(packets.count, 1)
        let packet = try XCTUnwrap(OpoPacket(tlv: packets[0]))
        XCTAssertEqual(packet.command, 0x0404)
        XCTAssertEqual(packet.payload, [0x01, 0x01, 0x02])
    }

    // MARK: 包解析

    func testPacketParsesPollResponse() throws {
        // 实测：查询 268 后耳机回当前档位（自适应 idx 11）
        let decoder = OpoFrameDecoder()
        let packets = decoder.append("aa0c00000c816305000001010008".bytes)
        let packet = try XCTUnwrap(OpoPacket(tlv: try XCTUnwrap(packets.first)))
        XCTAssertEqual(packet.command, 0x810C)
        // [0]=状态 [1]=0x01 回显 [2]=0x01 [3...]=位图
        XCTAssertEqual(packet.payload, [0x00, 0x01, 0x01, 0x00, 0x08])
    }

    func testPacketParsesEventNotification() throws {
        // 实测：按键/切换后耳机推的事件
        let decoder = OpoFrameDecoder()
        let packets = decoder.append("aa0c00000402ff05000301010400".bytes)
        let packet = try XCTUnwrap(OpoPacket(tlv: try XCTUnwrap(packets.first)))
        XCTAssertEqual(packet.command, 0x0204)
        // [0]=事件类型 3 [1]=0x01 [2]=载荷类型 1 [3...]=位图
        XCTAssertEqual(packet.payload, [0x03, 0x01, 0x01, 0x04, 0x00])
    }

    func testNoiseMaskFirstIndex() {
        XCTAssertEqual(NoiseMask.firstIndex([0x01]), 0)
        XCTAssertEqual(NoiseMask.firstIndex([0x04]), 2)
        XCTAssertEqual(NoiseMask.firstIndex([0x00, 0x08]), 11)
        XCTAssertNil(NoiseMask.firstIndex([0x00, 0x00]))
        XCTAssertNil(NoiseMask.firstIndex([]))
    }

    func testPacketRejectsTruncatedTlv() {
        XCTAssertNil(OpoPacket(tlv: [0x04, 0x04]))
        // len 声称 3 字节但只给了 1 字节
        XCTAssertNil(OpoPacket(tlv: [0x04, 0x04, 0x00, 0x03, 0x00, 0x01]))
    }
}

// MARK: - 测试辅助

private extension String {
    var bytes: [UInt8] {
        var out: [UInt8] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: 2)
            out.append(UInt8(self[index..<next], radix: 16) ?? 0)
            index = next
        }
        return out
    }
}

private extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
