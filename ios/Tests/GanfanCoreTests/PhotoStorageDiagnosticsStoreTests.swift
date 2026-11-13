import XCTest
@testable import GanfanCore

final class PhotoStorageDiagnosticsStoreTests: XCTestCase {
    func testRetainsOnlyRecentTypedFailureMetadata() throws {
        let suiteName = "PhotoStorageDiagnosticsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PhotoStorageDiagnosticsStore(userDefaults: defaults)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        for index in 0..<25 {
            store.record(
                stage: .photoWrite,
                reason: index.isMultiple(of: 2) ? .diskFull : .unknown,
                byteCount: index * 100,
                occurredAt: start.addingTimeInterval(TimeInterval(index))
            )
        }

        let events = store.recentEvents
        XCTAssertEqual(events.count, PhotoStorageDiagnosticsStore.maximumEvents)
        XCTAssertEqual(events.first?.byteCount, 2_400)
        XCTAssertEqual(events.last?.byteCount, 500)
        XCTAssertTrue(events.allSatisfy { $0.stage == .photoWrite })
    }
}
