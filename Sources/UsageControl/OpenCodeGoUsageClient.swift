import Foundation

/// 使用 API Key 读取 OpenCode Go 额度。
public final class OpenCodeGoUsageClient: @unchecked Sendable {
    public static let endpoint = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    private let session: URLSession
    private let timeout: TimeInterval
    private let now: () -> Date

    public init(timeout: TimeInterval = 20, now: @escaping () -> Date = Date.init) {
        self.timeout = timeout
        self.now = now

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false

        // 不跟随重定向，避免 Bearer 凭据被转发到其他主机。
        session = URLSession(configuration: configuration,
                             delegate: NoRedirectDelegate(),
                             delegateQueue: nil)
    }

    public func fetch(apiKey: String) async throws -> GoUsageSnapshot {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GoUsageError.unauthorized }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AlexToolBox/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("alextoolbox-usage", forHTTPHeaderField: "x-opencode-session")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw GoUsageError.transport(error.localizedDescription)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GoUsageError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GoUsageError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return try OpenCodeGoUsageParser.parse(data, now: now())
        case 401, 403, 429:
            throw GoUsageError.from(statusCode: http.statusCode)
        default:
            throw GoUsageError.from(statusCode: http.statusCode)
        }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable
{
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
