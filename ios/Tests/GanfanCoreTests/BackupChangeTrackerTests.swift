import Foundation
import XCTest
@testable import GanfanCore

@MainActor
final class BackupChangeTrackerTests: XCTestCase {
    func testDeletionCanRemainPendingEvenWhenNoRecordRemains() {
        let defaults = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tracker = BackupChangeTracker(defaults: defaults)

        tracker.markChanged()

        XCTAssertTrue(tracker.hasPendingChanges)
        XCTAssertEqual(tracker.generation, 1)
    }

    func testDoesNotClearChangesThatArriveDuringBackup() {
        let defaults = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tracker = BackupChangeTracker(defaults: defaults)
        let backupGeneration = tracker.markChanged()
        tracker.markChanged()

        XCTAssertFalse(tracker.markBackedUp(ifGenerationMatches: backupGeneration))
        XCTAssertTrue(tracker.hasPendingChanges)
    }

    func testClearsPendingFlagWhenBackupCoversCurrentGeneration() {
        let defaults = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tracker = BackupChangeTracker(defaults: defaults)
        let backupGeneration = tracker.markChanged()

        XCTAssertTrue(tracker.markBackedUp(ifGenerationMatches: backupGeneration))
        XCTAssertFalse(tracker.hasPendingChanges)
    }

    private var suiteName: String {
        "GanfanBackupChangeTrackerTests-\(name)"
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: suiteName)!
    }
}
