import Foundation
import SwiftData

public enum JournalLibraryRestoreError: Error, Equatable {
    case libraryNotEmpty
    case duplicateRecordIdentifier(UUID)
    case photoDataMismatch(UUID)
    case brandLogoDataMismatch(UUID)
}

@MainActor
public enum JournalLibraryRestoreService {
    public static func restore(
        _ archive: VerifiedBackupArchive,
        photoStore: LocalPhotoStore,
        catalogRepository: MenuCatalogRepository? = nil,
        brandLogoStore: LocalPhotoStore? = nil,
        nutritionRepository: NutritionUpdateRepository? = nil,
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
        let brandLogoAssets = archive.snapshot.brandLogoAssets ?? []
        let expectedBrandLogoIDs = Set(brandLogoAssets.map(\.id))
        guard Set(archive.brandLogoData.keys) == expectedBrandLogoIDs else {
            let mismatchID = expectedBrandLogoIDs.symmetricDifference(Set(archive.brandLogoData.keys))
                .sorted { $0.uuidString < $1.uuidString }
                .first ?? UUID()
            throw JournalLibraryRestoreError.brandLogoDataMismatch(mismatchID)
        }
        if !brandLogoAssets.isEmpty, brandLogoStore == nil {
            throw JournalLibraryRestoreError.brandLogoDataMismatch(brandLogoAssets[0].id)
        }

        let targetCatalogState = archive.snapshot.catalogState ?? archive.snapshot.catalog.map {
            MenuCatalogUserState.restoredCatalogOverlay(from: $0, settings: nil)
        }
        let settingsRepository = targetCatalogState == nil ? nil : (catalogRepository ?? MenuCatalogRepository())
        let nutritionRepository = archive.snapshot.catalog == nil ? nil : (nutritionRepository ?? NutritionUpdateRepository())
        let previousCatalogState = try settingsRepository?.loadUserState()
        let previousNutritionPack = nutritionRepository?.load()
        do {
            if let targetCatalogState {
                try settingsRepository?.saveUserState(targetCatalogState)
            }
            if let nutritionRepository {
                try nutritionRepository.restore(archive.snapshot.nutritionDataPack)
            }
        } catch {
            if let previousCatalogState {
                try? settingsRepository?.saveUserState(previousCatalogState)
            }
            if let nutritionRepository {
                try? nutritionRepository.restore(previousNutritionPack)
            }
            throw error
        }

        do {
            let importedAssets = try await Task.detached(priority: .utility) {
                var importedPhotos: [PhotoAsset] = []
                var importedLogos: [PhotoAsset] = []
                do {
                    for asset in archive.snapshot.photos {
                        guard let bytes = archive.photoData[asset.id] else {
                            throw JournalLibraryRestoreError.photoDataMismatch(asset.id)
                        }
                        if try photoStore.importVerified(bytes, as: asset) {
                            importedPhotos.append(asset)
                        }
                    }
                    if let brandLogoStore {
                        for asset in brandLogoAssets {
                            guard let bytes = archive.brandLogoData[asset.id] else {
                                throw JournalLibraryRestoreError.brandLogoDataMismatch(asset.id)
                            }
                            if try brandLogoStore.importVerified(bytes, as: asset) {
                                importedLogos.append(asset)
                            }
                        }
                    }
                    return (importedPhotos, importedLogos)
                } catch {
                    for asset in importedPhotos { try? photoStore.remove(asset) }
                    for asset in importedLogos { try? brandLogoStore?.remove(asset) }
                    throw error
                }
            }.value

            do {
                try restore(archive.snapshot.records, into: context)
            } catch {
                for asset in importedAssets.0 { try? photoStore.remove(asset) }
                for asset in importedAssets.1 { try? brandLogoStore?.remove(asset) }
                throw error
            }
        } catch {
            if let previousCatalogState {
                try? settingsRepository?.saveUserState(previousCatalogState)
            }
            if let nutritionRepository {
                try? nutritionRepository.restore(previousNutritionPack)
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
