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
        if model.isWorking { return "正在处理备份" }
        if model.folderBookmark.isEmpty { return "尚未设置备份目录" }
        return pendingCount > 0 || hasPendingLibraryChanges ? "有待备份变更" : "资料库已备份"
    }

    private func snapshotDescription(_ snapshot: BackupSnapshotSummary) -> String {
        if snapshot.includesCatalog {
            return "\(snapshot.recordCount) 条记录 · \(snapshot.photoCount) 张原图 · \(snapshot.brandCount) 个品牌 · \(snapshot.drinkCount) 款饮品 · 营养数据已备份（更新包 \(snapshot.nutritionEntryCount) 条）"
        }
        return "\(snapshot.recordCount) 条记录 · \(snapshot.photoCount) 张原图 · 此旧快照未包含饮品目录和营养数据"
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

                Text("新备份保存在所选目录下的「食光记」文件夹中；已有的「干饭手册」备份仍可读取。")
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

            Section("空间管理") {
                Button {
                    model.prepareCleanupPreview(hasPendingChanges: pendingCount > 0 || hasPendingLibraryChanges)
                } label: {
                    Label("检查并清理旧快照", systemImage: "archivebox")
                }
                .disabled(model.isWorking || model.folderBookmark.isEmpty || pendingCount > 0 || hasPendingLibraryChanges)
                if pendingCount > 0 || hasPendingLibraryChanges {
                    Text("请先完成待备份变更，再清理旧版本。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("保留最近 10 份、近 30 天每天 1 份、近 12 个月每月 1 份；快照至少保存 7 天后才会进入清理候选。清理会一并移除不再被保留快照引用的照片和 Logo。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                            Text(snapshotDescription(snapshot))
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
        .confirmationDialog("清理旧备份？", isPresented: $model.isConfirmingCleanup, titleVisibility: .visible) {
            if let preview = model.cleanupPreview {
                Button("清理 \(preview.snapshotCount) 份快照和 \(preview.orphanedPhotoCount) 个无引用图片", role: .destructive) {
                    model.cleanupOldSnapshots(hasPendingChanges: pendingCount > 0 || hasPendingLibraryChanges)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let preview = model.cleanupPreview {
                Text("预计释放约 \(ByteCountFormatter.string(fromByteCount: preview.estimatedBytesFreed, countStyle: .file))。清理只在新快照已成功写入后执行；App 无法确认 iCloud 上传完成，请先确认云端已有可用备份。")
            }
        }
        .task {
            model.restoreSavedFolderAccess()
        }
    }
}

enum BackupWorkflowHomeFailure: Equatable {
    case directoryUnavailable
    case backupFailed
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
    @Published var isConfirmingCleanup = false
    @Published private(set) var cleanupPreview: BackupCleanupPreview?
    @Published private(set) var folderBookmark = UserDefaults.standard.data(forKey: bookmarkKey) ?? Data()
    @Published private(set) var snapshots: [BackupSnapshotSummary] = []
    @Published private(set) var homeFailure: BackupWorkflowHomeFailure?

    private var selectedSnapshot: BackupSnapshotSummary?
    private var retryRequestedAfterCurrentBackup = false

    private init() {}

    func saveSelectedFolder(
        _ result: Result<[URL], Error>,
        records: [StoredJournalRecord],
        context: ModelContext
    ) {
        let folderURL: URL
        do {
            guard let selectedFolder = try result.get().first else {
                status = "没有选择目录。"
                return
            }
            folderURL = selectedFolder
        } catch {
            status = "保存目录授权或读取现有备份失败：\(error.localizedDescription)"
            return
        }

        guard folderURL.startAccessingSecurityScopedResource() else {
            status = "系统没有授予该目录访问权限，请重新选择。"
            homeFailure = .directoryUnavailable
            return
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        do {
            let bookmark = try folderURL.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            saveBookmark(bookmark)
            folderName = folderURL.lastPathComponent
            snapshots = try BackupDirectoryStore(userSelectedFolderURL: folderURL).listSnapshots()
            homeFailure = nil
            status = "目录授权已保存。App 会把记录快照和原图写入此目录下的「食光记」文件夹；已有的「干饭手册」备份仍可读取。"

            if !records.isEmpty || BackupChangeTracker().hasPendingChanges {
                backupNow(storedRecords: records, context: context)
            }
        } catch {
            status = "保存目录授权或读取现有备份失败：\(error.localizedDescription)"
            homeFailure = .directoryUnavailable
        }
    }

    func restoreSavedFolderAccess() {
        guard !folderBookmark.isEmpty else { return }
        homeFailure = nil

        do {
            let (folderURL, isStale) = try resolveSavedFolder()
            guard folderURL.startAccessingSecurityScopedResource() else {
                status = "目录授权不可用，请重新选择备份目录。"
                homeFailure = .directoryUnavailable
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
            homeFailure = .directoryUnavailable
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
            homeFailure = .backupFailed
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
            let brandLogoStore = AppStoragePaths.brandLogoPhotoStore
            isWorking = true
            homeFailure = nil
            status = "正在校验本机照片并写入备份快照。"

            Task { @MainActor in
                defer {
                    folderURL.stopAccessingSecurityScopedResource()
                    isWorking = false
                    queueFollowupBackupIfRequested(using: context)
                }

                do {
                    let result = try await Task.detached(priority: .utility) {
                        let catalogRepository = MenuCatalogRepository()
                        let catalogState = try catalogRepository.loadUserState()
                        guard let catalogURL = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
                            throw BackupSnapshotError.invalidCatalogManifest
                        }
                        let bundledCatalog = try MenuCatalog.decode(Data(contentsOf: catalogURL))
                        let catalog = try catalogRepository.catalog(from: bundledCatalog)
                        let nutritionDataPack = NutritionUpdateRepository().load()
                        let brandLogoAssets = try AppStoragePaths.brandLogoAssets()
                        let snapshot = try BackupSnapshot(
                            libraryID: libraryID,
                            records: records,
                            catalogState: catalogState,
                            brandLogoAssets: brandLogoAssets,
                            catalog: catalog,
                            nutritionDataPack: nutritionDataPack
                        )
                        var photoData: [UUID: Data] = [:]
                        for asset in snapshot.photos {
                            photoData[asset.id] = try photoStore.load(asset)
                        }
                        var brandLogoData: [UUID: Data] = [:]
                        for asset in snapshot.brandLogoAssets ?? [] {
                            brandLogoData[asset.id] = try brandLogoStore.load(asset)
                        }
                        return try backupStore.write(
                            snapshot: snapshot,
                            photoData: photoData,
                            brandLogoData: brandLogoData
                        )
                    }.value

                    snapshots = try backupStore.listSnapshots()
                    homeFailure = nil
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
                        let snapshotResult = result.didCreateSnapshot ? "已写入新快照" : "内容未变化，沿用已有快照"
                        status = "\(snapshotResult)：\(result.recordCount) 条记录、\(result.photoCount) 张原图、\(result.brandLogoCount) 个自定义图案、\(result.brandCount) 个品牌、\(result.drinkCount) 款饮品目录和营养数据（更新包 \(result.nutritionEntryCount) 条）。iCloud 同步状态由系统处理，App 未确认云端上传。"
                    } else {
                        status = result.didCreateSnapshot
                            ? "已写入一份快照，但备份期间资料又有变更，仍标记为待备份。iCloud 同步状态由系统处理。"
                            : "资料在校验期间又有变更，仍标记为待备份；本次内容与已有快照相同，没有新增文件。"
                    }
                } catch {
                    status = "备份失败，本机记录仍保留且会继续标记为待备份。\n\(error.localizedDescription)"
                    homeFailure = .backupFailed
                }
            }
        } catch {
            status = "无法访问备份目录，记录仍保留在本机。\n\(error.localizedDescription)"
            homeFailure = .directoryUnavailable
        }
    }

    func prepareCleanupPreview(hasPendingChanges: Bool) {
        guard !isWorking, !hasPendingChanges, !folderBookmark.isEmpty else {
            if hasPendingChanges { status = "请先完成待备份变更，再清理旧版本。" }
            return
        }
        isWorking = true
        status = "正在检查可清理的旧快照。"
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let (folderURL, isStale) = try resolveSavedFolder()
                guard folderURL.startAccessingSecurityScopedResource() else {
                    throw BackupWorkflowError.authorizationUnavailable
                }
                defer { folderURL.stopAccessingSecurityScopedResource() }
                if isStale { saveBookmark(try makeBookmark(for: folderURL)) }
                let store = BackupDirectoryStore(userSelectedFolderURL: folderURL)
                let preview = try await Task.detached(priority: .utility) { try store.previewCleanup() }.value
                cleanupPreview = preview
                if preview.snapshotCount == 0 && preview.orphanedPhotoCount == 0 {
                    status = "当前没有达到清理条件的旧快照或无引用图片。"
                } else {
                    isConfirmingCleanup = true
                    status = "找到可清理项目：\(preview.snapshotCount) 份快照、\(preview.orphanedPhotoCount) 个无引用图片。"
                }
            } catch {
                if error as? BackupDirectoryStoreError == .cleanupRequiresVerifiedSnapshot {
                    status = "最新快照或附件无法校验，未提供清理候选；请先检查备份目录。"
                } else {
                    status = "检查旧快照失败，未删除任何文件。\n\(error.localizedDescription)"
                }
            }
        }
    }

    func cleanupOldSnapshots(hasPendingChanges: Bool) {
        guard !isWorking, !hasPendingChanges, !folderBookmark.isEmpty else {
            if hasPendingChanges { status = "请先完成待备份变更，再清理旧版本。" }
            return
        }
        guard let expectedPreview = cleanupPreview else {
            status = "清理预览已失效，请重新检查。"
            return
        }
        isWorking = true
        status = "正在清理已确认的旧快照。"
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let (folderURL, isStale) = try resolveSavedFolder()
                guard folderURL.startAccessingSecurityScopedResource() else {
                    throw BackupWorkflowError.authorizationUnavailable
                }
                defer { folderURL.stopAccessingSecurityScopedResource() }
                if isStale { saveBookmark(try makeBookmark(for: folderURL)) }
                let store = BackupDirectoryStore(userSelectedFolderURL: folderURL)
                let result = try await Task.detached(priority: .utility) {
                    try store.cleanupOldSnapshots(matching: expectedPreview)
                }.value
                snapshots = try store.listSnapshots()
                cleanupPreview = nil
                status = "清理完成：移除 \(result.snapshotCount) 份快照和 \(result.orphanedPhotoCount) 个无引用图片，预计释放约 \(ByteCountFormatter.string(fromByteCount: result.estimatedBytesFreed, countStyle: .file))。请在「文件」App 确认 iCloud 同步状态。"
            } catch {
                if error as? BackupDirectoryStoreError == .cleanupPlanChanged {
                    cleanupPreview = nil
                    status = "备份目录在预览后发生变化，没有删除文件；请重新检查。"
                } else if error as? BackupDirectoryStoreError == .cleanupRequiresVerifiedSnapshot {
                    cleanupPreview = nil
                    status = "最新快照或附件无法校验，没有删除文件；请先检查备份目录。"
                } else {
                    status = "清理失败，保留剩余文件。\n\(error.localizedDescription)"
                }
            }
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
            let brandLogoStore = AppStoragePaths.brandLogoPhotoStore
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
                        brandLogoStore: brandLogoStore,
                        nutritionRepository: NutritionUpdateRepository(),
                        into: context
                    )

                    saveLibraryID(archive.snapshot.libraryID)
                    let changeTracker = BackupChangeTracker()
                    _ = changeTracker.markBackedUp(ifGenerationMatches: changeTracker.generation)
                    let catalogSummary = archive.snapshot.catalog.map {
                        "\($0.brands.count) 个品牌、\($0.drinks.count) 款饮品及营养数据（更新包 \(archive.snapshot.nutritionDataPack?.entries.count ?? 0) 条）"
                    } ?? "此旧快照未包含饮品目录和营养数据"
                    status = "恢复完成：\(archive.snapshot.records.count) 条记录、\(archive.snapshot.photos.count) 张原图、\((archive.snapshot.brandLogoAssets ?? []).count) 个自定义图案、\(catalogSummary)。图片与菜单数据已保存在本机，可离线使用。"
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
