import Foundation

// MARK: - 命令码

public enum OpoCommand {
    public static let pollDeviceInfo: UInt16 = 268      // 0x010C，payload [01 01] 查询当前降噪档位
    public static let setNoiseReduction: UInt16 = 1028  // 0x0404
    public static let registerNotification: UInt16 = 513
    public static let notificationEvent: UInt16 = 516

    public static func response(_ cmd: UInt16) -> UInt16 { (cmd & 0x7FFF) | 0x8000 }
}

// MARK: - 降噪模式

public enum NoiseMode: Int, CaseIterable, Identifiable {
    case adaptive = 11
    case reduction = 1
    case transparency = 2
    case off = 0

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .adaptive: return "自适应"
        case .reduction: return "降噪"
        case .transparency: return "通透"
        case .off: return "关闭"
        }
    }

    public var symbol: String {
        switch self {
        case .adaptive: return "waveform.path.ecg"
        case .reduction: return "ear.badge.waveform"
        case .transparency: return "ear"
        case .off: return "speaker.slash"
        }
    }

    /// `CurrentNoiseModeInfo.getData()`：`[0x01, type=1, mask...]`，第 N 位 = 白名单 protocolIndex。
    public var payload: [UInt8] {
        let index = rawValue
        guard index < 8 else {
            return [0x01, 0x01, 0x00, 1 << UInt8(index - 8)]
        }
        return [0x01, 0x01, 1 << UInt8(index)]
    }

    /// 耳机上报的是实际子模式，不是下发时用的档位。
    /// 实测：下发降噪(idx 1) → 上报 idx 4/5/7；下发通透(idx 2) → 上报 idx 8；下发关闭(idx 0) → 上报 idx 3。
    public static func matching(reportedIndex index: Int) -> NoiseMode? {
        switch index {
        case 0, 3: return .off
        case 2, 8: return .transparency
        case 1, 4, 5, 6, 7: return .reduction
        case 11: return .adaptive
        default: return nil
        }
    }
}

// MARK: - 三层封装

/// TLV 包 → OPOv1 链路帧。
///
/// ```
/// TLV    cmd(2B LE) seq(1B) len(2B LE) payload
/// 帧     0xAA | LEB128(len) | status | 0x00 | payload
/// ```
/// `len` = 帧总长 − 2。单帧 `status = 0`，不分片、无 FSN。
public enum OpoFrame {
    public static let sync: UInt8 = 0xAA

    public static func leb128(_ value: Int) -> [UInt8] {
        var out: [UInt8] = []
        var remaining = value
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            out.append(byte)
        } while remaining != 0
        return out
    }

    public static func tlv(cmd: UInt16, seq: UInt8, payload: [UInt8]) -> [UInt8] {
        [
            UInt8(cmd & 0xFF), UInt8(cmd >> 8),
            seq,
            UInt8(payload.count & 0xFF), UInt8((payload.count >> 8) & 0xFF),
        ] + payload
    }

    public static func encode(tlv: [UInt8]) -> [UInt8] {
        [sync] + leb128(tlv.count + 2) + [0x00, 0x00] + tlv
    }
}

// MARK: - 流式拆帧

/// 一次读可能带多个帧（实测出现过 24 字节含两帧），必须按缓冲区增量解析。
public final class OpoFrameDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [UInt8] = []
    private var fragments: [UInt8] = []

    /// 喂入原始字节，返回已完整组装出的 TLV 包。
    public func append(_ bytes: [UInt8]) -> [[UInt8]] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: bytes)

        var out: [[UInt8]] = []
        while true {
            guard let start = buffer.firstIndex(of: OpoFrame.sync) else {
                buffer.removeAll(keepingCapacity: true)
                return out
            }
            if start > 0 { buffer.removeFirst(start) }

            guard let (length, lengthBytes) = decodeLength(buffer, at: 1) else { return out }
            let total = length + 2
            guard buffer.count >= total else { return out }

            let statusIndex = 1 + lengthBytes
            guard statusIndex + 1 < total else {
                buffer.removeFirst(total)
                continue
            }
            let status = buffer[statusIndex] & 0x03
            let headerLength = statusIndex + 2 + (status == 0 ? 0 : 1)
            guard headerLength <= total else {
                buffer.removeFirst(total)
                continue
            }

            let payload = Array(buffer[headerLength..<total])
            buffer.removeFirst(total)

            switch status {
            case 0:
                out.append(payload)
            case 1:
                fragments = payload
            case 2:
                fragments.append(contentsOf: payload)
            default:
                fragments.append(contentsOf: payload)
                out.append(fragments)
                fragments = []
            }
        }
    }

    private func decodeLength(_ bytes: [UInt8], at offset: Int) -> (value: Int, size: Int)? {
        var value = 0
        var size = 0
        while true {
            let index = offset + size
            guard index < bytes.count else { return nil }
            let byte = bytes[index]
            value |= Int(byte & 0x7F) << (7 * size)
            size += 1
            if byte & 0x80 == 0 { return (value, size) }
            if size > 4 { return nil }
        }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
        fragments.removeAll()
    }
}

// MARK: - 位图

/// 降噪档位位图：第 N 位 = 白名单里的 `protocolIndex`。
public enum NoiseMask {
    public static func firstIndex(_ mask: [UInt8]) -> Int? {
        for (byteIndex, byte) in mask.enumerated() {
            for bit in 0..<8 where byte & (1 << UInt8(bit)) != 0 {
                return byteIndex * 8 + bit
            }
        }
        return nil
    }
}

// MARK: - TLV 解析

public struct OpoPacket {
    public let command: UInt16
    public let sequence: UInt8
    public let payload: [UInt8]

    public init?(tlv: [UInt8]) {
        guard tlv.count >= 5 else { return nil }
        command = UInt16(tlv[0]) | (UInt16(tlv[1]) << 8)
        sequence = tlv[2]
        let length = Int(tlv[3]) | (Int(tlv[4]) << 8)
        guard 5 + length <= tlv.count else { return nil }
        payload = Array(tlv[5..<(5 + length)])
    }

    public var status: UInt8? { payload.first }
    public var succeeded: Bool { payload.first == 0 }

    /// 位图 → 第一个置位的档位号。
    public var noiseModeIndex: Int? { NoiseMask.firstIndex(payload) }
}
