import Foundation
import SwiftData

public enum JournalLibraryRestoreError: Error, Equatable {
    case libraryNotEmpty
    case duplicateRecordIdentifier(UUID)
    case photoDataMismatch(UUID)
}

@MainActor
public enum JournalLibraryRestoreService {
    public static func restore(
        _ archive: VerifiedBackupArchive,
        photoStore: LocalPhotoStore,
        catalogRepository: MenuCatalogRepository? = nil,
        into context: ModelContext
    ) async throws {
        try ensureEmpty(context)
        try archive.snapshot.validate()
        try archive.snapshot.catalogState?.validate()

        let expectedPhotoIDs = Set(archive.snapshot.photos.map(\.id))
        guard Set(archive.photoData.keys) == expectedPhotoIDs else {
            let mismatchID = expectedPhotoIDs.symmetricDifference(Set(archive.photoData.keys))
                .sorted { $0.uuidString < $1.uuidString }
                .first ?? UUID()
            throw JournalLibraryRestoreError.photoDataMismatch(mismatchID)
        }

        let targetCatalogState = archive.snapshot.catalogState
        let settingsRepository = targetCatalogState == nil ? nil : (catalogRepository ?? MenuCatalogRepository())
        let previousCatalogState = try settingsRepository?.loadUserState()
        if let targetCatalogState {
            try settingsRepository?.saveUserState(targetCatalogState)
        }

        do {
            let importedAssets = try await Task.detached(priority: .utility) {
                var imported: [PhotoAsset] = []
                do {
                    for asset in archive.snapshot.photos {
                        guard let bytes = archive.photoData[asset.id] else {
                            throw JournalLibraryRestoreError.photoDataMismatch(asset.id)
                        }
                        if try photoStore.importVerified(bytes, as: asset) {
                            imported.append(asset)
                        }
                    }
                    return imported
                } catch {
                    for asset in imported { try? photoStore.remove(asset) }
                    throw error
                }
            }.value

            do {
                try restore(archive.snapshot.records, into: context)
            } catch {
                for asset in importedAssets { try? photoStore.remove(asset) }
                throw error
            }
        } catch {
            if let previousCatalogState {
                try? settingsRepository?.saveUserState(previousCatalogState)
            }
            throw error
        }
    }

    public static func restore(_ records: [JournalRecord], into context: ModelContext) throws {
        try ensureEmpty(context)

        var identifiers = Set<UUID>()
        for record in records {
            try record.validate()
            guard identifiers.insert(record.id).inserted else {
                throw JournalLibraryRestoreError.duplicateRecordIdentifier(record.id)
            }
        }

        let storedRecords = try records.map { try StoredJournalRecord(record: $0, needsBackup: false) }
        do {
            try context.transaction {
                for storedRecord in storedRecords {
                    context.insert(storedRecord)
                }
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func ensureEmpty(_ context: ModelContext) throws {
        let existingCount = try context.fetchCount(FetchDescriptor<StoredJournalRecord>())
        guard existingCount == 0 else {
            throw JournalLibraryRestoreError.libraryNotEmpty
        }
    }
}
