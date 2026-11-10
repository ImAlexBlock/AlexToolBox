import Foundation
import IOBluetooth
import CoreBluetooth
import os

private let logger = Logger(subsystem: "dev.alexblock.alextoolbox", category: "link")

// MARK: - 链路状态

public enum LinkState: Equatable {
    case noHeadset          // 没有已配对的 OPPO 耳机
    case disconnected(String)  // 配对过但当前未连接
    case connecting(String)
    case connected(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var text: String {
        switch self {
        case .noHeadset: return "未找到 OPPO 耳机"
        case .disconnected(let name): return name
        case .connecting(let name): return "正在连接 \(name)…"
        case .connected(let name): return name
        }
    }

    public var subtitle: String {
        switch self {
        case .noHeadset: return "请先在系统设置里配对"
        case .disconnected: return "未连接"
        case .connecting: return "建立通道…"
        case .connected: return "已连接"
        }
    }
}

// MARK: - 连接管理

/// 与 OPPO / OnePlus 耳机的私有 SPP 通道。
///
/// 实测要点：
/// - 服务 UUID `0000079A-D102-11E1-9B23-00025B00A5A5`，SDP 名 "enco link"，通道号由 SDP 给出
/// - 通道打开后耳机主动推 78 字节设备信息，之后才接受业务命令
/// - 首次 `openRFCOMMChannelAsync` 经常超时，第二次成功；**但不能快速连试**，
///   每次失败都会打断 ACL 链路，连打 8 次能把耳机从系统里踹掉
/// - `openRFCOMMChannelSync` 在通道已打开时仍返回 `kIOReturnError`，只能靠 `isOpen()` 判定
@MainActor
public final class HeadsetLink: NSObject, ObservableObject {
    /// `MenuBarExtra` 的 body 求值时机不可控，用单例保证 app 启动即开始扫描。
    public static let shared = HeadsetLink()

    /// melody 私有服务 UUID。
    static let melodyUUID = IOBluetoothSDPUUID(
        data: Data([0x00, 0x00, 0x07, 0x9A, 0xD1, 0x02, 0x11, 0xE1,
                    0x9B, 0x23, 0x00, 0x02, 0x5B, 0x00, 0xA5, 0xA5])
    )

    @Published public private(set) var state: LinkState = .noHeadset
    @Published public private(set) var mode: NoiseMode?
    @Published public private(set) var pendingMode: NoiseMode?
    @Published public private(set) var lastError: String?

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var channelID: BluetoothRFCOMMChannelID = 0
    private let decoder = OpoFrameDecoder()
    private var sequence: UInt8 = 0

    private var supervisor: Task<Void, Never>?
    private var openTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var pendingTimeout: Task<Void, Never>?
    private var openAttempts = 0
    private var openBackoffUntil = Date.distantPast
    private var lastConnectRequest = Date.distantPast
    private var isShuttingDown = false
    /// 必须持有：CoreBluetooth 的 XPC 连接随 manager 释放而失效。
    private var central: CBCentralManager?

    /// 通道打开超时。实测 ACL 已在时通常 < 1 秒。
    private static let openTimeout: TimeInterval = 3
    /// 同一 ACL 上的最大打开次数。再多就会打断链路。
    private static let maxOpenAttempts = 3
    /// 主动建 ACL 的最小间隔，避免把耳机踹下线。
    private static let connectCooldown: TimeInterval = 20
    /// 一轮打开全部失败后的冷却。猛试会打断 ACL，实测能把耳机踹下线。
    private static let openBackoff: TimeInterval = 30

    public override init() {
        super.init()
        // 打开 RFCOMM 前先让 CoreBluetooth 栈进入 powered-on，否则首次连接容易卡死。
        central = CBCentralManager(delegate: CentralDelegate.shared, queue: .main)
        start()
    }

    // MARK: 生命周期

