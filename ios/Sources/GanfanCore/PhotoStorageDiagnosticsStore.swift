import Foundation

public enum PhotoStorageFailureStage: String, Codable, CaseIterable, Sendable {
    case photoSelection
    case photoWrite
    case thumbnailWrite
    case photoRead
}

public enum PhotoStorageFailureReason: String, Codable, CaseIterable, Sendable {
    case permissionDenied
    case diskFull
    case integrityMismatch
    case unsupportedFormat
    case unknown
}

public struct PhotoStorageFailureEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let occurredAt: Date
    public let stage: PhotoStorageFailureStage
    public let reason: PhotoStorageFailureReason
    public let byteCount: Int?

    public init(
        id: UUID = UUID(),
        occurredAt: Date = .now,
        stage: PhotoStorageFailureStage,
        reason: PhotoStorageFailureReason,
        byteCount: Int? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.stage = stage
        self.reason = reason
        self.byteCount = byteCount.flatMap { $0 >= 0 ? $0 : nil }
    }
}

/// Stores only coarse event metadata; never accepts paths, photo bytes, record text, or raw errors.
public final class PhotoStorageDiagnosticsStore {
    public static let maximumEvents = 20
    private static let storageKey = "ganfan-handbook.photo-storage-failures.v1"
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var recentEvents: [PhotoStorageFailureEvent] {
        guard let data = userDefaults.data(forKey: Self.storageKey),
              let events = try? JSONDecoder().decode([PhotoStorageFailureEvent].self, from: data) else { return [] }
        return events.sorted { $0.occurredAt > $1.occurredAt }.prefix(Self.maximumEvents).map { $0 }
    }

    public func record(
        stage: PhotoStorageFailureStage,
        reason: PhotoStorageFailureReason,
        byteCount: Int? = nil,
        occurredAt: Date = .now
    ) {
        let event = PhotoStorageFailureEvent(
            occurredAt: occurredAt,
            stage: stage,
            reason: reason,
            byteCount: byteCount
        )
        let events = ([event] + recentEvents).prefix(Self.maximumEvents)
        guard let data = try? JSONEncoder().encode(Array(events)) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    public static func reason(for error: Error) -> PhotoStorageFailureReason {
        if let error = error as? LocalPhotoStoreError {
            return switch error {
            case .integrityMismatch: .integrityMismatch
            case .invalidFileExtension, .invalidAsset: .unsupportedFormat
            }
        } else {
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain,
               cocoaError.code == CocoaError.Code.fileWriteOutOfSpace.rawValue {
                return .diskFull
            }
            if cocoaError.domain == NSCocoaErrorDomain,
               cocoaError.code == CocoaError.Code.fileReadNoPermission.rawValue {
                return .permissionDenied
            }
            return .unknown
        }
    }
}
