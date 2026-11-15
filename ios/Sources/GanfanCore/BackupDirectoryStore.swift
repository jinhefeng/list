import CryptoKit
import Foundation

public enum BackupSnapshotError: Error, Equatable {
    case unsupportedFormatVersion(Int)
    case invalidCreationTime
    case duplicateRecordIdentifier(UUID)
    case conflictingPhotoAsset(UUID)
    case invalidPhotoManifest
    case invalidBrandLogoManifest
    case invalidCatalogManifest
}

public struct BackupSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let libraryID: UUID
    public let createdAt: Date
    public let records: [JournalRecord]
    public let photos: [PhotoAsset]
    public let catalogState: MenuCatalogUserState?
    public let brandLogoAssets: [PhotoAsset]?
    public let catalog: MenuCatalog?
    public let nutritionDataPack: NutritionDataPack?

    public init(
        libraryID: UUID,
        records: [JournalRecord],
        catalogState: MenuCatalogUserState? = nil,
        brandLogoAssets: [PhotoAsset] = [],
        catalog: MenuCatalog? = nil,
        nutritionDataPack: NutritionDataPack? = nil,
        createdAt: Date = .now
    ) throws {
        self.formatVersion = Self.currentFormatVersion
        self.libraryID = libraryID
        let createdAtMilliseconds = (createdAt.timeIntervalSince1970 * 1_000).rounded(.down)
        self.createdAt = Date(timeIntervalSince1970: createdAtMilliseconds / 1_000)
        let normalizedRecords = try records.map { record in
            try JournalRecordCodec.decode(JournalRecordCodec.encode(record))
        }
        self.records = JournalRecord.newestFirst(normalizedRecords)
        try catalogState?.validate()
        self.catalogState = catalogState
        self.photos = try Self.photoManifest(for: normalizedRecords)
        self.brandLogoAssets = brandLogoAssets
        self.catalog = catalog
        self.nutritionDataPack = nutritionDataPack
        try validate()
    }

    public func validate() throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw BackupSnapshotError.unsupportedFormatVersion(formatVersion)
        }
        guard createdAt.timeIntervalSince1970.isFinite else {
            throw BackupSnapshotError.invalidCreationTime
        }

        var recordIDs = Set<UUID>()
        var referencedPhotos: [UUID: PhotoAsset] = [:]
        for record in records {
            try record.validate()
            guard recordIDs.insert(record.id).inserted else {
                throw BackupSnapshotError.duplicateRecordIdentifier(record.id)
            }
            for asset in Self.assets(in: record) {
                if let previous = referencedPhotos[asset.id], previous != asset {
                    throw BackupSnapshotError.conflictingPhotoAsset(asset.id)
                }
                referencedPhotos[asset.id] = asset
            }
        }

        guard records == JournalRecord.newestFirst(records) else {
            throw BackupSnapshotError.invalidPhotoManifest
        }
        try catalogState?.validate()

        let brandLogos = brandLogoAssets ?? []
        var brandLogoIDs = Set<UUID>()
        for asset in brandLogos {
            try asset.validate()
            guard asset.fileExtension == "png", brandLogoIDs.insert(asset.id).inserted else {
                throw BackupSnapshotError.invalidBrandLogoManifest
            }
        }
        let referencedLogoIDs = Set(catalogState?.brands.compactMap(\.logoImageID) ?? [])
        guard referencedLogoIDs.isSubset(of: brandLogoIDs) else {
            throw BackupSnapshotError.invalidBrandLogoManifest
        }

        if let catalog {
            var brandIDs = Set<String>()
            for brand in catalog.brands {
                guard !brand.id.isEmpty, brandIDs.insert(brand.id).inserted else {
                    throw BackupSnapshotError.invalidCatalogManifest
                }
            }
            var drinkIDs = Set<String>()
            for drink in catalog.drinks {
                guard !drink.id.isEmpty, !drink.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      drinkIDs.insert(drink.id).inserted else {
                    throw BackupSnapshotError.invalidCatalogManifest
                }
            }
            let catalogLogoIDs = Set(catalog.brands.compactMap(\.logoImageID))
            guard catalogLogoIDs.isSubset(of: brandLogoIDs) else {
                throw BackupSnapshotError.invalidBrandLogoManifest
            }
        }
        try nutritionDataPack?.validate()

        for asset in photos {
            try asset.validate()
        }
        let manifest = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard manifest.count == photos.count, manifest == referencedPhotos else {
            throw BackupSnapshotError.invalidPhotoManifest
        }
    }

    fileprivate func hasSameContent(as other: BackupSnapshot) -> Bool {
        formatVersion == other.formatVersion
            && libraryID == other.libraryID
            && records == other.records
            && photos == other.photos
            && catalogState == other.catalogState
            && (brandLogoAssets ?? []) == (other.brandLogoAssets ?? [])
            && catalog == other.catalog
            && nutritionDataPack == other.nutritionDataPack
    }

    private static func photoManifest(for records: [JournalRecord]) throws -> [PhotoAsset] {
        var assetsByID: [UUID: PhotoAsset] = [:]
        for record in records {
            try record.validate()
            for asset in assets(in: record) {
                if let existing = assetsByID[asset.id], existing != asset {
                    throw BackupSnapshotError.conflictingPhotoAsset(asset.id)
                }
                assetsByID[asset.id] = asset
            }
        }
        return assetsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private static func assets(in record: JournalRecord) -> [PhotoAsset] {
        switch record {
        case .drink(let drink):
            return drink.photo.map { [$0] } ?? []
        case .meal(let meal):
            return meal.dishes.compactMap(\.photo)
        }
    }
}

