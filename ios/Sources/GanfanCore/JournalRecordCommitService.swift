import Foundation
import SwiftData

@MainActor
public enum JournalRecordCommitService {
    public static func save(
        _ record: JournalRecord,
        replacing recordID: UUID? = nil,
        createdPhotoAssets: [PhotoAsset],
        photoStore: LocalPhotoStore,
        into library: JournalSQLiteStore,
        changeTracker: BackupChangeTracker = BackupChangeTracker()
    ) throws {
        do {
            try record.validate()
            if let recordID, recordID != record.id {
                throw StoredJournalRecordError.invalidRecordIdentifier
            }
            for asset in photoAssets(in: record) {
                _ = try photoStore.load(asset)
            }
            try library.save(record)
            changeTracker.markChanged()
        } catch {
            for asset in createdPhotoAssets {
                try? photoStore.remove(asset)
            }
            throw error
        }
    }

    public static func save(
        _ record: JournalRecord,
        replacing storedRecord: StoredJournalRecord? = nil,
        createdPhotoAssets: [PhotoAsset],
        photoStore: LocalPhotoStore,
        into context: ModelContext,
        changeTracker: BackupChangeTracker = BackupChangeTracker(),
        saveChanges: (@MainActor () throws -> Void)? = nil
    ) throws {
        do {
            try record.validate()
            for asset in photoAssets(in: record) {
                _ = try photoStore.load(asset)
            }

            let previousState = storedRecord.map(StoredJournalRecordState.init)
            do {
                if let storedRecord {
                    try storedRecord.replace(with: record)
                } else {
                    context.insert(try StoredJournalRecord(record: record))
                }

                changeTracker.markChanged()
                if let saveChanges {
                    try saveChanges()
                } else {
                    try context.save()
                }
            } catch {
                context.rollback()
                if let storedRecord, let previousState {
                    previousState.restore(to: storedRecord)
                }
                throw error
            }
        } catch {
            for asset in createdPhotoAssets {
                try? photoStore.remove(asset)
            }
            throw error
        }
    }

    private static func photoAssets(in record: JournalRecord) -> [PhotoAsset] {
        switch record {
        case .drink(let drink):
            return drink.photo.map { [$0] } ?? []
        case .meal(let meal):
            return meal.dishes.compactMap(\.photo)
        }
    }
}

private struct StoredJournalRecordState {
    let recordType: String
    let consumedAt: Date
    let payloadVersion: Int
    let payload: Data
    let needsBackup: Bool

    init(_ record: StoredJournalRecord) {
        recordType = record.recordType
        consumedAt = record.consumedAt
        payloadVersion = record.payloadVersion
        payload = record.payload
        needsBackup = record.needsBackup
    }

    func restore(to record: StoredJournalRecord) {
        record.recordType = recordType
        record.consumedAt = consumedAt
        record.payloadVersion = payloadVersion
        record.payload = payload
        record.needsBackup = needsBackup
    }
}
