import Foundation
import SQLite3
import SwiftData

public struct JournalLibraryEntry: Equatable, Sendable, Identifiable {
    public let record: JournalRecord
    public let needsBackup: Bool

    public var id: UUID { record.id }

    public init(record: JournalRecord, needsBackup: Bool) {
        self.record = record
        self.needsBackup = needsBackup
    }
}

public struct JournalHistoryCursor: Equatable, Sendable {
    public let localDay: String
    public let consumedAt: Double
    public let recordID: String

    public init(localDay: String, consumedAt: Double, recordID: String) {
        self.localDay = localDay
        self.consumedAt = consumedAt
        self.recordID = recordID
    }
}

public struct JournalHistoryQuery: Sendable {
    public var startDate: Date?
    public var endDate: Date?
    public var recordTypes: Set<String>
    public var searchText: String

    public init(
        startDate: Date? = nil,
        endDate: Date? = nil,
        recordTypes: Set<String> = ["drink", "meal"],
        searchText: String = ""
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.recordTypes = recordTypes
        self.searchText = searchText
    }
}

public struct JournalHistoryPage: Sendable {
    public let items: [JournalLibraryEntry]
    public let nextCursor: JournalHistoryCursor?
    public let hasMore: Bool
}

public struct JournalLegacyRecordIssue: Sendable, Identifiable {
    public let id: String
    public let recordType: String
    public let consumedAt: Date
}

public enum JournalSQLiteStoreError: Error, LocalizedError, Equatable {
    case cannotOpen(String)
    case sqliteFailure(String)
    case invalidRecord(UUID)
    case recordNotFound(UUID)
    case unsupportedSchema(Int)
    case backupFailed(String)
    case migrationCountMismatch

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let reason): "无法打开本机资料库：\(reason)"
        case .sqliteFailure(let reason): "本机资料库操作失败：\(reason)"
        case .invalidRecord(let id): "记录 \(id.uuidString) 无法写入结构化资料库。"
        case .recordNotFound(let id): "找不到记录 \(id.uuidString)。"
        case .unsupportedSchema(let version): "资料库版本 \(version) 暂不支持。"
        case .backupFailed(let reason): "无法生成 SQLite 备份：\(reason)"
        case .migrationCountMismatch: "旧资料库迁移前后记录数量不一致。"
        }
    }
}

public enum JournalDatabasePaths {
    public static func libraryURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("GanfanHandbook", isDirectory: true)
            .appendingPathComponent("Journal", isDirectory: true)
            .appendingPathComponent("library.sqlite", isDirectory: false)
    }
}

/// An app-owned, typed SQLite library. The old SwiftData store is read only during migration.
public final class JournalSQLiteStore: @unchecked Sendable {
    public static let schemaVersion = 1
    public let url: URL

    private let lock = NSRecursiveLock()
    private var database: OpaquePointer?

    public init(url: URL, readOnly: Bool = false) throws {
        self.url = url
        if !readOnly {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        var handle: OpaquePointer?
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(
            url.path,
            &handle,
            flags,
            nil
        )
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite 打开失败（\(result)）"
            if let handle { sqlite3_close(handle) }
            throw JournalSQLiteStoreError.cannotOpen(message)
        }
        database = handle
        do {
            if readOnly {
                let version = try scalarInt("PRAGMA user_version")
                guard version == Self.schemaVersion else { throw JournalSQLiteStoreError.unsupportedSchema(version) }
                return
            }
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = FULL")
            let version = try scalarInt("PRAGMA user_version")
            guard version == 0 || version == Self.schemaVersion else {
                throw JournalSQLiteStoreError.unsupportedSchema(version)
            }
            try createSchema()
            if version == 0 { try execute("PRAGMA user_version = \(Self.schemaVersion)") }
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        guard let database else { return }
        sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
        sqlite3_close(database)
        self.database = nil
    }

    public func closeForFileMove() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let database else { return }
        var logFrames: Int32 = 0
        var checkpointedFrames: Int32 = 0
        let checkpoint = sqlite3_wal_checkpoint_v2(
            database,
            nil,
            SQLITE_CHECKPOINT_TRUNCATE,
            &logFrames,
            &checkpointedFrames
        )
        guard checkpoint == SQLITE_OK, logFrames < 0 || checkpointedFrames == logFrames else {
            throw JournalSQLiteStoreError.sqliteFailure("无法安全整理迁移中的 SQLite 文件。")
        }
        guard sqlite3_exec(database, "PRAGMA journal_mode = DELETE", nil, nil, nil) == SQLITE_OK else {
            throw JournalSQLiteStoreError.sqliteFailure(String(cString: sqlite3_errmsg(database)))
        }
        guard sqlite3_close(database) == SQLITE_OK else {
            throw JournalSQLiteStoreError.sqliteFailure(String(cString: sqlite3_errmsg(database)))
        }
        self.database = nil
    }

    public var migrationComplete: Bool {
        (try? scalarText("SELECT value FROM library_metadata WHERE key = 'migration_complete'")) == "1"
    }

    public var dataGeneration: Int {
        (try? scalarInt("SELECT value FROM library_metadata WHERE key = 'data_generation'")) ?? 0
    }

    public func markMigrationComplete() throws {
        try execute("INSERT OR REPLACE INTO library_metadata(key,value) VALUES('migration_complete','1')")
        try execute("INSERT OR REPLACE INTO library_metadata(key,value) VALUES('schema_version','\(Self.schemaVersion)')")
    }

    public func save(_ record: JournalRecord, needsBackup: Bool = true) throws {
        try record.validate()
        try transaction { database in
            try Self.insert(record, needsBackup: needsBackup, in: database)
            try Self.incrementDataGeneration(in: database)
        }
    }

    /// Imports a JSON snapshot's records into an empty library as one transaction.
    public func restoreRecords(_ records: [JournalRecord]) throws {
        var identifiers = Set<UUID>()
        for record in records {
            try record.validate()
            guard identifiers.insert(record.id).inserted else {
                throw JournalLibraryRestoreError.duplicateRecordIdentifier(record.id)
            }
        }
        try transaction { database in
            let existingCount = try Self.scalarInt("SELECT COUNT(*) FROM journal_records", in: database)
                + Self.scalarInt("SELECT COUNT(*) FROM legacy_records", in: database)
            guard existingCount == 0 else { throw JournalLibraryRestoreError.libraryNotEmpty }
            for record in records { try Self.insert(record, needsBackup: false, in: database) }
            if !records.isEmpty { try Self.incrementDataGeneration(in: database) }
        }
    }

