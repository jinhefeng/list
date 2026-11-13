import CryptoKit
import Foundation

public enum BackupSnapshotError: Error, Equatable {
    case unsupportedFormatVersion(Int)
    case invalidCreationTime
    case duplicateRecordIdentifier(UUID)
    case conflictingPhotoAsset(UUID)
    case invalidPhotoManifest
}

public struct BackupSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let libraryID: UUID
    public let createdAt: Date
    public let records: [JournalRecord]
    public let photos: [PhotoAsset]
    public let catalogState: MenuCatalogUserState?

    public init(
        libraryID: UUID,
        records: [JournalRecord],
        catalogState: MenuCatalogUserState? = nil,
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

        for asset in photos {
            try asset.validate()
        }
        let manifest = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard manifest.count == photos.count, manifest == referencedPhotos else {
            throw BackupSnapshotError.invalidPhotoManifest
        }
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
    case coordinatedReadFailed(String)
}

public struct BackupWriteResult: Equatable, Sendable {
    public let fileName: String
    public let createdAt: Date
    public let recordCount: Int
    public let photoCount: Int
}

public struct BackupSnapshotSummary: Equatable, Identifiable, Sendable {
    public let fileName: String
    public let createdAt: Date
    public let recordCount: Int
    public let photoCount: Int

    public var id: String { fileName }
}

public struct VerifiedBackupArchive: Equatable, Sendable {
    public let snapshot: BackupSnapshot
    public let photoData: [UUID: Data]
}

public struct BackupDirectoryStore: Sendable {
    public let userSelectedFolderURL: URL

    public init(userSelectedFolderURL: URL) {
        self.userSelectedFolderURL = userSelectedFolderURL
    }

    public var backupDirectoryURL: URL {
        userSelectedFolderURL.appendingPathComponent("干饭手册", isDirectory: true)
    }

    public func write(snapshot: BackupSnapshot, photoData: [UUID: Data]) throws -> BackupWriteResult {
        try snapshot.validate()
        try validatePhotoData(photoData, for: snapshot)
        try prepareLibraryDirectory(for: snapshot.libraryID)

        let photosDirectory = backupDirectoryURL.appendingPathComponent("photos", isDirectory: true)
        let snapshotsDirectory = backupDirectoryURL.appendingPathComponent("snapshots", isDirectory: true)
        try createDirectoryIfNeeded(at: photosDirectory)
        try createDirectoryIfNeeded(at: snapshotsDirectory)

        for asset in snapshot.photos {
            guard let data = photoData[asset.id] else {
                throw BackupDirectoryStoreError.photoDataMismatch(asset.id)
            }
            try writeOrReusePhoto(data, asset: asset, in: photosDirectory)
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
            photoCount: savedSnapshot.photos.count
        )
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
                photoCount: snapshot.photos.count
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

        return VerifiedBackupArchive(snapshot: snapshot, photoData: photoData)
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
