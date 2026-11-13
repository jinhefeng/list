import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredJournalRecord.consumedAt, order: .reverse)
    private var storedRecords: [StoredJournalRecord]
    @AppStorage(BackupChangeTracker.pendingKey) private var hasPendingLibraryChanges = false
    @StateObject private var model = BackupWorkflowModel.shared

    private var pendingCount: Int {
        storedRecords.filter(\.needsBackup).count
    }

    private var backupStatus: String {
        if model.isWorking { return "正在写入快照" }
        if model.folderBookmark.isEmpty { return "尚未设置备份目录" }
        return pendingCount > 0 || hasPendingLibraryChanges ? "有待备份变更" : "资料库已备份"
    }

    var body: some View {
        Form {
            Section {
                GanfanCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(backupStatus, systemImage: model.isWorking ? "arrow.triangle.2.circlepath.icloud" : "externaldrive")
                            .font(.headline)
                            .foregroundStyle(model.folderBookmark.isEmpty || pendingCount > 0 || hasPendingLibraryChanges ? GanfanPalette.leaf : GanfanPalette.forest)
                        Text("\(storedRecords.count) 条记录 · \(pendingCount) 条待备份")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !model.folderName.isEmpty {
                            Text(model.folderName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))
            }

            Section("备份目录") {
                if model.folderName.isEmpty {
                    Text("尚未选择目录")
                        .foregroundStyle(.secondary)
                } else {
                    Label(model.folderName, systemImage: "folder")
                }

                Button("选择备份目录") {
                    model.isImportingFolder = true
                }

                Text("备份文件保存在所选目录下的「干饭手册」文件夹中。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("本机资料库") {
                LabeledContent("记录数", value: "\(storedRecords.count)")
                LabeledContent("待备份记录", value: "\(pendingCount)")
                LabeledContent("资料库变更", value: hasPendingLibraryChanges ? "待备份" : "已备份")

                Button {
                    model.backupNow(storedRecords: storedRecords, context: modelContext)
                } label: {
                    if model.isWorking {
                        ProgressView("正在校验并写入")
                    } else {
                        Label("立即备份", systemImage: "arrow.up.doc")
                    }
                }
                .disabled(model.isWorking || model.folderBookmark.isEmpty)
            }

            Section("可恢复快照") {
                if model.snapshots.isEmpty {
                    Text("未找到可读取的快照。iCloud 文件尚未下载完成时，可以稍后重新打开此页并刷新。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.snapshots) { snapshot in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            Text("\(snapshot.recordCount) 条记录 · \(snapshot.photoCount) 张原图")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("恢复此快照") {
                                model.requestRestore(snapshot)
                            }
                            .disabled(model.isWorking || !storedRecords.isEmpty)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !storedRecords.isEmpty {
                    Text("为保护本机数据，恢复只对空资料库开放。当前资料库已有记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("状态") {
                Text(model.status)
                    .textSelection(.enabled)

                Text("App 会显示写入所选目录的结果，不会把它直接当作 iCloud 已同步。iCloud 上传由系统后台处理；请在「文件」App 或另一台设备确认云端文件可用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .tint(GanfanPalette.forest)
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .fileImporter(
            isPresented: $model.isImportingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: { result in
                model.saveSelectedFolder(result, records: storedRecords, context: modelContext)
            }
        )
        .confirmationDialog("恢复这份备份？", isPresented: $model.isConfirmingRestore, titleVisibility: .visible) {
            Button("恢复到空资料库", role: .destructive) {
                model.restoreSelectedSnapshot(storedRecords: storedRecords, context: modelContext)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("恢复前会校验全部记录和原图。此操作只在本机资料库为空时执行。")
        }
        .task {
            model.restoreSavedFolderAccess()
        }
    }
}

@MainActor
final class BackupWorkflowModel: ObservableObject {
    static let shared = BackupWorkflowModel()

    private static let bookmarkKey = "selectedBackupFolderBookmark"
    private static let libraryIDKey = "ganfanHandbookLibraryID"

    @Published var folderName = ""
    @Published var status = "选择一个目录，将本机资料库备份到其中。"
    @Published var isWorking = false
    @Published var isImportingFolder = false
    @Published var isConfirmingRestore = false
    @Published private(set) var folderBookmark = UserDefaults.standard.data(forKey: bookmarkKey) ?? Data()
    @Published private(set) var snapshots: [BackupSnapshotSummary] = []

    private var selectedSnapshot: BackupSnapshotSummary?
    private var retryRequestedAfterCurrentBackup = false

    private init() {}

    func saveSelectedFolder(
        _ result: Result<[URL], Error>,
        records: [StoredJournalRecord],
        context: ModelContext
    ) {
        do {
            guard let folderURL = try result.get().first else {
                status = "没有选择目录。"
                return
            }
            guard folderURL.startAccessingSecurityScopedResource() else {
                status = "系统没有授予该目录访问权限，请重新选择。"
                return
            }
            defer { folderURL.stopAccessingSecurityScopedResource() }

            let bookmark = try folderURL.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            saveBookmark(bookmark)
            folderName = folderURL.lastPathComponent
            snapshots = try BackupDirectoryStore(userSelectedFolderURL: folderURL).listSnapshots()
            status = "目录授权已保存。App 会把记录快照和原图写入此目录下的「干饭手册」文件夹。"

            if !records.isEmpty || BackupChangeTracker().hasPendingChanges {
                backupNow(storedRecords: records, context: context)
            }
        } catch {
            status = "保存目录授权或读取现有备份失败：\(error.localizedDescription)"
        }
    }

    func restoreSavedFolderAccess() {
        guard !folderBookmark.isEmpty else { return }

        do {
            let (folderURL, isStale) = try resolveSavedFolder()
            guard folderURL.startAccessingSecurityScopedResource() else {
                status = "目录授权不可用，请重新选择备份目录。"
                return
            }
            defer { folderURL.stopAccessingSecurityScopedResource() }

            if isStale {
                saveBookmark(try makeBookmark(for: folderURL))
            }
            folderName = folderURL.lastPathComponent
            snapshots = try BackupDirectoryStore(userSelectedFolderURL: folderURL).listSnapshots()
            status = snapshots.isEmpty ? "目录授权已恢复，当前没有可读取的备份快照。" : "目录授权已恢复，找到 \(snapshots.count) 份快照。"
        } catch {
            status = "无法恢复目录授权或读取快照，请重新选择备份目录。\n\(error.localizedDescription)"
        }
    }

    func backupIfNeeded(storedRecords: [StoredJournalRecord], context: ModelContext) {
        guard (storedRecords.contains(where: \.needsBackup) || BackupChangeTracker().hasPendingChanges),
              !folderBookmark.isEmpty else { return }
        if isWorking {
            retryRequestedAfterCurrentBackup = true
            return
        }
        backupNow(storedRecords: storedRecords, context: context)
    }

    func backupNow(storedRecords: [StoredJournalRecord], context: ModelContext) {
        guard !isWorking else { return }

        let records: [JournalRecord]
        do {
            records = try storedRecords.map { try $0.decodeRecord() }
        } catch {
            status = "本机有无法读取的记录，已停止备份以免生成不完整快照。\n\(error.localizedDescription)"
            return
        }

        do {
            let (folderURL, isStale) = try resolveSavedFolder()
            guard folderURL.startAccessingSecurityScopedResource() else {
                throw BackupWorkflowError.authorizationUnavailable
            }
            if isStale {
                saveBookmark(try makeBookmark(for: folderURL))
            }

            let libraryID = currentOrCreateLibraryID()
            let changeTracker = BackupChangeTracker()
            let backupGeneration = changeTracker.generation
            let backupStore = BackupDirectoryStore(userSelectedFolderURL: folderURL)
            let photoStore = AppStoragePaths.photoStore
            isWorking = true
            status = "正在校验本机照片并写入备份快照。"

            Task { @MainActor in
                defer {
                    folderURL.stopAccessingSecurityScopedResource()
                    isWorking = false
                    queueFollowupBackupIfRequested(using: context)
                }

                do {
                    let result = try await Task.detached(priority: .utility) {
                        let catalogState = try MenuCatalogRepository().loadUserState()
                        let snapshot = try BackupSnapshot(
                            libraryID: libraryID,
                            records: records,
                            catalogState: catalogState
                        )
                        var photoData: [UUID: Data] = [:]
                        for asset in snapshot.photos {
                            photoData[asset.id] = try photoStore.load(asset)
                        }
                        return try backupStore.write(snapshot: snapshot, photoData: photoData)
                    }.value

                    snapshots = try backupStore.listSnapshots()
                    if changeTracker.generation == backupGeneration {
                        for storedRecord in storedRecords {
                            storedRecord.needsBackup = false
                        }
                        do {
                            try context.save()
                        } catch {
                            context.rollback()
                            throw error
                        }
                        _ = changeTracker.markBackedUp(ifGenerationMatches: backupGeneration)
                        status = "已写入所选目录：\(result.recordCount) 条记录、\(result.photoCount) 张原图。iCloud 同步状态由系统处理，App 未确认云端上传。"
                    } else {
                        status = "已写入一份快照，但备份期间资料又有变更，仍标记为待备份。iCloud 同步状态由系统处理。"
                    }
                } catch {
                    status = "备份失败，本机记录仍保留且会继续标记为待备份。\n\(error.localizedDescription)"
                }
            }
        } catch {
            status = "无法访问备份目录，记录仍保留在本机。\n\(error.localizedDescription)"
        }
    }

    func requestRestore(_ snapshot: BackupSnapshotSummary) {
        selectedSnapshot = snapshot
        isConfirmingRestore = true
    }

    func restoreSelectedSnapshot(storedRecords: [StoredJournalRecord], context: ModelContext) {
        guard !isWorking else { return }
        guard storedRecords.isEmpty else {
            status = "当前资料库非空，未执行恢复。"
            return
        }
        guard let selectedSnapshot else {
            status = "没有选择快照。"
            return
        }

        do {
            let (folderURL, isStale) = try resolveSavedFolder()
            guard folderURL.startAccessingSecurityScopedResource() else {
                throw BackupWorkflowError.authorizationUnavailable
            }
            if isStale {
                saveBookmark(try makeBookmark(for: folderURL))
            }

            let backupStore = BackupDirectoryStore(userSelectedFolderURL: folderURL)
            let photoStore = AppStoragePaths.photoStore
            isWorking = true
            status = "正在下载并校验快照与全部原图。"

            Task { @MainActor in
                defer {
                    folderURL.stopAccessingSecurityScopedResource()
                    isWorking = false
                }

                do {
                    let archive = try await Task.detached(priority: .utility) {
                        try backupStore.loadSnapshot(named: selectedSnapshot.fileName)
                    }.value
                    try await JournalLibraryRestoreService.restore(
                        archive,
                        photoStore: photoStore,
                        catalogRepository: MenuCatalogRepository(),
                        into: context
                    )

                    saveLibraryID(archive.snapshot.libraryID)
                    let changeTracker = BackupChangeTracker()
                    _ = changeTracker.markBackedUp(ifGenerationMatches: changeTracker.generation)
                    status = "恢复完成：\(archive.snapshot.records.count) 条记录、\(archive.snapshot.photos.count) 张原图。原图已保存在本机，可离线打开。"
                } catch {
                    status = "恢复失败；本机没有新增部分记录。请等待 iCloud 文件下载完成后重试。\n\(error.localizedDescription)"
                }
            }
        } catch {
            status = "无法访问备份目录，未执行恢复。\n\(error.localizedDescription)"
        }
    }

    private func resolveSavedFolder() throws -> (URL, Bool) {
        guard !folderBookmark.isEmpty else {
            throw BackupWorkflowError.noSavedBookmark
        }
        var isStale = false
        let folderURL = try URL(resolvingBookmarkData: folderBookmark, bookmarkDataIsStale: &isStale)
        return (folderURL, isStale)
    }

    private func makeBookmark(for folderURL: URL) throws -> Data {
        try folderURL.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func saveBookmark(_ bookmark: Data) {
        folderBookmark = bookmark
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
    }

    private func currentOrCreateLibraryID() -> UUID {
        if let libraryID = UUID(uuidString: UserDefaults.standard.string(forKey: Self.libraryIDKey) ?? "") {
            return libraryID
        }
        let libraryID = UUID()
        saveLibraryID(libraryID)
        return libraryID
    }

    private func saveLibraryID(_ libraryID: UUID) {
        UserDefaults.standard.set(libraryID.uuidString, forKey: Self.libraryIDKey)
    }

    private func queueFollowupBackupIfRequested(using context: ModelContext) {
        guard retryRequestedAfterCurrentBackup else { return }
        retryRequestedAfterCurrentBackup = false
        guard let latestRecords = try? context.fetch(FetchDescriptor<StoredJournalRecord>()) else { return }
        Task { @MainActor in
            await Task.yield()
            backupIfNeeded(storedRecords: latestRecords, context: context)
        }
    }
}

private enum BackupWorkflowError: LocalizedError {
    case noSavedBookmark
    case authorizationUnavailable

    var errorDescription: String? {
        switch self {
        case .noSavedBookmark:
            "尚未选择备份目录。"
        case .authorizationUnavailable:
            "系统没有授予备份目录访问权限。"
        }
    }
}
