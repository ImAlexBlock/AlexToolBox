import Foundation

/// OpenCode Go 的一个额度窗口。
public struct GoUsageWindow: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case fiveHour
        case weekly
        case monthly

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .fiveHour: return "5 小时"
            case .weekly: return "本周"
            case .monthly: return "本月"
            }
        }

        public var symbol: String {
            switch self {
            case .fiveHour: return "clock"
            case .weekly: return "calendar.badge.clock"
            case .monthly: return "calendar"
            }
        }
    }

    public let kind: Kind
    /// 已用百分比，范围 0...100。
    public let percent: Double
    public let resetsAt: Date?
    public let status: String?

    public init(kind: Kind, percent: Double, resetsAt: Date? = nil, status: String? = nil) {
        self.kind = kind
        if percent.isFinite {
            self.percent = min(max(percent, 0), 100)
        } else {
            self.percent = 0
        }
        self.resetsAt = resetsAt
        let trimmed = status?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.status = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    public var id: Kind { kind }
}

/// 一次额度读取的结果。
public struct GoUsageSnapshot: Equatable, Sendable {
    public let windows: [GoUsageWindow]
    public let fetchedAt: Date

    public init(windows: [GoUsageWindow], fetchedAt: Date = Date()) {
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    public func window(_ kind: GoUsageWindow.Kind) -> GoUsageWindow? {
        windows.first { $0.kind == kind }
    }
}

/// 额度接口的失败分类。
public enum GoUsageError: LocalizedError, Equatable, Sendable {
    case unauthorized
    case forbidden
    case rateLimited
    case server(Int)
    case invalidResponse
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "API Key 无效或已过期"
        case .forbidden:
            return "该 API Key 没有 OpenCode Go 订阅"
        case .rateLimited:
            return "请求过于频繁，请稍后重试"
        case .server(let code):
            return "OpenCode 服务暂时不可用（HTTP \(code)）"
        case .invalidResponse:
            return "额度响应格式无法解析"
        case .transport(let message):
            return "网络请求失败：\(message)"
        }
    }

    public static func from(statusCode: Int) -> GoUsageError {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 429: return .rateLimited
        default: return .server(statusCode)
        }
    }
}

/// `GET https://opencode.ai/zen/go/v1/usage` 的响应解析。
///
/// ```
/// {
///   "usage": {
///     "rolling": { "status": "active", "percent": 12.5, "resetsAt": "..." },
///     "weekly":  { "percent": 42,            "resetsAt": "..." },
///     "monthly": { "percent": 71,            "resetsAt": "..." }
///   }
/// }
/// ```
///
/// rolling / weekly 通常存在，monthly 可能省略。只要至少有一个窗口可解析就返回结果。
public enum OpenCodeGoUsageParser {
    public static func parse(_ data: Data, now: Date = Date()) throws -> GoUsageSnapshot {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw GoUsageError.invalidResponse
        }

        guard let usage = payload.usage else { throw GoUsageError.invalidResponse }

        let windows = [
            window(.fiveHour, usage.rolling),
            window(.weekly, usage.weekly),
            window(.monthly, usage.monthly),
        ].compactMap { $0 }

        guard !windows.isEmpty else { throw GoUsageError.invalidResponse }
        return GoUsageSnapshot(windows: windows, fetchedAt: now)
    }

    private static func window(_ kind: GoUsageWindow.Kind,
                               _ raw: RawWindow?) -> GoUsageWindow? {
        guard let raw, let percent = raw.percent?.value, percent.isFinite else {
            return nil
        }
        return GoUsageWindow(kind: kind,
                             percent: percent,
                             resetsAt: raw.resetsAt.flatMap(parseDate),
                             status: raw.status)
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private struct Payload: Decodable {
        let usage: Usage?
    }

    private struct Usage: Decodable {
        let rolling: RawWindow?
        let weekly: RawWindow?
        let monthly: RawWindow?
    }

    private struct RawWindow: Decodable {
        let status: String?
        let percent: FlexibleDouble?
        let resetsAt: String?
    }

    /// 兼容数字与数字字符串两种编码。
    private struct FlexibleDouble: Decodable {
        let value: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self.value = value
            } else if let text = try? container.decode(String.self),
                      let value = Double(text) {
                self.value = value
            } else {
                throw DecodingError.typeMismatch(
                    Double.self,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected a number or a numeric string"
                    )
                )
            }
        }
    }
}