    public func start() {
        isShuttingDown = false
        supervisor?.cancel()
        supervisor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    public func stop() {
        isShuttingDown = true
        supervisor?.cancel()
        supervisor = nil
        openTask?.cancel()
        openTask = nil
        connectTask?.cancel()
        connectTask = nil
        closeChannel()
    }

    private func tick() async {
        if channel?.isOpen() == true { return }
        // 正在开通道或正在建 ACL 时不要重复发起，两条路径并发会打断链路。
        if openTask != nil || connectTask != nil { return }

        guard let found = Self.findPairedHeadset() else {
            logger.debug("scan: no paired melody headset")
            if state != .noHeadset { state = .noHeadset }
            device = nil
            return
        }
        logger.debug("scan: \(found.device.name ?? "?", privacy: .public) connected=\(found.device.isConnected()) ch=\(found.channelID)")
        let name = found.device.name ?? "OPPO 耳机"
        device = found.device
        channelID = found.channelID

        guard found.device.isConnected() else {
            if state.isConnected || state == .connecting(name) { closeChannel() }
            state = .disconnected(name)
            return
        }

        // 顶部已排除"通道仍开着"的情况，所以走到这里就是通道没了。
        guard Date() >= openBackoffUntil else { return }
        openAttempts = 0
        state = .connecting(name)
        beginOpen(name: name)
    }

    // MARK: 发现

    struct Paired {
        let device: IOBluetoothDevice
        let channelID: BluetoothRFCOMMChannelID
    }

    /// 已配对、SDP 里带 melody 服务的设备。不看 `isConnected`，因为用户可能需要主动连接。
    /// 多副耳机同时配对时优先取已连接的那副。
    static func findPairedHeadset() -> Paired? {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        var fallback: Paired?
        for dev in paired {
            guard let channel = channelID(for: dev) else { continue }
            let candidate = Paired(device: dev, channelID: channel)
            if dev.isConnected() { return candidate }
            if fallback == nil { fallback = candidate }
        }
        return fallback
    }

    private static func channelID(for device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        // SDP 缓存为空时主动查一次；结果异步落地，下一轮再取。
        if device.services == nil {
            _ = device.performSDPQuery(nil)
            return nil
        }
        guard let record = device.getServiceRecord(for: melodyUUID) else { return nil }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess, channelID != 0 else { return nil }
        return channelID
    }

    // MARK: 打开通道

    private func beginOpen(name: String) {
        guard !isShuttingDown, let device else { return }
        // ACL 掉了就别开通道：开了也是等 3 秒超时，还会累加尝试次数。
        guard device.isConnected() else {
            state = .disconnected(name)
            return
        }
        openAttempts += 1
        logger.info("open attempt \(self.openAttempts) ch=\(self.channelID)")

        var newChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
        guard result == kIOReturnSuccess, let opened = newChannel else {
            logger.error("openRFCOMMChannelAsync failed \(result)")
            scheduleRetry(name: name)
            return
        }
        channel = opened
        opened.setDelegate(self)
        decoder.reset()

        openTask?.cancel()
        openTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(Self.openTimeout)
            while Date() < deadline {
                if Task.isCancelled { return }
                if let self, self.channel?.isOpen() == true {
                    self.openTask = nil
                    self.didOpen(name: name)
                    return
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.openTask = nil
            self.scheduleRetry(name: name)
        }
    }

    private func scheduleRetry(name: String) {
        closeChannel()
        guard openAttempts < Self.maxOpenAttempts else {
            // 不再猛试：进入冷却，期间 supervisor 不会重开。
            openBackoffUntil = Date().addingTimeInterval(Self.openBackoff)
            state = .disconnected(name)
            lastError = "打开数据通道超时"
            return
        }
        // 指数退避，给 ACL 留出稳定时间。
        let delay = pow(2.0, Double(openAttempts - 1))
        openTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.openTask = nil
            self.beginOpen(name: name)
        }
    }

    private func didOpen(name: String) {
        logger.info("channel open: \(name, privacy: .public)")
        state = .connected(name)
        lastError = nil
        // 注册降噪事件上报（耳机按键改档时也会推），再拉一次当前档位。
        send(OpoCommand.registerNotification, payload: [0x03])
        send(OpoCommand.pollDeviceInfo, payload: [0x01, 0x01])
    }

    private func closeChannel() {
        openTask?.cancel()
        openTask = nil
        pendingTimeout?.cancel()
        pendingTimeout = nil
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        decoder.reset()
        mode = nil
        pendingMode = nil
    }

    // MARK: 主动连接

    /// 用户点"连接"：建 ACL，成功后 supervisor 会自动开通道。
    public func connectHeadset() {
        // 与 tick() 共用同一互斥：并发两次 openRFCOMMChannelAsync 会打断 ACL。
        guard openTask == nil, connectTask == nil else {
            lastError = "正在建立通道，请稍候"
            return
        }
        guard let device else {
            lastError = "未找到已配对的 OPPO 耳机"
            return
        }
        guard Date().timeIntervalSince(lastConnectRequest) > Self.connectCooldown else {
            lastError = "请稍候再试"
            return
        }
        lastConnectRequest = Date()
        lastError = nil
        openBackoffUntil = .distantPast
        openAttempts = 0
        let name = device.name ?? "OPPO 耳机"
        state = .connecting(name)

        connectTask?.cancel()
        connectTask = Task { [weak self] in
            let result = device.openConnection()
            logger.info("openConnection \(result)")
            guard let self, !Task.isCancelled else { return }
            // ACL 建立需要几秒，给 6 秒。
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                if Task.isCancelled { return }
                if device.isConnected() {
                    self.connectTask = nil
                    self.openAttempts = 0
                    self.beginOpen(name: name)
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard !Task.isCancelled else { return }
            self.connectTask = nil
            self.state = .disconnected(name)
            self.lastError = "无法连接耳机，请在系统设置中连接"
        }
    }

    // MARK: 发送

    @discardableResult
    private func send(_ command: UInt16, payload: [UInt8]) -> Bool {
        guard let channel, channel.isOpen() else { return false }
        sequence = sequence &+ 1
        let tlv = OpoFrame.tlv(cmd: command, seq: sequence, payload: payload)
        var frame = OpoFrame.encode(tlv: tlv)
        let result = channel.writeSync(&frame, length: UInt16(frame.count))
        guard result == kIOReturnSuccess else {
            lastError = String(format: "写入失败 (0x%08X)", UInt32(bitPattern: result))
            logger.error("write failed 0x\(String(UInt32(bitPattern: result), radix: 16), privacy: .public)")
            return false
        }
        logger.info("TX \(frame.map { String(format: "%02x", $0) }.joined(), privacy: .public)")
        return true
    }

    public func select(_ mode: NoiseMode) {
        guard state.isConnected else { return }
        pendingMode = mode
        lastError = nil
        // 不做乐观赋值：`mode` 只能由耳机回包决定。耳机回报的是实际子档位
        // （下发"降噪"可能回 idx 4/5/7），乐观赋值会让选中态跳变。
        guard send(OpoCommand.setNoiseReduction, payload: mode.payload) else {
            pendingMode = nil
            return
        }
        schedulePendingTimeout()
    }

    /// 耳机不回状态帧时清掉转圈，避免永久 pending。
    private func schedulePendingTimeout() {
        pendingTimeout?.cancel()
        pendingTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.pendingTimeout = nil
            self.pendingMode = nil
        }
    }

    // MARK: 收包

    fileprivate func handle(bytes: [UInt8]) {
        logger.info("RX \(bytes.count): \(bytes.map { String(format: "%02x", $0) }.joined(), privacy: .public)")
        for tlv in decoder.append(bytes) {
            guard let packet = OpoPacket(tlv: tlv) else { continue }
            handle(packet)
        }
    }

    private func handle(_ packet: OpoPacket) {
        switch packet.command {
        case OpoCommand.response(OpoCommand.setNoiseReduction):
            if !packet.succeeded {
                lastError = "耳机拒绝切换（状态 \(packet.payload.first ?? 0xFF)）"
                pendingMode = nil
                pendingTimeout?.cancel()
                pendingTimeout = nil
            }

        case OpoCommand.notificationEvent where packet.payload.count >= 5 && packet.payload[0] == 0x03:
            // [0]=事件类型 3，[1]=1（整机），[2]=载荷类型，[3...]=位图
            applyNoiseMask(Array(packet.payload[3...]))

        case OpoCommand.response(OpoCommand.pollDeviceInfo) where
            packet.payload.count >= 4 && packet.payload[0] == 0 && packet.payload[1] == 0x01:
            // [0]=状态 0，[1]=0x01，[2]=0x01，[3...]=位图
            applyNoiseMask(Array(packet.payload[3...]))

        default:
            break
        }
    }

    private func applyNoiseMask(_ mask: [UInt8]) {
        guard let index = NoiseMask.firstIndex(mask),
              let resolved = NoiseMode.matching(reportedIndex: index) else { return }
        mode = resolved
        pendingMode = nil
        pendingTimeout?.cancel()
        pendingTimeout = nil
    }
}

// MARK: - RFCOMM 回调

extension HeadsetLink: IOBluetoothRFCOMMChannelDelegate {
    public nonisolated func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        Task { @MainActor [weak self] in
            guard let self, self.channel === channel else { return }
            guard status == kIOReturnSuccess || channel.isOpen() else { return }
            self.openTask?.cancel()
            self.openTask = nil
            if self.state.isConnected { return }
            self.didOpen(name: self.device?.name ?? "OPPO 耳机")
        }
    }

    public nonisolated func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let dataPointer, dataLength > 0 else { return }
        let bytes = [UInt8](UnsafeBufferPointer(
            start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        Task { @MainActor [weak self] in
            guard let self, self.channel === channel else { return }
            self.handle(bytes: bytes)
        }
    }

    public nonisolated func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        Task { @MainActor [weak self] in
            guard let self, self.channel === channel, !self.isShuttingDown else { return }
            let name = self.device?.name ?? "OPPO 耳机"
            self.closeChannel()
            self.state = .disconnected(name)
        }
    }
}

// MARK: - CoreBluetooth 预热

private final class CentralDelegate: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    static let shared = CentralDelegate()
    func centralManagerDidUpdateState(_ central: CBCentralManager) {}
}
