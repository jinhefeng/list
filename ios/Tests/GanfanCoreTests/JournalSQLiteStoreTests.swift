import Foundation
import XCTest
import SwiftData
@testable import GanfanCore

@MainActor
final class JournalSQLiteStoreTests: XCTestCase {
    func testBootstrapMigratesReadableAndUnreadableSwiftDataRowsWithoutTouchingSource() async throws {
        let directory = try makeTemporaryDirectory()
        let container = try ModelContainer(
            for: StoredJournalRecord.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("legacy.store"))
        )
        let context = ModelContext(container)
        let validRecord = try DrinkRecord(drinkName: "可迁移饮品")
        let validStoredRow = try StoredJournalRecord(record: .drink(validRecord), needsBackup: false)
        let invalidStoredRow = try StoredJournalRecord(record: .drink(try DrinkRecord(drinkName: "旧格式记录")))
        let invalidBytes = Data([0x7B, 0x00, 0xFF, 0x39])
        invalidStoredRow.payloadVersion = 89
        invalidStoredRow.payload = invalidBytes
        context.insert(validStoredRow)
        context.insert(invalidStoredRow)
        try context.save()

        let sourceRowsBeforeMigration = try context.fetch(FetchDescriptor<StoredJournalRecord>())
        let sourceSnapshots = sourceRowsBeforeMigration.map { $0.decodingSnapshot() }
        let legacyURL = directory.appendingPathComponent("legacy.store")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))

        let destination = directory.appendingPathComponent("library.sqlite")
        let migrated = try await JournalDatabaseBootstrapper.open(
            at: destination,
            migratingFrom: container
        )
        defer { migrated.close() }

        XCTAssertTrue(migrated.migrationComplete)
        XCTAssertEqual(try migrated.migrationCounts().records, 1)
        XCTAssertEqual(try migrated.migrationCounts().legacy, 1)
        let expectedValidRecord = try XCTUnwrap(
            sourceSnapshots.first(where: { $0.recordID == validRecord.id.uuidString })
        ).decodeRecord()
        XCTAssertEqual(try migrated.record(id: validRecord.id)?.record, expectedValidRecord)
        XCTAssertEqual(try migrated.record(id: validRecord.id)?.needsBackup, false)
        XCTAssertTrue(try migrated.matchesImportedLegacySnapshot(try XCTUnwrap(
            sourceSnapshots.first(where: { $0.payloadVersion == 89 })
        )))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredJournalRecord>()), 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathExtension("migrating").path))

        let reopened = try await JournalDatabaseBootstrapper.open(at: destination, migratingFrom: nil)
        XCTAssertTrue(reopened.migrationComplete)
        XCTAssertEqual(try reopened.count(), 1)
        reopened.close()
    }

    func testHistoryPagesKeepLocalDayOrderingAndSearchUnloadedRecords() throws {
        let directory = try makeTemporaryDirectory()
        let store = try JournalSQLiteStore(url: directory.appendingPathComponent("library.sqlite"))
        defer { store.close() }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tieDate = today.addingTimeInterval(9 * 60 * 60)
        let first = try DrinkRecord(
            id: uuid("10000000-0000-0000-0000-000000000001"),
            consumedAt: tieDate,
            drinkName: "同秒第一条"
        )
        let second = try DrinkRecord(
            id: uuid("10000000-0000-0000-0000-000000000002"),
            consumedAt: tieDate,
            drinkName: "同秒第二条"
        )
        let laterToday = try DrinkRecord(
            id: uuid("10000000-0000-0000-0000-000000000003"),
            consumedAt: today.addingTimeInterval(10 * 60 * 60),
            drinkName: "今天稍晚"
        )
        let oldDate = try XCTUnwrap(calendar.date(byAdding: .year, value: -8, to: today))
        let old = try DrinkRecord(
            id: uuid("10000000-0000-0000-0000-000000000004"),
            consumedAt: oldDate.addingTimeInterval(12 * 60 * 60),
            drinkName: "八年前唯一命中",
            notes: "多年之前的稀有词"
        )
        for record in [old, laterToday, second, first] {
            try store.save(.drink(record))
        }

        let firstPage = try store.historyPage(query: JournalHistoryQuery(), limit: 2)
        let secondPage = try store.historyPage(query: JournalHistoryQuery(), after: try XCTUnwrap(firstPage.nextCursor), limit: 2)

        XCTAssertEqual(firstPage.items.map(\.id), [first.id, second.id])
        XCTAssertEqual(secondPage.items.map(\.id), [laterToday.id, old.id])
        XCTAssertFalse(secondPage.hasMore)

        let allHistorySearch = try store.historyPage(
            query: JournalHistoryQuery(searchText: "稀有词"),
            limit: 2
        )
        XCTAssertEqual(allHistorySearch.items.map(\.id), [old.id])
    }

    func testTenYearsOfRecordsCanBePagedWithoutDuplicatesAndSearchOldestEntry() throws {
        let directory = try makeTemporaryDirectory()
        let store = try JournalSQLiteStore(url: directory.appendingPathComponent("library.sqlite"))
        defer { store.close() }

        let firstDate = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: -10, to: .now))
        var records: [JournalRecord] = []
        records.reserveCapacity(22_000)
        for index in 0..<22_000 {
            let record = try DrinkRecord(
                consumedAt: firstDate.addingTimeInterval(Double(index) * 4 * 60 * 60),
                drinkName: "样本饮品 \(index)",
                notes: index == 0 ? "多年以前唯一命中" : ""
            )
            records.append(.drink(record))
        }
        try store.restoreRecords(records)

        var cursor: JournalHistoryCursor?
        var pageCount = 0
        var seenIDs = Set<UUID>()
        while true {
            let page = try store.historyPage(query: JournalHistoryQuery(), after: cursor, limit: 50)
            pageCount += 1
            for item in page.items {
                XCTAssertTrue(seenIDs.insert(item.id).inserted, "A record appeared in more than one page")
            }
            guard page.hasMore else { break }
            cursor = try XCTUnwrap(page.nextCursor)
        }
        XCTAssertEqual(pageCount, 440)
        XCTAssertEqual(seenIDs.count, 22_000)

        let oldestRecord = try XCTUnwrap(records.first)
        let oldestMatch = try store.historyPage(
            query: JournalHistoryQuery(searchText: "多年以前唯一命中"),
            limit: 50
        )
        XCTAssertEqual(oldestMatch.items.map(\.id), [oldestRecord.id])
        XCTAssertFalse(oldestMatch.hasMore)
    }

    func testReplacingRecordRemovesOldNutritionSources() throws {
        let directory = try makeTemporaryDirectory()
        let store = try JournalSQLiteStore(url: directory.appendingPathComponent("library.sqlite"))
        defer { store.close() }

        let id = uuid("20000000-0000-0000-0000-000000000001")
        let original = try DrinkRecord(
            id: id,
            drinkName: "原记录",
            nutrition: NutritionSnapshot(
                energyKcal: 100,
                sugarGrams: nil,
                caffeineMilligrams: nil,
                confidence: .official,
                metricSources: ["energyKcal": "official"]
            )
        )
        let replacement = try DrinkRecord(
            id: id,
            drinkName: "编辑后",
            nutrition: NutritionSnapshot(
                energyKcal: nil,
                sugarGrams: 10,
                caffeineMilligrams: nil,
                confidence: .estimated,
                metricSources: ["sugarGrams": "estimated"]
            )
        )
        try store.save(.drink(original))
        try store.save(.drink(replacement))

        let saved = try XCTUnwrap(store.record(id: id))
        guard case .drink(let drink) = saved.record else { return XCTFail("Expected a drink record") }
        XCTAssertEqual(drink.drinkName, "编辑后")
        XCTAssertEqual(drink.nutrition?.metricSources, ["sugarGrams": "estimated"])
    }

    func testSQLiteBackupRestoresUnreadableLegacyPayloadAsSingleDatabaseFile() throws {
        let directory = try makeTemporaryDirectory()
        let source = try JournalSQLiteStore(url: directory.appendingPathComponent("source.sqlite"))
        try source.markMigrationComplete()
        let rawPayload = Data([0x7B, 0x00, 0xFF, 0x31])
        let legacy = StoredJournalRecordSnapshot(
            recordID: "30000000-0000-0000-0000-000000000001",
            recordType: "drink",
            consumedAt: Date(timeIntervalSince1970: 1_700_000_000),
            payloadVersion: 99,
            payload: rawPayload,
            needsBackup: true
        )
        try source.importLegacy(legacy)
        XCTAssertTrue(try source.matchesImportedLegacySnapshot(legacy))

        let backupFolder = directory.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        let backupStore = BackupDirectoryStore(userSelectedFolderURL: backupFolder)
        let snapshot = try BackupSnapshot(libraryID: UUID(), records: [])
        let result = try backupStore.writeSQLite(
            snapshot: snapshot,
            library: source,
            changeGeneration: 4,
            databaseGeneration: source.dataGeneration,
            photoData: [:]
        )

        XCTAssertEqual(URL(fileURLWithPath: result.fileName).pathExtension, "sqlite")
        XCTAssertEqual(result.legacyIssueCount, 1)
        let archive = try backupStore.loadSnapshot(named: result.fileName)
        XCTAssertEqual(archive.snapshot.records, [])
        XCTAssertEqual(try XCTUnwrap(backupStore.listSnapshots().first).legacyIssueCount, 1)

        let archivedDatabase = try XCTUnwrap(archive.databaseSnapshotURL)
        defer { try? FileManager.default.removeItem(at: archivedDatabase) }
        let restored = try JournalSQLiteStore(url: directory.appendingPathComponent("restored.sqlite"))
        defer { restored.close() }
        try restored.markMigrationComplete()
        try restored.restoreDatabase(from: archivedDatabase)

        XCTAssertEqual(try restored.count(), 0)
        XCTAssertEqual(try restored.legacyIssueCount(), 1)
        XCTAssertEqual(try restored.pendingBackupCount(), 0)
        XCTAssertTrue(try restored.matchesImportedLegacySnapshot(StoredJournalRecordSnapshot(
            recordID: legacy.recordID,
            recordType: legacy.recordType,
            consumedAt: legacy.consumedAt,
            payloadVersion: legacy.payloadVersion,
            payload: rawPayload,
            needsBackup: false
        )))
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JournalSQLiteStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