public enum BackupDirectoryStoreError: Error, Equatable {
    case selectedFolderUnavailable
    case unrecognizedExistingData
    case invalidLibraryMarker
    case unsupportedLibraryVersion(Int)
    case differentLibrary
    case invalidSnapshotName
    case snapshotNotFound
    case photoDataMismatch(UUID)
    case photoIntegrityMismatch(UUID)
    case brandLogoDataMismatch(UUID)
    case brandLogoIntegrityMismatch(UUID)
    case coordinatedReadFailed(String)
    case cleanupPlanChanged
    case cleanupRequiresVerifiedSnapshot
}

public struct BackupWriteResult: Equatable, Sendable {
    public let fileName: String
    public let createdAt: Date
    public let recordCount: Int
    public let photoCount: Int
    public let brandLogoCount: Int
    public let brandCount: Int
    public let drinkCount: Int
    public let nutritionEntryCount: Int
    public let didCreateSnapshot: Bool
}

public struct BackupCleanupPreview: Equatable, Sendable {
    public let snapshotFileNames: [String]
    public let snapshotBytes: Int64
    public let orphanedPhotoCount: Int
    public let orphanedPhotoBytes: Int64

    public var snapshotCount: Int { snapshotFileNames.count }
    public var estimatedBytesFreed: Int64 { snapshotBytes + orphanedPhotoBytes }
}

public struct BackupSnapshotSummary: Equatable, Identifiable, Sendable {
    public let fileName: String
    public let createdAt: Date
    public let recordCount: Int
    public let photoCount: Int
    public let brandLogoCount: Int
    public let includesCatalog: Bool
    public let brandCount: Int
    public let drinkCount: Int
    public let nutritionEntryCount: Int

    public var id: String { fileName }
}

public struct VerifiedBackupArchive: Equatable, Sendable {
    public let snapshot: BackupSnapshot
    public let photoData: [UUID: Data]
    public let brandLogoData: [UUID: Data]

    public init(snapshot: BackupSnapshot, photoData: [UUID: Data], brandLogoData: [UUID: Data] = [:]) {
        self.snapshot = snapshot
        self.photoData = photoData
        self.brandLogoData = brandLogoData
    }
}

public struct BackupDirectoryStore: Sendable {
    public let userSelectedFolderURL: URL

    public init(userSelectedFolderURL: URL) {
        self.userSelectedFolderURL = userSelectedFolderURL
    }

