import Combine
import Foundation
import UsageControl

/// OpenCode Go 额度页状态：API Key、额度快照和自动刷新。
@MainActor
final class UsageModel: ObservableObject {
    static let refreshInterval: TimeInterval = 60

    @Published var keyDraft = ""
    @Published var isEditingKey = false
    @Published private(set) var hasStoredKey = false
    @Published private(set) var snapshot: GoUsageSnapshot?
    @Published private(set) var errorText: String?
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?

    private let keychain: KeychainStore
    private let client: OpenCodeGoUsageClient
    private var storedKey: String?
    private var didLoadKey = false
    private var refreshTask: Task<Void, Never>?
    private var autoTask: Task<Void, Never>?
    private var refreshID = 0
    private var isPageVisible = false
    private var autoRefreshEnabled = true

    init(keychain: KeychainStore = KeychainStore(),
         client: OpenCodeGoUsageClient = OpenCodeGoUsageClient()) {
        self.keychain = keychain
        self.client = client
        startAutoRefresh()
    }

    deinit {
        autoTask?.cancel()
        refreshTask?.cancel()
    }

    func setPageVisible(_ visible: Bool) {
        isPageVisible = visible
        guard visible else { return }
        if !didLoadKey {
            didLoadKey = true
            loadStoredKey()
        }
        if hasStoredKey, snapshot == nil {
            refresh()
        }
    }

    func saveDraftKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorText = "请输入 API Key"
            return
        }

        do {
            try keychain.save(key)
        } catch {
            errorText = error.localizedDescription
            return
        }

        storedKey = key
        hasStoredKey = true
        didLoadKey = true
        autoRefreshEnabled = true
        keyDraft = ""
        isEditingKey = false
        errorText = nil
        refresh(force: true)
    }

    func clearKey() {
        keychain.delete()
        storedKey = nil
        hasStoredKey = false
        snapshot = nil
        lastUpdated = nil
        errorText = nil
        keyDraft = ""
        isEditingKey = false
        autoRefreshEnabled = true
        isLoading = false
        refreshID &+= 1
        refreshTask?.cancel()
        refreshTask = nil
    }

    func beginEditingKey() {
        isEditingKey = true
        keyDraft = ""
        errorText = nil
    }

    func cancelEditingKey() {
        isEditingKey = false
        keyDraft = ""
        errorText = nil
    }

    func refresh(force: Bool = false) {
        guard let key = storedKey, !key.isEmpty else { return }
        if isLoading, !force { return }

        refreshID &+= 1
        let currentID = refreshID
        refreshTask?.cancel()
        isLoading = true
        errorText = nil

        refreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await self.client.fetch(apiKey: key)
                guard !Task.isCancelled, self.refreshID == currentID else { return }
                self.snapshot = snapshot
                self.lastUpdated = snapshot.fetchedAt
                self.errorText = nil
            } catch is CancellationError {
                // 被新的刷新请求替换。
            } catch {
                guard !Task.isCancelled, self.refreshID == currentID else { return }
                self.errorText = error.localizedDescription
                if let usageError = error as? GoUsageError {
                    switch usageError {
                    case .unauthorized, .forbidden:
                        self.autoRefreshEnabled = false
                    default:
                        break
                    }
                    if usageError == .unauthorized {
                        self.isEditingKey = true
                    }
                }
            }

            if self.refreshID == currentID {
                self.isLoading = false
                self.refreshTask = nil
            }
        }
    }

    private func loadStoredKey() {
        do {
            guard let key = try keychain.load(), !key.isEmpty else { return }
            storedKey = key
            hasStoredKey = true
            refresh()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func startAutoRefresh() {
        autoTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(Self.refreshInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                if self.isPageVisible, self.hasStoredKey, self.autoRefreshEnabled {
                    self.refresh()
                }
            }
        }
    }
}
