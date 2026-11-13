import CryptoKit
import Foundation

public enum LocalPhotoStoreError: Error, Equatable {
    case invalidFileExtension
    case invalidAsset
    case integrityMismatch
}

public struct LocalPhotoStore: Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func save(_ data: Data, fileExtension: String) throws -> PhotoAsset {
        let normalizedExtension = fileExtension.lowercased()
        guard normalizedExtension.range(of: #"^[a-z0-9]{1,10}$"#, options: .regularExpression) != nil else {
            throw LocalPhotoStoreError.invalidFileExtension
        }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let id = UUID()
        let fileName = "\(id.uuidString).\(normalizedExtension)"
        let result = try LocalFolderProbe.writeAndVerify(data, fileName: fileName, in: directoryURL)

        return try PhotoAsset(
            id: id,
            fileName: fileName,
            fileExtension: normalizedExtension,
            byteCount: result.byteCount,
            sha256: result.sha256
        )
    }

    public func load(_ asset: PhotoAsset) throws -> Data {
        guard PhotoAsset.isSafeFileName(
            asset.fileName,
            id: asset.id,
            fileExtension: asset.fileExtension
        ) else {
            throw LocalPhotoStoreError.invalidAsset
        }

        let fileURL = directoryURL.appendingPathComponent(asset.fileName, isDirectory: false)
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard data.count == asset.byteCount, Self.digest(data) == asset.sha256 else {
            throw LocalPhotoStoreError.integrityMismatch
        }
        return data
    }

    /// Copies a verified backup image into the local store using its stable identity.
    /// Returns `true` only when this call created a new local file.
    @discardableResult
    public func importVerified(_ data: Data, as asset: PhotoAsset) throws -> Bool {
        do {
            try asset.validate()
        } catch {
            throw LocalPhotoStoreError.invalidAsset
        }

        guard data.count == asset.byteCount, Self.digest(data) == asset.sha256 else {
            throw LocalPhotoStoreError.integrityMismatch
        }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let destination = directoryURL.appendingPathComponent(asset.fileName, isDirectory: false)

        if FileManager.default.fileExists(atPath: destination.path) {
            guard try load(asset) == data else {
                throw LocalPhotoStoreError.integrityMismatch
            }
            return false
        }

        _ = try LocalFolderProbe.writeAndVerify(data, fileName: asset.fileName, in: directoryURL)
        return true
    }

    public func remove(_ asset: PhotoAsset) throws {
        guard PhotoAsset.isSafeFileName(
            asset.fileName,
            id: asset.id,
            fileExtension: asset.fileExtension
        ) else {
            throw LocalPhotoStoreError.invalidAsset
        }
        try FileManager.default.removeItem(at: directoryURL.appendingPathComponent(asset.fileName))
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