    public var backupDirectoryURL: URL {
        let currentDirectory = userSelectedFolderURL.appendingPathComponent("食光记", isDirectory: true)
        let legacyDirectory = userSelectedFolderURL.appendingPathComponent("干饭手册", isDirectory: true)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: currentDirectory.path)
            || !fileManager.fileExists(atPath: legacyDirectory.path) {
            return currentDirectory
        }
        return legacyDirectory
    }

    public func write(
        snapshot: BackupSnapshot,
        photoData: [UUID: Data],
        brandLogoData: [UUID: Data] = [:]
    ) throws -> BackupWriteResult {
        try snapshot.validate()
        try validatePhotoData(photoData, for: snapshot)
        try validateBrandLogoData(brandLogoData, for: snapshot)
        try prepareLibraryDirectory(for: snapshot.libraryID)

        if let existing = try latestSnapshot(matching: snapshot) {
            return BackupWriteResult(
                fileName: existing.summary.fileName,
                createdAt: existing.snapshot.createdAt,
                recordCount: existing.snapshot.records.count,
                photoCount: existing.snapshot.photos.count,
                brandLogoCount: (existing.snapshot.brandLogoAssets ?? []).count,
                brandCount: existing.snapshot.catalog?.brands.count ?? 0,
                drinkCount: existing.snapshot.catalog?.drinks.count ?? 0,
                nutritionEntryCount: existing.snapshot.nutritionDataPack?.entries.count ?? 0,
                didCreateSnapshot: false
            )
        }

        let photosDirectory = backupDirectoryURL.appendingPathComponent("photos", isDirectory: true)
        let brandLogosDirectory = backupDirectoryURL.appendingPathComponent("brand-logos", isDirectory: true)
        let snapshotsDirectory = backupDirectoryURL.appendingPathComponent("snapshots", isDirectory: true)
        try createDirectoryIfNeeded(at: photosDirectory)
        if !(snapshot.brandLogoAssets ?? []).isEmpty {
            try createDirectoryIfNeeded(at: brandLogosDirectory)
        }
        try createDirectoryIfNeeded(at: snapshotsDirectory)

        for asset in snapshot.photos {
            guard let data = photoData[asset.id] else {
                throw BackupDirectoryStoreError.photoDataMismatch(asset.id)
            }
            try writeOrReusePhoto(data, asset: asset, in: photosDirectory)
        }
        for asset in snapshot.brandLogoAssets ?? [] {
            guard let data = brandLogoData[asset.id] else {
                throw BackupDirectoryStoreError.brandLogoDataMismatch(asset.id)
            }
            try writeOrReuseBrandLogo(data, asset: asset, in: brandLogosDirectory)
        }

        let snapshotData = try Self.encode(snapshot)
        let fileName = "snapshot-\(UUID().uuidString).json"
        _ = try LocalFolderProbe.writeAndVerify(snapshotData, fileName: fileName, in: snapshotsDirectory)
        let savedSnapshot = try Self.decode(readCoordinated(
            from: snapshotsDirectory.appendingPathComponent(fileName, isDirectory: false)
        ))
        guard savedSnapshot == snapshot else {
            throw BackupDirectoryStoreError.coordinatedReadFailed("写入后的快照与原数据不一致。")
        }

        return BackupWriteResult(
            fileName: fileName,
            createdAt: savedSnapshot.createdAt,
            recordCount: savedSnapshot.records.count,
            photoCount: savedSnapshot.photos.count,
            brandLogoCount: (savedSnapshot.brandLogoAssets ?? []).count,
            brandCount: savedSnapshot.catalog?.brands.count ?? 0,
            drinkCount: savedSnapshot.catalog?.drinks.count ?? 0,
            nutritionEntryCount: savedSnapshot.nutritionDataPack?.entries.count ?? 0,
            didCreateSnapshot: true
        )
    }

    public func previewCleanup(now: Date = .now, calendar: Calendar = .current) throws -> BackupCleanupPreview {
        let plan = try cleanupPlan(now: now, calendar: calendar)
        return plan.preview
    }

    @discardableResult
    public func cleanupOldSnapshots(now: Date = .now, calendar: Calendar = .current) throws -> BackupCleanupPreview {
        let plan = try cleanupPlan(now: now, calendar: calendar)
        return try performCleanup(plan)
    }

    public func cleanupOldSnapshots(matching expectedPreview: BackupCleanupPreview, now: Date = .now, calendar: Calendar = .current) throws -> BackupCleanupPreview {
        let plan = try cleanupPlan(now: now, calendar: calendar)
        guard plan.preview == expectedPreview else { throw BackupDirectoryStoreError.cleanupPlanChanged }
        return try performCleanup(plan)
    }

    private func performCleanup(_ plan: (
        preview: BackupCleanupPreview,
        retainedSnapshots: [BackupSnapshot],
        canCollectOrphanedAssets: Bool
    )) throws -> BackupCleanupPreview {
        guard plan.preview.snapshotCount > 0 || plan.preview.orphanedPhotoCount > 0 else { return plan.preview }

        let snapshotsDirectory = backupDirectoryURL.appendingPathComponent("snapshots", isDirectory: true)
        for fileName in plan.preview.snapshotFileNames {
            try removeCoordinated(at: snapshotsDirectory.appendingPathComponent(fileName, isDirectory: false))
        }

        if plan.canCollectOrphanedAssets {
            let photosDirectory = backupDirectoryURL.appendingPathComponent("photos", isDirectory: true)
            let brandLogosDirectory = backupDirectoryURL.appendingPathComponent("brand-logos", isDirectory: true)
            let actualOrphanedPhotos = try orphanedAssetURLs(
                in: photosDirectory,
                retainingFileNames: Set(plan.retainedSnapshots.flatMap(\.photos).map(\.fileName))
            )
            let actualOrphanedLogos = try orphanedAssetURLs(
                in: brandLogosDirectory,
                retainingFileNames: Set(plan.retainedSnapshots.flatMap { $0.brandLogoAssets ?? [] }.map(\.fileName))
            )
            for url in actualOrphanedPhotos + actualOrphanedLogos {
                try removeCoordinated(at: url)
            }
        }
        return plan.preview
    }

    public func listSnapshots() throws -> [BackupSnapshotSummary] {
        guard FileManager.default.fileExists(atPath: backupDirectoryURL.path) else {
            return []
        }
        let markerURL = backupDirectoryURL.appendingPathComponent("library.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            return []
        }
        let libraryID = try readLibraryMarker()
        let snapshotsDirectory = backupDirectoryURL.appendingPathComponent("snapshots", isDirectory: true)
        guard FileManager.default.fileExists(atPath: snapshotsDirectory.path) else {
            return []
        }

        let files = try contentsOfDirectory(at: snapshotsDirectory)
            .filter { Self.isSnapshotName($0.lastPathComponent) }
        return files.compactMap { fileURL in
            guard let snapshot = try? Self.decode(readCoordinated(from: fileURL)),
                  snapshot.libraryID == libraryID else {
                return nil
            }
            return BackupSnapshotSummary(
                fileName: fileURL.lastPathComponent,
                createdAt: snapshot.createdAt,
                recordCount: snapshot.records.count,
                photoCount: snapshot.photos.count,
                brandLogoCount: (snapshot.brandLogoAssets ?? []).count,
                includesCatalog: snapshot.catalog != nil,
                brandCount: snapshot.catalog?.brands.count ?? 0,
                drinkCount: snapshot.catalog?.drinks.count ?? 0,
                nutritionEntryCount: snapshot.nutritionDataPack?.entries.count ?? 0
            )
        }
        .sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.fileName > $1.fileName
        }
    }

    public func loadSnapshot(named fileName: String) throws -> VerifiedBackupArchive {
        guard Self.isSnapshotName(fileName) else {
            throw BackupDirectoryStoreError.invalidSnapshotName
        }
        let libraryID = try readLibraryMarker()
        let snapshotURL = backupDirectoryURL
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            throw BackupDirectoryStoreError.snapshotNotFound
        }

        let snapshot = try Self.decode(readCoordinated(from: snapshotURL))
        guard snapshot.libraryID == libraryID else {
            throw BackupDirectoryStoreError.differentLibrary
        }

        let photosDirectory = backupDirectoryURL.appendingPathComponent("photos", isDirectory: true)
        var photoData: [UUID: Data] = [:]
        for asset in snapshot.photos {
            let photoURL = photosDirectory.appendingPathComponent(asset.fileName, isDirectory: false)
            guard FileManager.default.fileExists(atPath: photoURL.path) else {
                throw BackupDirectoryStoreError.photoIntegrityMismatch(asset.id)
            }
            let data = try readCoordinated(from: photoURL)
            guard data.count == asset.byteCount, Self.digest(data) == asset.sha256 else {
                throw BackupDirectoryStoreError.photoIntegrityMismatch(asset.id)
            }
            photoData[asset.id] = data
        }

        let brandLogosDirectory = backupDirectoryURL.appendingPathComponent("brand-logos", isDirectory: true)
        var brandLogoData: [UUID: Data] = [:]
        for asset in snapshot.brandLogoAssets ?? [] {
            let logoURL = brandLogosDirectory.appendingPathComponent(asset.fileName, isDirectory: false)
            guard FileManager.default.fileExists(atPath: logoURL.path) else {
                throw BackupDirectoryStoreError.brandLogoIntegrityMismatch(asset.id)
            }
            let data = try readCoordinated(from: logoURL)
            guard data.count == asset.byteCount, Self.digest(data) == asset.sha256 else {
                throw BackupDirectoryStoreError.brandLogoIntegrityMismatch(asset.id)
            }
            brandLogoData[asset.id] = data
        }

        return VerifiedBackupArchive(snapshot: snapshot, photoData: photoData, brandLogoData: brandLogoData)
    }

    private func validatePhotoData(_ photoData: [UUID: Data], for snapshot: BackupSnapshot) throws {
        let expectedIDs = Set(snapshot.photos.map(\.id))
        guard Set(photoData.keys) == expectedIDs else {
            let mismatchID = expectedIDs.symmetricDifference(Set(photoData.keys))
                .sorted { $0.uuidString < $1.uuidString }
                .first ?? UUID()
            throw BackupDirectoryStoreError.photoDataMismatch(mismatchID)
        }
        for asset in snapshot.photos {
            guard let data = photoData[asset.id], data.count == asset.byteCount, Self.digest(data) == asset.sha256 else {
                throw BackupDirectoryStoreError.photoDataMismatch(asset.id)
            }
        }
    }

    private func validateBrandLogoData(_ dataByID: [UUID: Data], for snapshot: BackupSnapshot) throws {
        let assets = snapshot.brandLogoAssets ?? []
        let expectedIDs = Set(assets.map(\.id))
        guard Set(dataByID.keys) == expectedIDs else {
            let mismatchID = expectedIDs.symmetricDifference(Set(dataByID.keys))
                .sorted { $0.uuidString < $1.uuidString }
                .first ?? UUID()
            throw BackupDirectoryStoreError.brandLogoDataMismatch(mismatchID)
        }
        for asset in assets {
            guard let data = dataByID[asset.id], data.count == asset.byteCount, Self.digest(data) == asset.sha256 else {
                throw BackupDirectoryStoreError.brandLogoDataMismatch(asset.id)
            }
        }
    }

    private func latestSnapshot(matching incoming: BackupSnapshot) throws -> (summary: BackupSnapshotSummary, snapshot: BackupSnapshot)? {
        guard incoming.libraryID == (try readLibraryMarker()) else {
            throw BackupDirectoryStoreError.differentLibrary
        }
        guard let latest = try listSnapshots().first else { return nil }
        let url = backupDirectoryURL
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(latest.fileName, isDirectory: false)
        guard let existing = try? Self.decode(readCoordinated(from: url)),
              existing.hasSameContent(as: incoming),
              try storedAssetsExistAndMatch(for: existing) else { return nil }
        return (latest, existing)
    }

    private func storedAssetsExistAndMatch(for snapshot: BackupSnapshot) throws -> Bool {
        let photosDirectory = backupDirectoryURL.appendingPathComponent("photos", isDirectory: true)
        let logosDirectory = backupDirectoryURL.appendingPathComponent("brand-logos", isDirectory: true)
        for (assets, directory) in [(snapshot.photos, photosDirectory), (snapshot.brandLogoAssets ?? [], logosDirectory)] {
            for asset in assets {
                let url = directory.appendingPathComponent(asset.fileName, isDirectory: false)
                guard FileManager.default.fileExists(atPath: url.path) else { return false }
                let data = try readCoordinated(from: url)
                guard data.count == asset.byteCount, Self.digest(data) == asset.sha256 else { return false }
            }
        }
        return true
    }

    private func cleanupPlan(now: Date, calendar: Calendar) throws -> (
        preview: BackupCleanupPreview,
        retainedSnapshots: [BackupSnapshot],
        canCollectOrphanedAssets: Bool
    ) {
        let libraryID = try readLibraryMarker()
        let snapshotsDirectory = backupDirectoryURL.appendingPathComponent("snapshots", isDirectory: true)
        guard FileManager.default.fileExists(atPath: snapshotsDirectory.path) else {
            return (BackupCleanupPreview(snapshotFileNames: [], snapshotBytes: 0, orphanedPhotoCount: 0, orphanedPhotoBytes: 0), [], true)
        }

        let files = try contentsOfDirectory(at: snapshotsDirectory).filter { Self.isSnapshotName($0.lastPathComponent) }
        var valid: [(url: URL, snapshot: BackupSnapshot)] = []
        var hasUnverifiedSnapshot = false
        for url in files {
            guard let snapshot = try? Self.decode(readCoordinated(from: url)), snapshot.libraryID == libraryID else {
                hasUnverifiedSnapshot = true
                continue
            }
            valid.append((url, snapshot))
        }
        valid.sort {
            if $0.snapshot.createdAt != $1.snapshot.createdAt { return $0.snapshot.createdAt > $1.snapshot.createdAt }
            return $0.url.lastPathComponent > $1.url.lastPathComponent
        }
        guard !hasUnverifiedSnapshot,
              let newest = valid.first,
              try storedAssetsExistAndMatch(for: newest.snapshot) else {
            throw BackupDirectoryStoreError.cleanupRequiresVerifiedSnapshot
        }

        var retained = Set(valid.prefix(10).map { $0.url.lastPathComponent })
        let recentCutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86_400)
        let monthlyCutoff = calendar.date(byAdding: .month, value: -12, to: now) ?? now.addingTimeInterval(-365 * 86_400)
        var keptDays = Set<Date>()
        var keptMonths = Set<Date>()
        for item in valid {
            let date = item.snapshot.createdAt
            if date >= recentCutoff, date <= now {
                let day = calendar.startOfDay(for: date)
                if keptDays.insert(day).inserted { retained.insert(item.url.lastPathComponent) }
            } else if date >= monthlyCutoff, date < recentCutoff {
                let components = calendar.dateComponents([.year, .month], from: date)
                if let month = calendar.date(from: components), keptMonths.insert(month).inserted {
                    retained.insert(item.url.lastPathComponent)
                }
            } else if date > now {
                retained.insert(item.url.lastPathComponent)
            }
        }

        let graceCutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86_400)
        let deletable = valid.filter {
            !retained.contains($0.url.lastPathComponent) && $0.snapshot.createdAt < graceCutoff
        }
        // Rebuild without the deletable names; malformed or foreign snapshots remain untouched.
        let deletableNames = Set(deletable.map { $0.url.lastPathComponent })
        let keptSnapshots = valid.filter { !deletableNames.contains($0.url.lastPathComponent) }.map(\.snapshot)
        let snapshotBytes = deletable.reduce(Int64(0)) { $0 + fileSize(at: $1.url) }

        var orphanedURLs: [URL] = []
        if !hasUnverifiedSnapshot {
            let retainedPhotoNames = Set(keptSnapshots.flatMap(\.photos).map(\.fileName))
            let retainedLogoNames = Set(keptSnapshots.flatMap { $0.brandLogoAssets ?? [] }.map(\.fileName))
            orphanedURLs += try orphanedAssetURLs(
                in: backupDirectoryURL.appendingPathComponent("photos", isDirectory: true),
                retainingFileNames: retainedPhotoNames
            )
            orphanedURLs += try orphanedAssetURLs(
                in: backupDirectoryURL.appendingPathComponent("brand-logos", isDirectory: true),
                retainingFileNames: retainedLogoNames
            )
        }
        let preview = BackupCleanupPreview(
            snapshotFileNames: deletable.map { $0.url.lastPathComponent },
            snapshotBytes: snapshotBytes,
            orphanedPhotoCount: orphanedURLs.count,
            orphanedPhotoBytes: orphanedURLs.reduce(Int64(0)) { $0 + fileSize(at: $1) }
        )
        return (preview, keptSnapshots, !hasUnverifiedSnapshot)
    }

    private func orphanedAssetURLs(in directory: URL, retainingFileNames: Set<String>) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try contentsOfDirectory(at: directory).filter { url in
            let name = url.lastPathComponent
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                  !url.pathExtension.isEmpty,
                  name == "\(url.deletingPathExtension().lastPathComponent).\(url.pathExtension.lowercased())" else { return false }
            return !retainingFileNames.contains(name)
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func removeCoordinated(at url: URL) throws {
        #if os(iOS)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(writingItemAt: url, options: [.forDeleting], error: &coordinationError) { coordinatedURL in
            do {
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    try FileManager.default.removeItem(at: coordinatedURL)
                }
            } catch {
                operationError = error
            }
        }
        if let coordinationError {
            throw BackupDirectoryStoreError.coordinatedReadFailed(coordinationError.localizedDescription)
        }
        if let operationError { throw operationError }
        #else
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        #endif
    }

    private func prepareLibraryDirectory(for libraryID: UUID) throws {
        guard userSelectedFolderURL.isFileURL, isDirectory(userSelectedFolderURL) else {
            throw BackupDirectoryStoreError.selectedFolderUnavailable
        }

        if FileManager.default.fileExists(atPath: backupDirectoryURL.path) {
            guard isDirectory(backupDirectoryURL) else {
                throw BackupDirectoryStoreError.selectedFolderUnavailable
            }
        } else {
            try createDirectoryIfNeeded(at: backupDirectoryURL)
        }

        let markerURL = backupDirectoryURL.appendingPathComponent("library.json", isDirectory: false)
        if FileManager.default.fileExists(atPath: markerURL.path) {
            let marker = try Self.decodeMarker(readCoordinated(from: markerURL))
            guard marker.libraryID == libraryID else {
                throw BackupDirectoryStoreError.differentLibrary
            }
            return
        }

        let existingItems = try contentsOfDirectory(at: backupDirectoryURL)
        guard existingItems.isEmpty else {
            throw BackupDirectoryStoreError.unrecognizedExistingData
        }

        let marker = LibraryMarker(formatVersion: BackupSnapshot.currentFormatVersion, libraryID: libraryID)
        _ = try LocalFolderProbe.writeAndVerify(Self.encodeMarker(marker), fileName: "library.json", in: backupDirectoryURL)
    }

    private func readLibraryMarker() throws -> UUID {
        let markerURL = backupDirectoryURL.appendingPathComponent("library.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            throw BackupDirectoryStoreError.invalidLibraryMarker
        }
        return try Self.decodeMarker(readCoordinated(from: markerURL)).libraryID
    }

    private func writeOrReusePhoto(_ data: Data, asset: PhotoAsset, in directory: URL) throws {
        let destination = directory.appendingPathComponent(asset.fileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: destination.path) {
            let saved = try readCoordinated(from: destination)
            guard saved.count == asset.byteCount, Self.digest(saved) == asset.sha256 else {
                throw BackupDirectoryStoreError.photoIntegrityMismatch(asset.id)
            }
            return
        }
        _ = try LocalFolderProbe.writeAndVerify(data, fileName: asset.fileName, in: directory)
    }

    private func writeOrReuseBrandLogo(_ data: Data, asset: PhotoAsset, in directory: URL) throws {
        let destination = directory.appendingPathComponent(asset.fileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: destination.path) {
            let saved = try readCoordinated(from: destination)
            guard saved.count == asset.byteCount, Self.digest(saved) == asset.sha256 else {
                throw BackupDirectoryStoreError.brandLogoIntegrityMismatch(asset.id)
            }
            return
        }
        _ = try LocalFolderProbe.writeAndVerify(data, fileName: asset.fileName, in: directory)
    }

    private func createDirectoryIfNeeded(at directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            guard isDirectory(directory) else {
                throw BackupDirectoryStoreError.selectedFolderUnavailable
            }
            return
        }

        #if os(iOS)
        let parent = directory.deletingLastPathComponent()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(writingItemAt: parent, options: [.forMerging], error: &coordinationError) { coordinatedParent in
            let destination = coordinatedParent.appendingPathComponent(directory.lastPathComponent, isDirectory: true)
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    guard isDirectory(destination) else {
                        throw BackupDirectoryStoreError.selectedFolderUnavailable
                    }
                } else {
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                }
            } catch {
                operationError = error
            }
        }
        if let coordinationError {
            throw BackupDirectoryStoreError.coordinatedReadFailed(coordinationError.localizedDescription)
        }
        if let operationError { throw operationError }
        #else
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        #endif
    }

    private func contentsOfDirectory(at directory: URL) throws -> [URL] {
        #if os(iOS)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        var result: [URL] = []
        coordinator.coordinate(readingItemAt: directory, options: [], error: &coordinationError) { coordinatedDirectory in
            do {
                result = try FileManager.default.contentsOfDirectory(
                    at: coordinatedDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                operationError = error
            }
        }
        if let coordinationError {
            throw BackupDirectoryStoreError.coordinatedReadFailed(coordinationError.localizedDescription)
        }
        if let operationError { throw operationError }
        return result
        #else
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        #endif
    }

    private func readCoordinated(from url: URL) throws -> Data {
        #if os(iOS)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        var result: Data?
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { coordinatedURL in
            do {
                result = try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
            } catch {
                operationError = error
            }
        }
        if let coordinationError {
            throw BackupDirectoryStoreError.coordinatedReadFailed(coordinationError.localizedDescription)
        }
        if let operationError { throw operationError }
        guard let result else {
            throw BackupDirectoryStoreError.coordinatedReadFailed("协调读取未返回文件内容。")
        }
        return result
        #else
        return try Data(contentsOf: url, options: [.mappedIfSafe])
        #endif
    }

    private static func encode(_ snapshot: BackupSnapshot) throws -> Data {
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    private static func decode(_ data: Data) throws -> BackupSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(BackupSnapshot.self, from: data)
        try snapshot.validate()
        return snapshot
    }

    private static func encodeMarker(_ marker: LibraryMarker) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(marker)
    }

    private static func decodeMarker(_ data: Data) throws -> LibraryMarker {
        let marker: LibraryMarker
        do {
            marker = try JSONDecoder().decode(LibraryMarker.self, from: data)
        } catch {
            throw BackupDirectoryStoreError.invalidLibraryMarker
        }
        guard marker.formatVersion == BackupSnapshot.currentFormatVersion else {
            throw BackupDirectoryStoreError.unsupportedLibraryVersion(marker.formatVersion)
        }
        return marker
    }

    private static func isSnapshotName(_ fileName: String) -> Bool {
        fileName.range(
            of: #"^snapshot-[0-9A-Fa-f-]{36}\.json$"#,
            options: .regularExpression
        ) != nil
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private struct LibraryMarker: Codable, Sendable {
    let formatVersion: Int
    let libraryID: UUID
}
