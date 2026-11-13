import AppKit
import Combine
import Foundation
import HeadsetControl
import MouseControl

/// 合并后的 App 状态：鼠标模型 + 耳机链路，以及 App 生命周期内的指针属性写入与恢复。
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let mouse: MouseModel
    let headset: HeadsetLink
    let usage: UsageModel

    private let manager: PointerServiceManager
    private let applier: PointerSettingsApplier
    private var wakeObserver: NSObjectProtocol?
    private var started = false

    private init() {
        let manager = PointerServiceManager()
        let applier = PointerSettingsApplier(manager: manager)
        let store = SettingsStore()
        self.manager = manager
        self.applier = applier
        self.mouse = MouseModel(store: store, applier: applier, manager: manager)
        self.headset = HeadsetLink.shared
        self.usage = UsageModel()
    }

    func start() {
        guard !started else { return }
        started = true

        manager.start(queue: .main)
        manager.onChange = { [weak self] in
            Task { @MainActor in self?.mouse.apply() }
        }

        // 上一次运行可能崩溃在已写入状态；先恢复，再按已保存设置写入。
        if applier.hasSnapshot {
            applier.restoreAll()
        }
        mouse.apply()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.mouse.apply() }
        }
    }

    func shutdown() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        applier.restoreAll()
        manager.stop()
    }
}
