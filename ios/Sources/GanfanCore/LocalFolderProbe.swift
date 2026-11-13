import CryptoKit
import Foundation

public struct LocalFolderProbeResult: Sendable, Equatable {
    public let fileName: String
    public let byteCount: Int
    public let sha256: String

    public init(fileName: String, byteCount: Int, sha256: String) {
        self.fileName = fileName
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public enum LocalFolderProbeError: Error, Equatable {
    case invalidFileName
    case emptyContents
    case directoryUnavailable
    case fileAlreadyExists
    case coordinationFailed(String)
    case verificationFailed
}

public enum LocalFolderProbe {
    public static func writeAndVerify(_ data: Data, fileName: String, in folder: URL) throws -> LocalFolderProbeResult {
        guard isSafeFileName(fileName) else {
            throw LocalFolderProbeError.invalidFileName
        }

        guard !data.isEmpty else {
            throw LocalFolderProbeError.emptyContents
        }

        guard folder.isFileURL, isExistingDirectory(folder) else {
            throw LocalFolderProbeError.directoryUnavailable
        }

        #if os(iOS)
        return try writeWithCoordination(data, fileName: fileName, in: folder)
        #else
        return try writeWithoutCoordination(data, fileName: fileName, in: folder)
        #endif
    }

    #if os(iOS)
    private static func writeWithCoordination(_ data: Data, fileName: String, in folder: URL) throws -> LocalFolderProbeResult {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        var result: LocalFolderProbeResult?

        coordinator.coordinate(writingItemAt: folder, options: [], error: &coordinationError) { coordinatedFolder in
            do {
                result = try writeWithoutCoordination(data, fileName: fileName, in: coordinatedFolder)
            } catch {
                operationError = error
            }
        }

        if let coordinationError {
            throw LocalFolderProbeError.coordinationFailed(coordinationError.localizedDescription)
        }

        if let operationError {
            throw operationError
        }

        guard let result else {
            throw LocalFolderProbeError.verificationFailed
        }

        return result
    }
    #endif

    private static func writeWithoutCoordination(_ data: Data, fileName: String, in folder: URL) throws -> LocalFolderProbeResult {
        let destination = folder.appendingPathComponent(fileName, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw LocalFolderProbeError.fileAlreadyExists
        }

        let temporaryFile = folder.appendingPathComponent(".ganfan-\(UUID().uuidString).tmp", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: temporaryFile) }

        do {
            try data.write(to: temporaryFile, options: .atomic)
            let stagedData = try Data(contentsOf: temporaryFile, options: [.mappedIfSafe])
            guard stagedData == data else {
                throw LocalFolderProbeError.verificationFailed
            }

            try FileManager.default.moveItem(at: temporaryFile, to: destination)
        } catch {
            if error as? LocalFolderProbeError == .verificationFailed {
                throw error
            }
            if isFileExistsError(error) {
                throw LocalFolderProbeError.fileAlreadyExists
            }
            throw error
        }

        let savedData = try Data(contentsOf: destination, options: [.mappedIfSafe])
        guard savedData == data else {
            throw LocalFolderProbeError.verificationFailed
        }

        let digest = SHA256.hash(data: savedData)
            .map { String(format: "%02x", $0) }
            .joined()

        return LocalFolderProbeResult(fileName: fileName, byteCount: savedData.count, sha256: digest)
    }

    private static func isSafeFileName(_ fileName: String) -> Bool {
        guard !fileName.isEmpty, fileName != ".", fileName != ".." else {
            return false
        }

        guard !fileName.contains("/"), !fileName.contains("\\") else {
            return false
        }

        return !fileName.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func isFileExistsError(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        return cocoaError.domain == NSCocoaErrorDomain
            && cocoaError.code == CocoaError.fileWriteFileExists.rawValue
    }
}
