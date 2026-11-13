import XCTest
@testable import UsageControl

final class OpenCodeGoUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_763_000_000)

    func testParsesAllWindows() throws {
        let json = """
        {
          "usage": {
            "rolling": {
              "status": "active",
              "percent": 12.5,
              "resetsAt": "2026-11-13T15:30:00.123Z"
            },
            "weekly": {
              "percent": 42,
              "resetsAt": "2026-11-17T00:00:00Z"
            },
            "monthly": {
              "percent": 71.8,
              "resetsAt": "2026-12-01T00:00:00Z"
            }
          }
        }
        """

        let snapshot = try OpenCodeGoUsageParser.parse(Data(json.utf8), now: now)

        XCTAssertEqual(snapshot.fetchedAt, now)
        XCTAssertEqual(snapshot.windows.map(\.kind), [.fiveHour, .weekly, .monthly])
        XCTAssertEqual(snapshot.window(.fiveHour)?.percent, 12.5)
        XCTAssertEqual(snapshot.window(.weekly)?.percent, 42)
        XCTAssertEqual(snapshot.window(.monthly)?.percent, 71.8)
        XCTAssertEqual(snapshot.window(.fiveHour)?.status, "active")
        XCTAssertNil(snapshot.window(.weekly)?.status)

        let expected = ISO8601DateFormatter()
        expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(snapshot.window(.fiveHour)?.resetsAt,
                       expected.date(from: "2026-11-13T15:30:00.123Z"))
        XCTAssertNotNil(snapshot.window(.weekly)?.resetsAt)
        XCTAssertNotNil(snapshot.window(.monthly)?.resetsAt)
    }

    func testMonthlyIsOptional() throws {
        let json = """
        {
          "usage": {
            "rolling": { "percent": 5, "resetsAt": "2026-11-13T15:30:00Z" },
            "weekly": { "percent": 10, "resetsAt": "2026-11-17T00:00:00Z" }
          }
        }
        """

        let snapshot = try OpenCodeGoUsageParser.parse(Data(json.utf8), now: now)

        XCTAssertEqual(snapshot.windows.map(\.kind), [.fiveHour, .weekly])
        XCTAssertNil(snapshot.window(.monthly))
    }

    func testPercentAcceptsNumericStringsAndClamps() throws {
        let json = """
        {
          "usage": {
            "rolling": { "percent": "120.5" },
            "weekly": { "percent": -4 },
            "monthly": { "percent": 0 }
          }
        }
        """

        let snapshot = try OpenCodeGoUsageParser.parse(Data(json.utf8), now: now)

        XCTAssertEqual(snapshot.window(.fiveHour)?.percent, 100)
        XCTAssertEqual(snapshot.window(.weekly)?.percent, 0)
        XCTAssertEqual(snapshot.window(.monthly)?.percent, 0)
        XCTAssertNil(snapshot.window(.fiveHour)?.resetsAt)
    }

    func testMissingUsageFails() {
        for json in ["{}", #"{"usage":null}"#, #"{"usage":{}}"#] {
            XCTAssertThrowsError(try OpenCodeGoUsageParser.parse(Data(json.utf8), now: now)) {
                XCTAssertEqual($0 as? GoUsageError, .invalidResponse)
            }
        }
    }

    func testMalformedJSONFails() {
        XCTAssertThrowsError(
            try OpenCodeGoUsageParser.parse(Data("not json".utf8), now: now)
        ) {
            XCTAssertEqual($0 as? GoUsageError, .invalidResponse)
        }
    }

    func testHTTPStatusMapping() {
        XCTAssertEqual(GoUsageError.from(statusCode: 401), .unauthorized)
        XCTAssertEqual(GoUsageError.from(statusCode: 403), .forbidden)
        XCTAssertEqual(GoUsageError.from(statusCode: 429), .rateLimited)
        XCTAssertEqual(GoUsageError.from(statusCode: 500), .server(500))
        XCTAssertEqual(GoUsageError.from(statusCode: 418), .server(418))
        XCTAssertEqual(GoUsageError.unauthorized.errorDescription,
                       "API Key 无效或已过期")
    }

    func testKeychainRoundTrip() throws {
        let store = KeychainStore(
            service: "dev.alexblock.alextoolbox.tests.\(UUID().uuidString)",
            account: "api-key"
        )
        defer { store.delete() }

        XCTAssertNil(try store.load())
        try store.save("test-api-key")
        XCTAssertEqual(try store.load(), "test-api-key")
        store.delete()
        XCTAssertNil(try store.load())
    }
}
