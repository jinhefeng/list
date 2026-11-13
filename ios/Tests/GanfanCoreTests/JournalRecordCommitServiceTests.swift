import Foundation
import SwiftData
import XCTest
@testable import GanfanCore

@MainActor
final class JournalRecordCommitServiceTests: XCTestCase {
    private enum InjectedError: Error, Equatable {
        case saveFailed
    }

    func testFailedEditKeepsOldRecordAndPhotoAndRemovesNewPhoto() throws {
        let suiteName = "GanfanRecordCommitTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tracker = BackupChangeTracker(defaults: defaults)
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoStore = LocalPhotoStore(directoryURL: directory.appendingPathComponent("Photos", isDirectory: true))
        let oldBytes = Data("old photo".utf8)
        let newBytes = Data("new photo".utf8)
        let oldPhoto = try photoStore.save(oldBytes, fileExtension: "jpg")
        let originalRecord = try DrinkRecord(drinkName: "原记录", photo: oldPhoto)
        let context = ModelContext(try makeInMemoryContainer())
        let storedRecord = try StoredJournalRecord(record: .drink(originalRecord), needsBackup: false)
        context.insert(storedRecord)
        try context.save()

        let newPhoto = try photoStore.save(newBytes, fileExtension: "jpg")
        let editedRecord = try DrinkRecord(id: originalRecord.id, drinkName: "修改后的记录", photo: newPhoto)

        XCTAssertThrowsError(
            try JournalRecordCommitService.save(
                .drink(editedRecord),
                replacing: storedRecord,
                createdPhotoAssets: [newPhoto],
                photoStore: photoStore,
                into: context,
                changeTracker: tracker,
                saveChanges: { throw InjectedError.saveFailed }
            )
        ) { error in
            XCTAssertEqual(error as? InjectedError, .saveFailed)
        }

        guard case .drink(let restoredRecord) = try storedRecord.decodeRecord() else {
            return XCTFail("Expected the original record after the failed edit")
        }
        XCTAssertEqual(restoredRecord.drinkName, "原记录")
        XCTAssertEqual(restoredRecord.photo, oldPhoto)
        XCTAssertEqual(try photoStore.load(oldPhoto), oldBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoStore.directoryURL.appendingPathComponent(newPhoto.fileName).path))
        XCTAssertTrue(tracker.hasPendingChanges)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: StoredJournalRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GanfanRecordCommitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
