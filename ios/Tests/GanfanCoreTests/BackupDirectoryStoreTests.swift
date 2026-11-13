import Foundation
import SwiftData
import XCTest
@testable import GanfanCore

final class BackupDirectoryStoreTests: XCTestCase {
    func testWritesAndRestoresSnapshotWithVerifiedOriginalPhoto() throws {
        let selectedFolder = try makeTemporaryDirectory()
        let localPhotos = LocalPhotoStore(directoryURL: selectedFolder.appendingPathComponent("local-photos"))
        let originalBytes = Data("original photo bytes".utf8)
        let asset = try localPhotos.save(originalBytes, fileExtension: "jpg")
        let record = try DrinkRecord(drinkName: "拿铁", photo: asset)
        let catalogState = MenuCatalogUserState(
            drinks: [MenuDrink(id: "custom-1", brandID: "", brandName: "", name: "自定义", custom: true)],
            deletedDrinkIDs: ["deleted-1"],
            globalCupSizes: [MenuCupSize(cupType: "中杯", sizeML: 500)]
        )
        let snapshot = try BackupSnapshot(libraryID: UUID(), records: [.drink(record)], catalogState: catalogState)
        let store = BackupDirectoryStore(userSelectedFolderURL: selectedFolder)

        let result = try store.write(snapshot: snapshot, photoData: [asset.id: originalBytes])
        let archive = try store.loadSnapshot(named: result.fileName)

        XCTAssertEqual(result.recordCount, 1)
        XCTAssertEqual(result.photoCount, 1)
        XCTAssertEqual(archive.snapshot, snapshot)
        XCTAssertEqual(archive.snapshot.catalogState, catalogState)
        XCTAssertEqual(archive.photoData[asset.id], originalBytes)
        XCTAssertEqual(try store.listSnapshots().map(\.fileName), [result.fileName])
    }

    func testSnapshotDecodesLegacyPayloadWithoutCatalogSettings() throws {
        let snapshot = try BackupSnapshot(libraryID: UUID(), records: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any])
        json.removeValue(forKey: "catalogState")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let legacySnapshot = try decoder.decode(BackupSnapshot.self, from: legacyData)