    public func delete(_ id: UUID) throws {
        try transaction { database in
            try Self.execute(
                "DELETE FROM nutrition_metric_sources WHERE owner_kind = 'record' AND owner_id = ?",
                values: [.text(id.uuidString)],
                in: database
            )
            try Self.execute(
                "DELETE FROM nutrition_metric_sources WHERE owner_kind = 'dish' AND owner_id IN (SELECT id FROM meal_dishes WHERE record_id = ?)",
                values: [.text(id.uuidString)],
                in: database
            )
            try Self.execute("DELETE FROM journal_records WHERE id = ?", values: [.text(id.uuidString)], in: database)
            if try Self.scalarInt("SELECT changes()", in: database) > 0 {
                try Self.incrementDataGeneration(in: database)
            }
        }
    }

    public func record(id: UUID) throws -> JournalLibraryEntry? {
        try withDatabase { database in
            guard let row = try Self.queryRecordRow(
                "SELECT id, kind, consumed_at, needs_backup FROM journal_records WHERE id = ?",
                values: [.text(id.uuidString)],
                in: database
            ).first else { return nil }
            return try Self.decodeEntry(row, in: database)
        }
    }

    public func count() throws -> Int { try scalarInt("SELECT COUNT(*) FROM journal_records") }

    public func pendingBackupCount() throws -> Int {
        try scalarInt("SELECT (SELECT COUNT(*) FROM journal_records WHERE needs_backup = 1) + (SELECT COUNT(*) FROM legacy_records WHERE needs_backup = 1)")
    }

    public func markBackedUp(recordIDs: [UUID]) throws {
        guard !recordIDs.isEmpty else { return }
        try transaction { database in
            for id in recordIDs {
                try Self.execute(
                    "UPDATE journal_records SET needs_backup = 0 WHERE id = ?",
                    values: [.text(id.uuidString)],
                    in: database
                )
            }
        }
    }

    public func markAllBackedUp() throws {
        try execute("UPDATE journal_records SET needs_backup = 0")
        try execute("UPDATE legacy_records SET needs_backup = 0")
    }

    /// Clears backup flags only when the data used to build the snapshot is still current.
    public func markAllBackedUp(ifDataGenerationMatches expectedGeneration: Int) throws -> Bool {
        try transaction { database in
            let currentGeneration = try Self.scalarInt(
                "SELECT value FROM library_metadata WHERE key = 'data_generation'",
                in: database
            )
            guard currentGeneration == expectedGeneration else { return false }
            try Self.execute("UPDATE journal_records SET needs_backup = 0", in: database)
            try Self.execute("UPDATE legacy_records SET needs_backup = 0", in: database)
            return true
        }
    }

    public func allRecords() throws -> [JournalLibraryEntry] {
        try withDatabase { database in
            let rows = try Self.queryRecordRow(
                "SELECT id, kind, consumed_at, needs_backup FROM journal_records ORDER BY consumed_at, id",
                values: [],
                in: database
            )
            return try rows.map { try Self.decodeEntry($0, in: database) }
        }
    }

    public func records(from start: Date, to endExclusive: Date) throws -> [JournalRecord] {
        try withDatabase { database in
            let rows = try Self.queryRecordRow(
                "SELECT id, kind, consumed_at, needs_backup FROM journal_records WHERE consumed_at >= ? AND consumed_at < ? ORDER BY consumed_at, id",
                values: [.double(start.timeIntervalSince1970), .double(endExclusive.timeIntervalSince1970)],
                in: database
            )
            return try rows.map { try Self.decodeEntry($0, in: database).record }
        }
    }

    public func entries(from start: Date, to endExclusive: Date) throws -> [JournalLibraryEntry] {
        try withDatabase { database in
            let rows = try Self.queryRecordRow(
                "SELECT id, kind, consumed_at, needs_backup FROM journal_records WHERE consumed_at >= ? AND consumed_at < ? ORDER BY consumed_at, id",
                values: [.double(start.timeIntervalSince1970), .double(endExclusive.timeIntervalSince1970)],
                in: database
            )
            return try rows.map { try Self.decodeEntry($0, in: database) }
        }
    }

    public func recentEntries(limit: Int = 100) throws -> [JournalLibraryEntry] {
        let safeLimit = min(max(limit, 1), 500)
        return try withDatabase { database in
            let rows = try Self.queryRecordRow(
                "SELECT id, kind, consumed_at, needs_backup FROM journal_records ORDER BY consumed_at DESC, id ASC LIMIT \(safeLimit)",
                values: [],
                in: database
            )
            return try rows.map { try Self.decodeEntry($0, in: database) }
        }
    }

    public func recentPhotoEntries(limit: Int = 8) throws -> [JournalLibraryEntry] {
        let safeLimit = min(max(limit, 1), 100)
        return try withDatabase { database in
            let rows = try Self.queryRecordRow(
                """
                SELECT id, kind, consumed_at, needs_backup FROM journal_records
                WHERE photo_id IS NOT NULL OR EXISTS(SELECT 1 FROM meal_dishes WHERE meal_dishes.record_id = journal_records.id AND meal_dishes.photo_id IS NOT NULL)
                ORDER BY consumed_at DESC, id ASC LIMIT \(safeLimit)
                """,
                values: [],
                in: database
            )
            return try rows.map { try Self.decodeEntry($0, in: database) }
        }
    }

    public func referencesDrinkID(_ drinkID: String) throws -> Bool {
        try scalarInt(
            "SELECT EXISTS(SELECT 1 FROM journal_records WHERE kind = 'drink' AND drink_id = ?)",
            values: [.text(drinkID)]
        ) != 0
    }

    public func referencedDrinkIDs() throws -> Set<String> {
        try withDatabase { database in
            let statement = try Self.prepare(
                "SELECT DISTINCT drink_id FROM journal_records WHERE kind = 'drink' AND drink_id IS NOT NULL AND drink_id != ''",
                in: database
            )
            var ids = Set<String>()
            while try statement.step() { ids.insert(statement.text(0)) }
            return ids
        }
    }

