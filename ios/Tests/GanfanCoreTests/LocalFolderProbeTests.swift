import CryptoKit
import Foundation
import XCTest
@testable import GanfanCore

final class LocalFolderProbeTests: XCTestCase {
    func testWritesAndVerifiesTheExactBytes() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let photoBytes = Data("prototype photo bytes".utf8)
        let result = try LocalFolderProbe.writeAndVerify(
            photoBytes,
            fileName: "drink-photo.jpg",
            in: folder
        )

        XCTAssertEqual(result.fileName, "drink-photo.jpg")
        XCTAssertEqual(result.byteCount, photoBytes.count)
        XCTAssertEqual(result.sha256, SHA256.hash(data: photoBytes).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(result.fileName)), photoBytes)
    }

    func testRejectsAnEmptyFileName() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertThrowsError(try LocalFolderProbe.writeAndVerify(Data([1]), fileName: "", in: folder)) { error in
            XCTAssertEqual(error as? LocalFolderProbeError, .invalidFileName)
        }
    }

    func testRejectsPathTraversalAndNestedPaths() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        for fileName in ["../outside.jpg", "folder/photo.jpg", "folder\\photo.jpg", ".", ".."] {
            XCTAssertThrowsError(try LocalFolderProbe.writeAndVerify(Data([1]), fileName: fileName, in: folder)) { error in
                XCTAssertEqual(error as? LocalFolderProbeError, .invalidFileName, fileName)
            }
        }
    }

    func testRefusesToReplaceAnExistingFile() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("existing.jpg")
        let originalBytes = Data("keep this file".utf8)
        try originalBytes.write(to: destination)

        XCTAssertThrowsError(try LocalFolderProbe.writeAndVerify(Data("new contents".utf8), fileName: "existing.jpg", in: folder)) { error in
            XCTAssertEqual(error as? LocalFolderProbeError, .fileAlreadyExists)
        }
        XCTAssertEqual(try Data(contentsOf: destination), originalBytes)
    }

    func testRejectsEmptyPhotoData() throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertThrowsError(try LocalFolderProbe.writeAndVerify(Data(), fileName: "empty.jpg", in: folder)) { error in
            XCTAssertEqual(error as? LocalFolderProbeError, .emptyContents)
        }
    }

    func testDoesNotCreateAMissingDestinationDirectory() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let missingFolder = parent.appendingPathComponent("not-created", isDirectory: true)

        XCTAssertThrowsError(try LocalFolderProbe.writeAndVerify(Data([1]), fileName: "photo.jpg", in: missingFolder)) { error in
            XCTAssertEqual(error as? LocalFolderProbeError, .directoryUnavailable)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingFolder.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GanfanCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