        XCTAssertNil(legacySnapshot.catalogState)
        XCTAssertEqual(legacySnapshot.libraryID, snapshot.libraryID)
        XCTAssertEqual(legacySnapshot.records, [])
        XCTAssertNoThrow(try legacySnapshot.validate())
    }

    func testReusesMatchingPhotoButRefusesDifferentLibraryIdentity() throws {
        let selectedFolder = try makeTemporaryDirectory()
        let bytes = Data("photo".utf8)
        let asset = try LocalPhotoStore(directoryURL: selectedFolder.appendingPathComponent("local"))
            .save(bytes, fileExtension: "png")
        let store = BackupDirectoryStore(userSelectedFolderURL: selectedFolder)
        let first = try BackupSnapshot(libraryID: UUID(), records: [.drink(try DrinkRecord(drinkName: "茶", photo: asset))])

        _ = try store.write(snapshot: first, photoData: [asset.id: bytes])
        let repeated = try store.write(snapshot: first, photoData: [asset.id: bytes])
        XCTAssertNoThrow(try store.loadSnapshot(named: repeated.fileName))

        let otherLibrary = try BackupSnapshot(libraryID: UUID(), records: [])
        XCTAssertThrowsError(try store.write(snapshot: otherLibrary, photoData: [:])) { error in
            XCTAssertEqual(error as? BackupDirectoryStoreError, .differentLibrary)
        }
    }

    func testRejectsMissingOrTamperedPhotoBeforePublishingSnapshot() throws {
        let selectedFolder = try makeTemporaryDirectory()
        let bytes = Data("safe photo".utf8)
        let asset = try LocalPhotoStore(directoryURL: selectedFolder.appendingPathComponent("local"))
            .save(bytes, fileExtension: "jpg")
        let snapshot = try BackupSnapshot(libraryID: UUID(), records: [.drink(try DrinkRecord(drinkName: "茶", photo: asset))])
        let store = BackupDirectoryStore(userSelectedFolderURL: selectedFolder)

        XCTAssertThrowsError(try store.write(snapshot: snapshot, photoData: [:])) { error in
            XCTAssertEqual(error as? BackupDirectoryStoreError, .photoDataMismatch(asset.id))
        }
        XCTAssertTrue(try store.listSnapshots().isEmpty)

        XCTAssertThrowsError(try store.write(snapshot: snapshot, photoData: [asset.id: Data("changed".utf8)])) { error in
            XCTAssertEqual(error as? BackupDirectoryStoreError, .photoDataMismatch(asset.id))
        }
        XCTAssertTrue(try store.listSnapshots().isEmpty)
    }

    func testRestoreRejectsTamperedBackupPhotoAndKeepsEarlierSnapshotListed() throws {
        let selectedFolder = try makeTemporaryDirectory()
        let bytes = Data("photo bytes".utf8)
        let asset = try LocalPhotoStore(directoryURL: selectedFolder.appendingPathComponent("local"))
            .save(bytes, fileExtension: "jpg")
        let snapshot = try BackupSnapshot(libraryID: UUID(), records: [.drink(try DrinkRecord(drinkName: "茶", photo: asset))])
        let store = BackupDirectoryStore(userSelectedFolderURL: selectedFolder)
        let first = try store.write(snapshot: snapshot, photoData: [asset.id: bytes])
        let second = try store.write(snapshot: snapshot, photoData: [asset.id: bytes])

        let backedUpPhoto = store.backupDirectoryURL
            .appendingPathComponent("photos", isDirectory: true)
            .appendingPathComponent(asset.fileName)
        try Data("tampered".utf8).write(to: backedUpPhoto)

        XCTAssertThrowsError(try store.loadSnapshot(named: second.fileName)) { error in
            XCTAssertEqual(error as? BackupDirectoryStoreError, .photoIntegrityMismatch(asset.id))
        }
        XCTAssertEqual(Set(try store.listSnapshots().map(\.fileName)), Set([first.fileName, second.fileName]))
    }

    func testDoesNotOverwriteUnrecognizedDataInAppBackupFolder() throws {
        let selectedFolder = try makeTemporaryDirectory()
        let store = BackupDirectoryStore(userSelectedFolderURL: selectedFolder)
        try FileManager.default.createDirectory(at: store.backupDirectoryURL, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: store.backupDirectoryURL.appendingPathComponent("notes.txt"))
        let snapshot = try BackupSnapshot(libraryID: UUID(), records: [])

        XCTAssertThrowsError(try store.write(snapshot: snapshot, photoData: [:])) { error in
            XCTAssertEqual(error as? BackupDirectoryStoreError, .unrecognizedExistingData)
        }
        XCTAssertEqual(try Data(contentsOf: store.backupDirectoryURL.appendingPathComponent("notes.txt")), Data("keep me".utf8))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GanfanBackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

@MainActor
final class JournalLibraryRestoreTests: XCTestCase {
    func testRestoresRecordsToAnEmptyLibraryAndMarksThemBackedUp() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let drink = try DrinkRecord(drinkName: "燕麦拿铁")
        let meal = try MealRecord(dishes: [try MealDish(name: "米饭"), try MealDish(name: "青菜")])

        try JournalLibraryRestoreService.restore([.drink(drink), .meal(meal)], into: context)

        let restored = try context.fetch(FetchDescriptor<StoredJournalRecord>())
        XCTAssertEqual(restored.count, 2)
        XCTAssertTrue(restored.allSatisfy { !$0.needsBackup })
        XCTAssertEqual(Set(try restored.map { try $0.decodeRecord().id }), Set([drink.id, meal.id]))
    }

    func testRefusesToRestoreIntoPopulatedLibraryWithoutChangingIt() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let existing = try DrinkRecord(drinkName: "已有记录")
        let incoming = try MealRecord(dishes: [try MealDish(name: "新菜")])
        context.insert(try StoredJournalRecord(record: .drink(existing)))
        try context.save()

        XCTAssertThrowsError(try JournalLibraryRestoreService.restore([.meal(incoming)], into: context)) { error in
            XCTAssertEqual(error as? JournalLibraryRestoreError, .libraryNotEmpty)
        }
        let records = try context.fetch(FetchDescriptor<StoredJournalRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(try records.first?.decodeRecord().id, existing.id)
    }

    func testRestoresRecordAndOriginalPhotoFromVerifiedArchive() async throws {
        let selectedFolder = try makeTemporaryDirectory()
        let photoBytes = Data("meal photo".utf8)
        let sourcePhotoStore = LocalPhotoStore(directoryURL: selectedFolder.appendingPathComponent("source-photos"))
        let photo = try sourcePhotoStore.save(photoBytes, fileExtension: "jpg")
        let drink = try DrinkRecord(drinkName: "冰美式", photo: photo)
        let snapshot = try BackupSnapshot(libraryID: UUID(), records: [.drink(drink)])
        let backupStore = BackupDirectoryStore(userSelectedFolderURL: selectedFolder)
        let backup = try backupStore.write(snapshot: snapshot, photoData: [photo.id: photoBytes])
        let archive = try backupStore.loadSnapshot(named: backup.fileName)
        let restoredPhotoStore = LocalPhotoStore(directoryURL: selectedFolder.appendingPathComponent("restored-photos"))
        let context = ModelContext(try makeInMemoryContainer())

        try await JournalLibraryRestoreService.restore(archive, photoStore: restoredPhotoStore, into: context)

        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<StoredJournalRecord>()).first)
        guard case .drink(let restoredDrink) = try restored.decodeRecord() else {
            return XCTFail("Expected the restored drink record")
        }
        XCTAssertEqual(restoredDrink.id, drink.id)
        XCTAssertEqual(restoredDrink.drinkName, drink.drinkName)
        XCTAssertEqual(restoredDrink.photo, photo)
        XCTAssertEqual(try restoredPhotoStore.load(photo), photoBytes)
        XCTAssertFalse(restored.needsBackup)
    }

    func testRestoresCatalogOverridesAndCupSizesWithTheEmptyLibrary() async throws {
        let suiteName = "JournalLibraryRestoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = MenuCatalogRepository(userDefaults: defaults)
        let previousState = MenuCatalogUserState(globalCupSizes: [MenuCupSize(cupType: "旧杯", sizeML: 350)])
        let restoredState = MenuCatalogUserState(
            drinks: [MenuDrink(id: "custom-drink", brandID: "", brandName: "", name: "自定义饮品", custom: true)],
            deletedDrinkIDs: ["removed-drink"],
            globalCupSizes: [MenuCupSize(cupType: "中杯", sizeML: 500)]
        )
        try repository.saveUserState(previousState)
        let drink = try DrinkRecord(drinkName: "手冲咖啡")
        let snapshot = try BackupSnapshot(
            libraryID: UUID(),
            records: [.drink(drink)],
            catalogState: restoredState
        )
        let archive = VerifiedBackupArchive(snapshot: snapshot, photoData: [:])
        let photoStore = LocalPhotoStore(directoryURL: try makeTemporaryDirectory().appendingPathComponent("photos"))
        let context = ModelContext(try makeInMemoryContainer())

        try await JournalLibraryRestoreService.restore(
            archive,
            photoStore: photoStore,
            catalogRepository: repository,
            into: context
        )

        XCTAssertEqual(try repository.loadUserState(), restoredState)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredJournalRecord>()).count, 1)
    }

    func testTamperedArchiveCreatesNoPartialPhotosOrRecords() async throws {
        let selectedFolder = try makeTemporaryDirectory()
        let sourcePhotoStore = LocalPhotoStore(directoryURL: selectedFolder.appendingPathComponent("source-photos"))
        let firstBytes = Data("first photo".utf8)
        let secondBytes = Data("second photo".utf8)
        let firstPhoto = try sourcePhotoStore.save(firstBytes, fileExtension: "jpg")
        let secondPhoto = try sourcePhotoStore.save(secondBytes, fileExtension: "png")
        let meal = try MealRecord(dishes: [
            try MealDish(name: "主菜", photo: firstPhoto),
            try MealDish(name: "配菜", photo: secondPhoto)
        ])
        let suiteName = "JournalLibraryRestoreRollbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = MenuCatalogRepository(userDefaults: defaults)
        let previousState = MenuCatalogUserState(globalCupSizes: [MenuCupSize(cupType: "旧杯", sizeML: 350)])
        let incomingState = MenuCatalogUserState(globalCupSizes: [MenuCupSize(cupType: "新杯", sizeML: 500)])
        try repository.saveUserState(previousState)
        let snapshot = try BackupSnapshot(libraryID: UUID(), records: [.meal(meal)], catalogState: incomingState)
        let backupStore = BackupDirectoryStore(userSelectedFolderURL: selectedFolder)
        let backup = try backupStore.write(
            snapshot: snapshot,
            photoData: [firstPhoto.id: firstBytes, secondPhoto.id: secondBytes]
        )
        let verifiedArchive = try backupStore.loadSnapshot(named: backup.fileName)
        var alteredPhotoData = verifiedArchive.photoData
        let lastAsset = try XCTUnwrap(verifiedArchive.snapshot.photos.last)
        alteredPhotoData[lastAsset.id] = Data("tampered".utf8)
        let invalidArchive = VerifiedBackupArchive(snapshot: verifiedArchive.snapshot, photoData: alteredPhotoData)
        let restoredPhotoStore = LocalPhotoStore(directoryURL: selectedFolder.appendingPathComponent("restored-photos"))
        let context = ModelContext(try makeInMemoryContainer())

        do {
            try await JournalLibraryRestoreService.restore(
                invalidArchive,
                photoStore: restoredPhotoStore,
                catalogRepository: repository,
                into: context
            )
            XCTFail("Expected the modified photo to be rejected")
        } catch {
            XCTAssertEqual(error as? LocalPhotoStoreError, .integrityMismatch)
        }

        XCTAssertTrue(try context.fetch(FetchDescriptor<StoredJournalRecord>()).isEmpty)
        XCTAssertEqual(try repository.loadUserState(), previousState)
        if FileManager.default.fileExists(atPath: restoredPhotoStore.directoryURL.path) {
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: restoredPhotoStore.directoryURL.path).isEmpty)
        }
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: StoredJournalRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GanfanRestoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