    public func legacyIssueCount() throws -> Int { try scalarInt("SELECT COUNT(*) FROM legacy_records") }

    public func historyPage(
        query: JournalHistoryQuery,
        after cursor: JournalHistoryCursor? = nil,
        limit: Int = 50
    ) throws -> JournalHistoryPage {
        let batchSize = min(max(limit, 1), 200)
        let types = query.recordTypes.intersection(["drink", "meal"]).sorted()
        guard !types.isEmpty else { return JournalHistoryPage(items: [], nextCursor: nil, hasMore: false) }

        var clauses: [String] = []
        var values: [SQLiteValue] = []
        if let startDate = query.startDate {
            let start = Calendar.current.startOfDay(for: startDate)
            clauses.append("consumed_at >= ?")
            values.append(.double(start.timeIntervalSince1970))
        }
        if let endDate = query.endDate {
            let endDay = Calendar.current.startOfDay(for: endDate)
            let endExclusive = Calendar.current.date(byAdding: .day, value: 1, to: endDay) ?? endDay.addingTimeInterval(86_400)
            clauses.append("consumed_at < ?")
            values.append(.double(endExclusive.timeIntervalSince1970))
        }
        clauses.append("kind IN (\(Array(repeating: "?", count: types.count).joined(separator: ",")))")
        values.append(contentsOf: types.map(SQLiteValue.text))

        let foldedQuery = Self.fold(query.searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        if !foldedQuery.isEmpty {
            clauses.append("instr(search_key, ?) > 0")
            values.append(.text(foldedQuery))
        }
        let dayExpression = "date(consumed_at, 'unixepoch', 'localtime')"
        if let cursor {
            clauses.append("(\(dayExpression) < ? OR (\(dayExpression) = ? AND (consumed_at > ? OR (consumed_at = ? AND id > ?))))")
            values.append(.text(cursor.localDay))
            values.append(.text(cursor.localDay))
            values.append(.double(cursor.consumedAt))
            values.append(.double(cursor.consumedAt))
            values.append(.text(cursor.recordID))
        }

        let sql = """
        SELECT id, kind, consumed_at, needs_backup
        FROM journal_records
        WHERE \(clauses.joined(separator: " AND "))
        ORDER BY \(dayExpression) DESC, consumed_at ASC, id ASC
        LIMIT \(batchSize + 1)
        """
        return try withDatabase { database in
            let rows = try Self.queryRecordRow(sql, values: values, in: database)
            let hasMore = rows.count > batchSize
            let pageRows = Array(rows.prefix(batchSize))
            let entries = try pageRows.map { try Self.decodeEntry($0, in: database) }
            let nextCursor = pageRows.last.map { row in
                JournalHistoryCursor(
                    localDay: Self.localDayKey(for: row.consumedAt),
                    consumedAt: row.consumedAt.timeIntervalSince1970,
                    recordID: row.id
                )
            }
            return JournalHistoryPage(items: entries, nextCursor: nextCursor, hasMore: hasMore)
        }
    }

    public func legacyIssues() throws -> [JournalLegacyRecordIssue] {
        try withDatabase { database in
            let statement = try Self.prepare("SELECT id, record_type, consumed_at FROM legacy_records ORDER BY consumed_at DESC, id ASC", in: database)
            var rows: [JournalLegacyRecordIssue] = []
            while try statement.step() {
                rows.append(JournalLegacyRecordIssue(
                    id: statement.text(0),
                    recordType: statement.text(1),
                    consumedAt: Date(timeIntervalSince1970: statement.double(2))
                ))
            }
            return rows
        }
    }

    public func legacyIssues(from start: Date?, to end: Date?) throws -> [JournalLegacyRecordIssue] {
        var clauses: [String] = []
        var values: [SQLiteValue] = []
        if let start {
            clauses.append("consumed_at >= ?")
            values.append(.double(Calendar.current.startOfDay(for: start).timeIntervalSince1970))
        }
        if let end {
            let day = Calendar.current.startOfDay(for: end)
            let exclusive = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            clauses.append("consumed_at < ?")
            values.append(.double(exclusive.timeIntervalSince1970))
        }
        let sql = "SELECT id, record_type, consumed_at FROM legacy_records"
            + (clauses.isEmpty ? "" : " WHERE \(clauses.joined(separator: " AND "))")
            + " ORDER BY consumed_at DESC, id ASC"
        return try withDatabase { database in
            let statement = try Self.prepare(sql, in: database)
            try statement.bind(values)
            var rows: [JournalLegacyRecordIssue] = []
            while try statement.step() {
                rows.append(JournalLegacyRecordIssue(
                    id: statement.text(0), recordType: statement.text(1),
                    consumedAt: Date(timeIntervalSince1970: statement.double(2))
                ))
            }
            return rows
        }
    }

    public func photoAssets() throws -> [PhotoAsset] {
        try withDatabase { database in
            let rows = try Self.queryRows(
                """
                SELECT photo_id, photo_file_name, photo_file_extension, photo_byte_count, photo_sha256
                FROM journal_records WHERE photo_id IS NOT NULL
                UNION
                SELECT photo_id, photo_file_name, photo_file_extension, photo_byte_count, photo_sha256
                FROM meal_dishes WHERE photo_id IS NOT NULL
                ORDER BY photo_id
                """,
                parameters: [], in: database
            )
            return try rows.compactMap { row in
                guard let id = UUID(uuidString: row.text(0)),
                      let fileName = row.optionalText(1),
                      let fileExtension = row.optionalText(2),
                      let byteCount = row.optionalInt(3),
                      let sha256 = row.optionalText(4) else { return nil }
                return try PhotoAsset(id: id, fileName: fileName, fileExtension: fileExtension, byteCount: byteCount, sha256: sha256)
            }
        }
    }

    public func databaseByteCount(fileManager: FileManager = .default) -> Int? {
        [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
            .compactMap { try? fileManager.attributesOfItem(atPath: $0.path)[.size] as? NSNumber }
            .reduce(0) { $0 + $1.intValue }
    }

    public func setArchiveMetadata(_ data: Data) throws {
        try execute(
            "INSERT OR REPLACE INTO archive_metadata(key,value) VALUES('snapshot',?)",
            values: [.blob(data)]
        )
    }

    public func archiveMetadata() throws -> Data? {
        try withDatabase { database in
            let statement = try Self.prepare("SELECT value FROM archive_metadata WHERE key = 'snapshot'", in: database)
            guard try statement.step() else { return nil }
            return statement.data(0)
        }
    }

    public func importLegacy(_ snapshot: StoredJournalRecordSnapshot) throws {
        try importLegacy([snapshot])
    }

    public func importLegacy(_ snapshots: [StoredJournalRecordSnapshot]) throws {
        try transaction { database in
            for snapshot in snapshots {
                let record: JournalRecord
                do {
                    record = try snapshot.decodeRecord()
                    try record.validate()
                } catch {
                    try Self.execute(
                        "INSERT OR REPLACE INTO legacy_records(id,record_type,consumed_at,payload_version,payload,needs_backup,error_text) VALUES(?,?,?,?,?,?,?)",
                        values: [
                            .text(snapshot.recordID), .text(snapshot.recordType), .double(snapshot.consumedAt.timeIntervalSince1970),
                            .int(snapshot.payloadVersion), .blob(snapshot.payload), .bool(snapshot.needsBackup), .text(String(describing: error))
                        ],
                        in: database
                    )
                    try Self.incrementDataGeneration(in: database)
                    continue
                }
                try Self.insert(record, needsBackup: snapshot.needsBackup, in: database)
                try Self.incrementDataGeneration(in: database)
            }
        }
    }

    public func matchesImportedLegacySnapshot(_ snapshot: StoredJournalRecordSnapshot) throws -> Bool {
        if let decodedRecord = try? snapshot.decodeRecord(), (try? decodedRecord.validate()) != nil {
            guard let imported = try record(id: decodedRecord.id) else { return false }
            return imported.record == decodedRecord && imported.needsBackup == snapshot.needsBackup
        }
        return try withDatabase { database in
            let statement = try Self.prepare(
                "SELECT record_type, consumed_at, payload_version, payload, needs_backup FROM legacy_records WHERE id = ?",
                in: database
            )
            try statement.bind([.text(snapshot.recordID)])
            guard try statement.step() else { return false }
            return statement.text(0) == snapshot.recordType
                && statement.double(1) == snapshot.consumedAt.timeIntervalSince1970
                && statement.int(2) == snapshot.payloadVersion
                && statement.data(3) == snapshot.payload
                && (statement.int(4) != 0) == snapshot.needsBackup
        }
    }

    /// Produces a standalone SQLite copy using SQLite's online backup API.
    public func writeConsistentSnapshot(to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try withDatabase { source in
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            var target: OpaquePointer?
            guard sqlite3_open_v2(destination.path, &target, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
                  let target else {
                let reason = target.map { String(cString: sqlite3_errmsg($0)) } ?? "无法创建备份文件"
                if let target { sqlite3_close(target) }
                throw JournalSQLiteStoreError.backupFailed(reason)
            }
            defer { sqlite3_close(target) }
            guard let backup = sqlite3_backup_init(target, "main", source, "main") else {
                throw JournalSQLiteStoreError.backupFailed(String(cString: sqlite3_errmsg(target)))
            }
            let result = sqlite3_backup_step(backup, -1)
            let finish = sqlite3_backup_finish(backup)
            guard result == SQLITE_DONE, finish == SQLITE_OK else {
                throw JournalSQLiteStoreError.backupFailed(String(cString: sqlite3_errmsg(target)))
            }
        }
    }

    /// Restores an archive into an empty live library in one SQL transaction.
    /// Copying tables preserves the raw payloads of legacy rows that could not be decoded.
    public func restoreDatabase(from sourceURL: URL) throws {
        let source = try JournalSQLiteStore(url: sourceURL, readOnly: true)
        defer { source.close() }
        try source.validateIntegrity()
        guard source.migrationComplete else {
            throw JournalSQLiteStoreError.backupFailed("恢复文件没有完整的资料库迁移标记。")
        }
        let sourceCounts = try source.migrationCounts()

        try execute("ATTACH DATABASE ? AS restore_source", values: [.text(sourceURL.path)])
        defer { try? execute("DETACH DATABASE restore_source") }
        try transaction { database in
            let currentCount = try Self.scalarInt("SELECT COUNT(*) FROM journal_records", in: database)
                + Self.scalarInt("SELECT COUNT(*) FROM legacy_records", in: database)
            guard currentCount == 0 else { throw JournalLibraryRestoreError.libraryNotEmpty }

            try Self.execute("DELETE FROM library_metadata", in: database)
            try Self.execute("INSERT INTO library_metadata SELECT * FROM restore_source.library_metadata", in: database)
            try Self.execute("INSERT INTO journal_records SELECT * FROM restore_source.journal_records", in: database)
            try Self.execute("INSERT INTO meal_dishes SELECT * FROM restore_source.meal_dishes", in: database)
            try Self.execute("INSERT INTO nutrition_metric_sources SELECT * FROM restore_source.nutrition_metric_sources", in: database)
            try Self.execute("INSERT INTO legacy_records SELECT * FROM restore_source.legacy_records", in: database)

            let restoredRecords = try Self.scalarInt("SELECT COUNT(*) FROM journal_records", in: database)
            let restoredLegacy = try Self.scalarInt("SELECT COUNT(*) FROM legacy_records", in: database)
            guard restoredRecords == sourceCounts.records, restoredLegacy == sourceCounts.legacy else {
                throw JournalSQLiteStoreError.migrationCountMismatch
            }
        }
        try validateIntegrity()
    }

    public func validateIntegrity() throws {
        let result = try scalarText("PRAGMA integrity_check")
        guard result == "ok" else { throw JournalSQLiteStoreError.sqliteFailure(result ?? "完整性检查没有结果") }
    }

    // MARK: - Migration support

    public func migrationCounts() throws -> (records: Int, legacy: Int) {
        (try scalarInt("SELECT COUNT(*) FROM journal_records"), try scalarInt("SELECT COUNT(*) FROM legacy_records"))
    }

    // MARK: - SQL implementation

    private func createSchema() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS library_metadata (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        )
        """)
        try execute("INSERT OR IGNORE INTO library_metadata(key,value) VALUES('data_generation','0')")
        try execute("CREATE TABLE IF NOT EXISTS archive_metadata (key TEXT PRIMARY KEY NOT NULL, value BLOB NOT NULL)")
        try execute("""
        CREATE TABLE IF NOT EXISTS journal_records (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL CHECK(kind IN ('drink','meal')),
            consumed_at REAL NOT NULL,
            needs_backup INTEGER NOT NULL DEFAULT 1,
            search_key TEXT NOT NULL DEFAULT '',
            brand_id TEXT, brand_name TEXT, drink_id TEXT, drink_name TEXT,
            cup_type TEXT, size_ml INTEGER, sweetness TEXT, serving_option TEXT,
            temperature TEXT, ice TEXT, location_name TEXT, location_address TEXT,
            latitude REAL, longitude REAL, store_name TEXT, notes TEXT,
            energy_kcal REAL, sugar_grams REAL, caffeine_milligrams REAL,
            nutrition_confidence TEXT, nutrition_source TEXT, nutrition_source_url TEXT,
            protein_grams REAL, fat_grams REAL, carbohydrate_grams REAL, nutrition_assumptions TEXT,
            photo_id TEXT, photo_file_name TEXT, photo_file_extension TEXT, photo_byte_count INTEGER, photo_sha256 TEXT
        )
        """)
        try execute("CREATE INDEX IF NOT EXISTS journal_records_time_id ON journal_records(consumed_at, id)")
        try execute("CREATE INDEX IF NOT EXISTS journal_records_type_time ON journal_records(kind, consumed_at, id)")
        try execute("CREATE INDEX IF NOT EXISTS journal_records_drink_id ON journal_records(drink_id) WHERE drink_id IS NOT NULL")
        try execute("""
        CREATE TABLE IF NOT EXISTS meal_dishes (
            id TEXT PRIMARY KEY NOT NULL,
            record_id TEXT NOT NULL REFERENCES journal_records(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            name TEXT NOT NULL,
            photo_id TEXT, photo_file_name TEXT, photo_file_extension TEXT, photo_byte_count INTEGER, photo_sha256 TEXT,
            energy_kcal REAL, sugar_grams REAL, caffeine_milligrams REAL,
            nutrition_confidence TEXT, nutrition_source TEXT, nutrition_source_url TEXT,
            protein_grams REAL, fat_grams REAL, carbohydrate_grams REAL, nutrition_assumptions TEXT,
            UNIQUE(record_id, position)
        )
        """)
        try execute("CREATE INDEX IF NOT EXISTS meal_dishes_record_position ON meal_dishes(record_id, position)")
        try execute("""
        CREATE TABLE IF NOT EXISTS nutrition_metric_sources (
            owner_kind TEXT NOT NULL,
            owner_id TEXT NOT NULL,
            metric TEXT NOT NULL,
            source TEXT NOT NULL,
            PRIMARY KEY(owner_kind, owner_id, metric)
        )
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS legacy_records (
            id TEXT PRIMARY KEY NOT NULL,
            record_type TEXT NOT NULL,
            consumed_at REAL NOT NULL,
            payload_version INTEGER NOT NULL,
            payload BLOB NOT NULL,
            needs_backup INTEGER NOT NULL,
            error_text TEXT NOT NULL
        )
        """)
    }

    private static func insertRecord(
        id: String,
        type: String,
        consumedAt: Date,
        needsBackup: Bool,
        searchKey: String,
        fields: [SQLiteValue],
        nutrition: NutritionSnapshot?,
        photo: PhotoAsset?,
        in database: OpaquePointer
    ) throws {
        let columns = [
            "id", "kind", "consumed_at", "needs_backup", "search_key",
            "brand_id", "brand_name", "drink_id", "drink_name", "cup_type", "size_ml", "sweetness", "serving_option",
            "temperature", "ice", "location_name", "location_address", "latitude", "longitude", "store_name", "notes",
            "energy_kcal", "sugar_grams", "caffeine_milligrams", "nutrition_confidence", "nutrition_source", "nutrition_source_url",
            "protein_grams", "fat_grams", "carbohydrate_grams", "nutrition_assumptions",
            "photo_id", "photo_file_name", "photo_file_extension", "photo_byte_count", "photo_sha256"
        ]
        var values: [SQLiteValue] = [
            .text(id), .text(type), .double(consumedAt.timeIntervalSince1970), .bool(needsBackup), .text(searchKey)
        ]
        values.append(contentsOf: fields)
        values.append(contentsOf: Self.nutritionValues(nutrition))
        values.append(contentsOf: Self.photoValues(photo))
        try Self.execute(
            "INSERT INTO journal_records(\(columns.joined(separator: ","))) VALUES(\(Array(repeating: "?", count: columns.count).joined(separator: ",")))",
            values: values,
            in: database
        )
        if let nutrition { try Self.insertSources(nutrition.metricSources, ownerKind: "record", ownerID: id, in: database) }
    }

    private static func insertDish(_ dish: MealDish, position: Int, recordID: String, in database: OpaquePointer) throws {
        let columns = [
            "id", "record_id", "position", "name", "photo_id", "photo_file_name", "photo_file_extension", "photo_byte_count", "photo_sha256",
            "energy_kcal", "sugar_grams", "caffeine_milligrams", "nutrition_confidence", "nutrition_source", "nutrition_source_url",
            "protein_grams", "fat_grams", "carbohydrate_grams", "nutrition_assumptions"
        ]
        var values: [SQLiteValue] = [.text(dish.id.uuidString), .text(recordID), .int(position), .text(dish.name)]
        values.append(contentsOf: photoValues(dish.photo))
        values.append(contentsOf: nutritionValues(dish.nutrition))
        try execute(
            "INSERT INTO meal_dishes(\(columns.joined(separator: ","))) VALUES(\(Array(repeating: "?", count: columns.count).joined(separator: ",")))",
            values: values,
            in: database
        )
        if let nutrition = dish.nutrition {
            try insertSources(nutrition.metricSources, ownerKind: "dish", ownerID: dish.id.uuidString, in: database)
        }
    }

    private static func decodeEntry(_ row: RecordRow, in database: OpaquePointer) throws -> JournalLibraryEntry {
        let query = "SELECT * FROM journal_records WHERE id = ?"
        guard let values = try queryRows(query, parameters: [.text(row.id)], in: database).first else {
            throw JournalSQLiteStoreError.sqliteFailure("结构化记录行丢失：\(row.id)")
        }
        guard let id = UUID(uuidString: row.id) else { throw JournalSQLiteStoreError.invalidRecord(UUID()) }
        let consumedAt = row.consumedAt
        let record: JournalRecord
        if row.kind == "drink" {
            let nutrition = try decodeNutrition(values, start: 21, ownerKind: "record", ownerID: row.id, in: database)
            let photo = try decodePhoto(values, start: 31)
            let drink = try DrinkRecord(
                id: id,
                consumedAt: consumedAt,
                brandID: values.text(5),
                brandName: values.text(6),
                drinkID: values.text(7),
                drinkName: values.text(8),
                cupType: values.text(9),
                sizeML: values.optionalInt(10),
                sweetness: values.text(11),
                servingOption: values.text(12),
                temperature: values.optionalText(13),
                ice: values.optionalText(14),
                locationName: values.text(15),
                locationAddress: values.text(16),
                latitude: values.optionalDouble(17),
                longitude: values.optionalDouble(18),
                notes: values.text(20),
                photo: photo,
                nutrition: nutrition
            )
            record = .drink(drink)
        } else if row.kind == "meal" {
            let dishes = try queryRows(
                "SELECT * FROM meal_dishes WHERE record_id = ? ORDER BY position ASC",
                parameters: [.text(row.id)],
                in: database
            ).map { dishValues -> MealDish in
                let dishID = UUID(uuidString: dishValues.text(0)) ?? UUID()
                let photo = try decodePhoto(dishValues, start: 4)
                let nutrition = try decodeNutrition(dishValues, start: 9, ownerKind: "dish", ownerID: dishValues.text(0), in: database)
                return try MealDish(id: dishID, name: dishValues.text(3), photo: photo, nutrition: nutrition)
            }
            let meal = try MealRecord(
                id: id,
                consumedAt: consumedAt,
                storeName: values.text(19),
                locationAddress: values.text(16),
                latitude: values.optionalDouble(17),
                longitude: values.optionalDouble(18),
                dishes: dishes,
                notes: values.text(20)
            )
            record = .meal(meal)
        } else {
            throw JournalSQLiteStoreError.sqliteFailure("未知记录类型：\(row.kind)")
        }
        return JournalLibraryEntry(record: record, needsBackup: row.needsBackup)
    }

    private static func decodeNutrition(
        _ row: SQLiteRow,
        start: Int32,
        ownerKind: String,
        ownerID: String,
        in database: OpaquePointer
    ) throws -> NutritionSnapshot? {
        guard let confidenceText = row.optionalText(start + 3),
              let confidence = NutritionSnapshot.Confidence(rawValue: confidenceText) else { return nil }
        let sourceRows = try queryRows(
            "SELECT metric, source FROM nutrition_metric_sources WHERE owner_kind = ? AND owner_id = ?",
            parameters: [.text(ownerKind), .text(ownerID)],
            in: database
        )
        let sources = Dictionary(sourceRows.map { ($0.text(0), $0.text(1)) }, uniquingKeysWith: { _, last in last })
        return NutritionSnapshot(
            energyKcal: row.optionalDouble(start),
            sugarGrams: row.optionalDouble(start + 1),
            caffeineMilligrams: row.optionalDouble(start + 2),
            confidence: confidence,
            source: row.text(start + 4),
            sourceURL: row.optionalText(start + 5),
            proteinGrams: row.optionalDouble(start + 6),
            fatGrams: row.optionalDouble(start + 7),
            carbohydrateGrams: row.optionalDouble(start + 8),
            assumptions: row.text(start + 9),
            metricSources: sources
        )
    }

    private static func decodePhoto(_ row: SQLiteRow, start: Int32) throws -> PhotoAsset? {
        guard let idText = row.optionalText(start),
              let id = UUID(uuidString: idText),
              let fileName = row.optionalText(start + 1),
              let fileExtension = row.optionalText(start + 2),
              let byteCount = row.optionalInt(start + 3),
              let sha256 = row.optionalText(start + 4) else { return nil }
        return try PhotoAsset(id: id, fileName: fileName, fileExtension: fileExtension, byteCount: byteCount, sha256: sha256)
    }

    private static func nutritionValues(_ nutrition: NutritionSnapshot?) -> [SQLiteValue] {
        guard let nutrition else { return Array(repeating: .null, count: 10) }
        return [
            .optionalDouble(nutrition.energyKcal), .optionalDouble(nutrition.sugarGrams), .optionalDouble(nutrition.caffeineMilligrams),
            .text(nutrition.confidence.rawValue), .text(nutrition.source), .optionalText(nutrition.sourceURL),
            .optionalDouble(nutrition.proteinGrams), .optionalDouble(nutrition.fatGrams), .optionalDouble(nutrition.carbohydrateGrams),
            .text(nutrition.assumptions)
        ]
    }

    private static func photoValues(_ photo: PhotoAsset?) -> [SQLiteValue] {
        guard let photo else { return Array(repeating: .null, count: 5) }
        return [
            .text(photo.id.uuidString), .text(photo.fileName), .text(photo.fileExtension), .int(photo.byteCount), .text(photo.sha256)
        ]
    }

    private static func insertSources(_ sources: [String: String], ownerKind: String, ownerID: String, in database: OpaquePointer) throws {
        for (metric, source) in sources {
            try execute(
                "INSERT INTO nutrition_metric_sources(owner_kind,owner_id,metric,source) VALUES(?,?,?,?)",
                values: [.text(ownerKind), .text(ownerID), .text(metric), .text(source)],
                in: database
            )
        }
    }

    private static func incrementDataGeneration(in database: OpaquePointer) throws {
        try execute("UPDATE library_metadata SET value = CAST(value AS INTEGER) + 1 WHERE key = 'data_generation'", in: database)
    }

    private static func queryRecordRow(_ sql: String, values: [SQLiteValue], in database: OpaquePointer) throws -> [RecordRow] {
        let statement = try prepare(sql, in: database)
        try statement.bind(values)
        var result: [RecordRow] = []
        while try statement.step() {
            result.append(RecordRow(
                id: statement.text(0),
                kind: statement.text(1),
                consumedAt: Date(timeIntervalSince1970: statement.double(2)),
                needsBackup: statement.int(3) != 0
            ))
        }
        return result
    }

    private static func queryRows(_ sql: String, parameters: [SQLiteValue], in database: OpaquePointer) throws -> [SQLiteRow] {
        let statement = try prepare(sql, in: database)
        try statement.bind(parameters)
        var result: [SQLiteRow] = []
        while try statement.step() { result.append(SQLiteRow(statement.pointer)) }
        return result
    }

    private func scalarInt(_ sql: String, values: [SQLiteValue] = []) throws -> Int {
        try withDatabase { database in
            let statement = try Self.prepare(sql, in: database)
            try statement.bind(values)
            guard try statement.step() else { return 0 }
            return statement.int(0)
        }
    }
    private func scalarText(_ sql: String) throws -> String? { try withDatabase { try Self.scalarText(sql, in: $0) } }

    private static func scalarInt(_ sql: String, in database: OpaquePointer) throws -> Int {
        let statement = try prepare(sql, in: database)
        guard try statement.step() else { return 0 }
        return statement.int(0)
    }

    private static func scalarText(_ sql: String, in database: OpaquePointer) throws -> String? {
        let statement = try prepare(sql, in: database)
        guard try statement.step() else { return nil }
        return statement.optionalText(0)
    }

    private func execute(_ sql: String, values: [SQLiteValue] = []) throws {
        try withDatabase { try Self.execute(sql, values: values, in: $0) }
    }

    private static func execute(_ sql: String, values: [SQLiteValue] = [], in database: OpaquePointer) throws {
        let statement = try prepare(sql, in: database)
        try statement.bind(values)
        _ = try statement.step()
    }

    private func transaction<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try withDatabase { database in
            try Self.execute("BEGIN IMMEDIATE", in: database)
            do {
                let value = try body(database)
                try Self.execute("COMMIT", in: database)
                return value
            } catch {
                try? Self.execute("ROLLBACK", in: database)
                throw error
            }
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let database else { throw JournalSQLiteStoreError.cannotOpen("资料库已关闭") }
        return try body(database)
    }

    private static func prepare(_ sql: String, in database: OpaquePointer) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw failure(database) }
        return SQLiteStatement(pointer: statement, database: database)
    }

    private static func failure(_ database: OpaquePointer) -> JournalSQLiteStoreError {
        .sqliteFailure(String(cString: sqlite3_errmsg(database)))
    }

    private static func searchableText(for record: JournalRecord) -> String {
        switch record {
        case .drink(let value):
            return [value.brandName, value.drinkName, value.locationName, value.locationAddress, value.notes].joined(separator: "\n")
        case .meal(let value):
            return ([value.storeName, value.locationAddress, value.notes] + value.dishes.map(\.name)).joined(separator: "\n")
        }
    }

    private static func insert(_ record: JournalRecord, needsBackup: Bool, in database: OpaquePointer) throws {
        let id = record.id.uuidString
        try Self.execute(
            "DELETE FROM nutrition_metric_sources WHERE owner_kind = 'record' AND owner_id = ?",
            values: [.text(id)],
            in: database
        )
        try Self.execute(
            "DELETE FROM nutrition_metric_sources WHERE owner_kind = 'dish' AND owner_id IN (SELECT id FROM meal_dishes WHERE record_id = ?)",
            values: [.text(id)],
            in: database
        )
        try Self.execute("DELETE FROM journal_records WHERE id = ?", values: [.text(id)], in: database)
        switch record {
        case .drink(let drink):
            try Self.insertRecord(
                id: id,
                type: "drink",
                consumedAt: drink.consumedAt,
                needsBackup: needsBackup,
                searchKey: Self.fold(Self.searchableText(for: record)),
                fields: [
                    .text(drink.brandID), .text(drink.brandName), .text(drink.drinkID), .text(drink.drinkName),
                    .text(drink.cupType), .optionalInt(drink.sizeML), .text(drink.sweetness), .text(drink.servingOption),
                    .optionalText(drink.temperature), .optionalText(drink.ice), .text(drink.locationName),
                    .text(drink.locationAddress), .optionalDouble(drink.latitude), .optionalDouble(drink.longitude),
                    .null, .text(drink.notes)
                ], nutrition: drink.nutrition, photo: drink.photo, in: database
            )
        case .meal(let meal):
            try Self.insertRecord(
                id: id,
                type: "meal",
                consumedAt: meal.consumedAt,
                needsBackup: needsBackup,
                searchKey: Self.fold(Self.searchableText(for: record)),
                fields: [
                    .null, .null, .null, .null, .null, .null, .null, .null, .null, .null,
                    .null, .text(meal.locationAddress), .optionalDouble(meal.latitude), .optionalDouble(meal.longitude),
                    .text(meal.storeName), .text(meal.notes)
                ], nutrition: nil, photo: nil, in: database
            )
            for (position, dish) in meal.dishes.enumerated() {
                try Self.insertDish(dish, position: position, recordID: id, in: database)
            }
        }
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: .current)
    }

    private static func localDayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

@MainActor
public enum JournalDatabaseMigrator {
    public static func migrate(
        from container: ModelContainer,
        into store: JournalSQLiteStore,
        batchSize: Int = 100,
        progress: (@MainActor (Int, Int) -> Void)? = nil
    ) async throws {
        let context = ModelContext(container)
        let total = try context.fetchCount(FetchDescriptor<StoredJournalRecord>())
        var offset = 0
        while offset < total {
            var descriptor = FetchDescriptor<StoredJournalRecord>(sortBy: [SortDescriptor(\.recordID)])
            descriptor.fetchLimit = min(max(batchSize, 1), 500)
            descriptor.fetchOffset = offset
            let batch = try context.fetch(descriptor)
            guard !batch.isEmpty else { break }
            let snapshots = batch.map { $0.decodingSnapshot() }
            try await Task.detached(priority: .utility) {
                try store.importLegacy(snapshots)
                for snapshot in snapshots {
                    guard try store.matchesImportedLegacySnapshot(snapshot) else {
                        throw JournalSQLiteStoreError.migrationCountMismatch
                    }
                }
            }.value
            offset += batch.count
            progress?(offset, total)
            await Task.yield()
        }

        let counts = try store.migrationCounts()
        guard counts.records + counts.legacy == total else { throw JournalSQLiteStoreError.migrationCountMismatch }
        try store.validateIntegrity()
        try store.markMigrationComplete()
    }
}

@MainActor
public enum JournalDatabaseBootstrapper {
    public static func open(
        at destination: URL,
        migratingFrom legacyContainer: ModelContainer?,
        progress: (@MainActor (Int, Int) -> Void)? = nil
    ) async throws -> JournalSQLiteStore {
        if FileManager.default.fileExists(atPath: destination.path) {
            let existing = try JournalSQLiteStore(url: destination)
            if existing.migrationComplete { return existing }
            existing.close()
            throw JournalSQLiteStoreError.sqliteFailure("资料库存在，但迁移标记未完成；旧资料保持原样。")
        }
        guard let legacyContainer else {
            throw JournalSQLiteStoreError.cannotOpen("尚未找到已迁移的资料库，也无法打开旧资料库。")
        }

        let staging = destination.appendingPathExtension("migrating")
        if FileManager.default.fileExists(atPath: staging.path) {
            try FileManager.default.removeItem(at: staging)
        }
        let stagedStore = try JournalSQLiteStore(url: staging)
        do {
            try await JournalDatabaseMigrator.migrate(from: legacyContainer, into: stagedStore, progress: progress)
            try stagedStore.closeForFileMove()
            try FileManager.default.moveItem(at: staging, to: destination)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: staging.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: staging.path + "-shm"))
            return try JournalSQLiteStore(url: destination)
        } catch {
            stagedStore.close()
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: staging.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: staging.path + "-shm"))
            throw error
        }
    }
}

private struct RecordRow {
    let id: String
    let kind: String
    let consumedAt: Date
    let needsBackup: Bool
}

private enum SQLiteValue {
    case text(String)
    case double(Double)
    case int(Int)
    case bool(Bool)
    case blob(Data)
    case optionalText(String?)
    case optionalDouble(Double?)
    case optionalInt(Int?)
    case null
}

private final class SQLiteStatement {
    let pointer: OpaquePointer
    private let database: OpaquePointer

    init(pointer: OpaquePointer, database: OpaquePointer) {
        self.pointer = pointer
        self.database = database
    }

    deinit { sqlite3_finalize(pointer) }

    func bind(_ values: [SQLiteValue]) throws {
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch value {
            case .text(let value): result = value.withCString { sqlite3_bind_text(pointer, position, $0, -1, sqliteTransient()) }
            case .double(let value): result = sqlite3_bind_double(pointer, position, value)
            case .int(let value): result = sqlite3_bind_int64(pointer, position, sqlite3_int64(value))
            case .bool(let value): result = sqlite3_bind_int(pointer, position, value ? 1 : 0)
            case .blob(let data):
                result = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(pointer, position, bytes.baseAddress, Int32(data.count), sqliteTransient())
                }
            case .optionalText(let value):
                result = value.map { text in text.withCString { sqlite3_bind_text(pointer, position, $0, -1, sqliteTransient()) } } ?? sqlite3_bind_null(pointer, position)
            case .optionalDouble(let value): result = value.map { sqlite3_bind_double(pointer, position, $0) } ?? sqlite3_bind_null(pointer, position)
            case .optionalInt(let value): result = value.map { sqlite3_bind_int64(pointer, position, sqlite3_int64($0)) } ?? sqlite3_bind_null(pointer, position)
            case .null: result = sqlite3_bind_null(pointer, position)
            }
            guard result == SQLITE_OK else { throw JournalSQLiteStoreError.sqliteFailure(String(cString: sqlite3_errmsg(database))) }
        }
    }

    func step() throws -> Bool {
        let result = sqlite3_step(pointer)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        throw JournalSQLiteStoreError.sqliteFailure(String(cString: sqlite3_errmsg(database)))
    }

    func text(_ index: Int32) -> String { optionalText(index) ?? "" }
    func optionalText(_ index: Int32) -> String? {
        guard sqlite3_column_type(pointer, index) != SQLITE_NULL,
              let value = sqlite3_column_text(pointer, index) else { return nil }
        return String(cString: value)
    }
    func int(_ index: Int32) -> Int { Int(sqlite3_column_int64(pointer, index)) }
    func optionalInt(_ index: Int32) -> Int? {
        sqlite3_column_type(pointer, index) == SQLITE_NULL ? nil : int(index)
    }
    func double(_ index: Int32) -> Double { sqlite3_column_double(pointer, index) }
    func optionalDouble(_ index: Int32) -> Double? {
        sqlite3_column_type(pointer, index) == SQLITE_NULL ? nil : double(index)
    }
    func data(_ index: Int32) -> Data? {
        guard sqlite3_column_type(pointer, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(pointer, index) else { return nil }
        let count = Int(sqlite3_column_bytes(pointer, index))
        return Data(bytes: bytes, count: count)
    }
}

private enum SQLiteCell {
    case text(String?)
    case integer(Int64?)
    case real(Double?)
}

private struct SQLiteRow {
    private let cells: [SQLiteCell]

    init(_ pointer: OpaquePointer) {
        cells = (0..<Int(sqlite3_column_count(pointer))).map { index in
            let column = Int32(index)
            return switch sqlite3_column_type(pointer, column) {
            case SQLITE_INTEGER: .integer(sqlite3_column_int64(pointer, column))
            case SQLITE_FLOAT: .real(sqlite3_column_double(pointer, column))
            case SQLITE_NULL: .text(nil)
            case SQLITE_TEXT:
                .text(sqlite3_column_text(pointer, column).map { String(cString: $0) })
            default: .text(nil)
            }
        }
    }

    func text(_ index: Int32) -> String { optionalText(index) ?? "" }
    func optionalText(_ index: Int32) -> String? {
        guard cells.indices.contains(Int(index)), case .text(let value) = cells[Int(index)] else { return nil }
        return value
    }
    func optionalInt(_ index: Int32) -> Int? {
        guard cells.indices.contains(Int(index)) else { return nil }
        return switch cells[Int(index)] {
            case .integer(let value): value.map(Int.init)
            case .real(let value): value.map { Int($0) }
            case .text: nil
        }
    }
    func optionalDouble(_ index: Int32) -> Double? {
        guard cells.indices.contains(Int(index)) else { return nil }
        return switch cells[Int(index)] {
            case .integer(let value): value.map(Double.init)
            case .real(let value): value
            case .text: nil
        }
    }
}

private func sqliteTransient() -> sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
