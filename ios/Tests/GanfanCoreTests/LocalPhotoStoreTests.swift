import CryptoKit
import Foundation
import XCTest
@testable import GanfanCore

final class LocalPhotoStoreTests: XCTestCase {
    func testSavesAndReadsOriginalBytesWithMetadata() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalPhotoStore(directoryURL: directory.appendingPathComponent("Photos", isDirectory: true))
        let bytes = Data("original photo bytes".utf8)

        let asset = try store.save(bytes, fileExtension: "JPG")

        XCTAssertEqual(asset.byteCount, bytes.count)
        XCTAssertEqual(asset.fileExtension, "jpg")
        XCTAssertEqual(asset.sha256, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(try store.load(asset), bytes)
    }

    func testRejectsTamperedPhotoBytes() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalPhotoStore(directoryURL: directory.appendingPathComponent("Photos", isDirectory: true))
        let asset = try store.save(Data("original".utf8), fileExtension: "png")
        try Data("changed!".utf8).write(to: store.directoryURL.appendingPathComponent(asset.fileName))

        XCTAssertThrowsError(try store.load(asset)) { error in
            XCTAssertEqual(error as? LocalPhotoStoreError, .integrityMismatch)
        }
    }

    func testRejectsUnsafeExtension() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalPhotoStore(directoryURL: directory.appendingPathComponent("Photos", isDirectory: true))

        XCTAssertThrowsError(try store.save(Data([1]), fileExtension: "../outside")) { error in
            XCTAssertEqual(error as? LocalPhotoStoreError, .invalidFileExtension)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directoryURL.path))
    }

    func testImportsVerifiedBytesUsingTheOriginalStableIdentifier() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = LocalPhotoStore(directoryURL: directory.appendingPathComponent("source"))
        let destination = LocalPhotoStore(directoryURL: directory.appendingPathComponent("destination"))
        let bytes = Data("original".utf8)
        let asset = try source.save(bytes, fileExtension: "png")

        XCTAssertTrue(try destination.importVerified(bytes, as: asset))
        XCTAssertFalse(try destination.importVerified(bytes, as: asset))
        XCTAssertEqual(try destination.load(asset), bytes)
    }

    func testRefusesToOverwriteDifferentBytesDuringImport() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = LocalPhotoStore(directoryURL: directory.appendingPathComponent("source"))
        let destination = LocalPhotoStore(directoryURL: directory.appendingPathComponent("destination"))
        let bytes = Data("original".utf8)
        let asset = try source.save(bytes, fileExtension: "jpg")
        _ = try destination.importVerified(bytes, as: asset)
        try Data("changed".utf8).write(to: destination.directoryURL.appendingPathComponent(asset.fileName))

        XCTAssertThrowsError(try destination.importVerified(bytes, as: asset)) { error in
            XCTAssertEqual(error as? LocalPhotoStoreError, .integrityMismatch)
        }
        XCTAssertEqual(try Data(contentsOf: destination.directoryURL.appendingPathComponent(asset.fileName)), Data("changed".utf8))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GanfanPhotoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
