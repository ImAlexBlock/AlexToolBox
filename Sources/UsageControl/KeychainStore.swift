import Foundation
import Security

/// 把 OpenCode API Key 存在登录钥匙串，不写 UserDefaults。
public struct KeychainStore: Sendable {
    public enum KeychainError: LocalizedError, Sendable {
        case status(OSStatus)
        case invalidData

        public var errorDescription: String? {
            switch self {
            case .status(let status):
                let message = SecCopyErrorMessageString(status, nil) as String?
                return message ?? "钥匙串错误（\(status)）"
            case .invalidData:
                return "钥匙串中的数据无法读取"
            }
        }
    }

    public let service: String
    public let account: String

    public init(service: String = "dev.alexblock.alextoolbox.opencode-go",
                account: String = "api-key") {
        self.service = service
        self.account = account
    }

    public func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status)
        }
    }

    public func save(_ value: String) throws {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }

    public func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
