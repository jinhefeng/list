import Foundation
import SwiftData

public enum StoredJournalRecordError: Error, Equatable {
    case invalidRecordIdentifier
    case recordTypeMismatch
    case unsupportedPayloadVersion(Int)
}

public struct StoredJournalRecordSnapshot: Sendable {
    public let recordID: String
    public let recordType: String
    public let payloadVersion: Int
    public let payload: Data

    public func decodeRecord() throws -> JournalRecord {
        guard payloadVersion == 1 else {
            throw StoredJournalRecordError.unsupportedPayloadVersion(payloadVersion)
        }
        guard UUID(uuidString: recordID) != nil else {
            throw StoredJournalRecordError.invalidRecordIdentifier
        }

        let record = try JournalRecordCodec.decode(payload)
        guard record.id.uuidString == recordID else {
            throw StoredJournalRecordError.invalidRecordIdentifier
        }
        guard Self.typeName(for: record) == recordType else {
            throw StoredJournalRecordError.recordTypeMismatch
        }
        return record
    }

    private static func typeName(for record: JournalRecord) -> String {
        switch record {
        case .drink: "drink"
        case .meal: "meal"
        }
    }
}

@Model
public final class StoredJournalRecord {
    @Attribute(.unique) public var recordID: String
    public var recordType: String
    public var consumedAt: Date
    public var payloadVersion: Int
    public var payload: Data
    public var needsBackup: Bool

    public init(record: JournalRecord, needsBackup: Bool = true) throws {
        let encoded = try JournalRecordCodec.encode(record)
        self.recordID = record.id.uuidString
        self.recordType = Self.typeName(for: record)
        self.consumedAt = record.consumedAt
        self.payloadVersion = 1
        self.payload = encoded
        self.needsBackup = needsBackup
    }

    public func decodeRecord() throws -> JournalRecord {
        try decodingSnapshot().decodeRecord()
    }

    public func decodingSnapshot() -> StoredJournalRecordSnapshot {
        StoredJournalRecordSnapshot(
            recordID: recordID,
            recordType: recordType,
            payloadVersion: payloadVersion,
            payload: payload
        )
    }

    public func replace(with record: JournalRecord) throws {
        guard record.id.uuidString == recordID else {
            throw StoredJournalRecordError.invalidRecordIdentifier
        }

        let encoded = try JournalRecordCodec.encode(record)
        payload = encoded
        recordType = Self.typeName(for: record)
        consumedAt = record.consumedAt
        needsBackup = true
    }

    private static func typeName(for record: JournalRecord) -> String {
        switch record {
        case .drink: "drink"
        case .meal: "meal"
        }
    }
}
