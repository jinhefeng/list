import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let ganfanLibraryBackupStateChanged = Notification.Name("ganfanLibraryBackupStateChanged")
    static let ganfanJournalRecordsRestored = Notification.Name("ganfanJournalRecordsRestored")
}

struct BackupSettingsView: View {
    @Environment(\.journalSQLiteStore) private var library
    @AppStorage(BackupChangeTracker.generationKey) private var libraryChangeGeneration = 0
    @AppStorage(BackupChangeTracker.pendingKey) private var hasPendingLibraryChanges = false
    @StateObject private var model = BackupWorkflowModel.shared
    @State private var recordCount = 0
    @State private var pendingCount = 0
    @State private var legacyIssueCount = 0
    private var libraryIsEmpty: Bool { recordCount == 0 && legacyIssueCount == 0 }

    private var backupStatus: String {
        if model.isWorking { return "正在处理备份" }
        if model.folderBookmark.isEmpty { return "尚未设置备份目录" }
        return pendingCount > 0 || hasPendingLibraryChanges ? "有待备份变更" : "资料库已备份"
    }

    private func snapshotDescription(_ snapshot: BackupSnapshotSummary) -> String {
        let recordText = snapshot.legacyIssueCount == 0
            ? "\(snapshot.recordCount) 条记录"
            : "\(snapshot.recordCount) 条可读取记录 · \(snapshot.legacyIssueCount) 条旧记录原样保留"
        if snapshot.includesCatalog {
            return "\(recordText) · \(snapshot.photoCount) 张原图 · \(snapshot.brandCount) 个品牌 · \(snapshot.drinkCount) 款饮品 · 营养数据已备份（更新包 \(snapshot.nutritionEntryCount) 条）"
        }
        return "\(recordText) · \(snapshot.photoCount) 张原图 · 此旧快照未包含饮品目录和营养数据"
    }

    var body: some View {
        Form {
            Section {
                GanfanCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(backupStatus, systemImage: model.isWorking ? "arrow.triangle.2.circlepath.icloud" : "externaldrive")
                            .font(.headline)
                            .foregroundStyle(model.folderBookmark.isEmpty || pendingCount > 0 || hasPendingLibraryChanges ? GanfanPalette.leaf : GanfanPalette.forest)
                        Text("\(recordCount + legacyIssueCount) 条记录 · \(pendingCount) 条待备份")
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

                Text("新备份保存在所选目录下的「吃吃喝喝」文件夹中；已有的「食光记」或「干饭手册」备份仍可读取。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("本机资料库") {
                LabeledContent("记录数", value: "\(recordCount + legacyIssueCount)")
                LabeledContent("待备份记录", value: "\(pendingCount)")
                LabeledContent("资料库变更", value: hasPendingLibraryChanges ? "待备份" : "已备份")

                Button {
                    if let library { model.backupNow(library: library) }
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
                            .disabled(model.isWorking || !libraryIsEmpty)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !libraryIsEmpty {
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
                if let library { model.saveSelectedFolder(result, library: library) }
            }
        )
        .confirmationDialog("恢复这份备份？", isPresented: $model.isConfirmingRestore, titleVisibility: .visible) {
            Button("恢复到空资料库", role: .destructive) {
                if let library { model.restoreSelectedSnapshot(library: library) }
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
            await refreshCounts()
        }
        .task(id: libraryChangeGeneration) { await refreshCounts() }
        .onReceive(NotificationCenter.default.publisher(for: .ganfanLibraryBackupStateChanged)) { _ in
            Task { await refreshCounts() }
        }
    }

    private func refreshCounts() async {
        guard let library else { return }
        do {
            let result = try await Task.detached(priority: .utility) {
                (try library.count(), try library.pendingBackupCount(), try library.legacyIssueCount())
            }.value
            recordCount = result.0
            pendingCount = result.1
            legacyIssueCount = result.2
        } catch {
            model.status = "无法读取资料库摘要：\(error.localizedDescription)"
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
        library: JournalSQLiteStore
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
            status = "目录授权已保存。App 会把记录快照和原图写入此目录下的「吃吃喝喝」文件夹；已有的「食光记」或「干饭手册」备份仍可读取。"

            let recordCount = try library.count()
            let legacyIssueCount = try library.legacyIssueCount()
            if recordCount > 0 || legacyIssueCount > 0 || BackupChangeTracker().hasPendingChanges {
                backupNow(library: library)
            }
        } catch {
            status = "保存目录授权或读取现有备份失败：\(error.localizedDescription)"
            homeFailure = .directoryUnavailable
        }
    }

    func restoreSavedFolderAccess() {
        guard !folderBookmark.isEmpty else { return }
        homeFailure = nil
        var activeFolderURL: URL?

        do {
            let (folderURL, isStale) = try resolveSavedFolder()
            guard folderURL.startAccessingSecurityScopedResource() else {
                status = "目录授权不可用，请重新选择备份目录。"
                homeFailure = .directoryUnavailable
                return
            }
            activeFolderURL = folderURL

            if isStale {
                saveBookmark(try makeBookmark(for: folderURL))
            }
            folderName = folderURL.lastPathComponent
            let store = BackupDirectoryStore(userSelectedFolderURL: folderURL)
            status = "目录授权已恢复，正在读取备份快照。"
            Task { @MainActor in
                defer { folderURL.stopAccessingSecurityScopedResource() }
                do {
                    let loadedSnapshots = try await Task.detached(priority: .utility) {
                        try store.listSnapshots()
                    }.value
                    snapshots = loadedSnapshots
                    status = loadedSnapshots.isEmpty
                        ? "目录授权已恢复，当前没有可读取的备份快照。"
                        : "目录授权已恢复，找到 \(loadedSnapshots.count) 份快照。"
                } catch {
                    status = "无法读取备份快照，请重新选择备份目录。\n\(error.localizedDescription)"
                    homeFailure = .directoryUnavailable
                }
            }
            activeFolderURL = nil
        } catch {
            activeFolderURL?.stopAccessingSecurityScopedResource()
            status = "无法恢复目录授权或读取快照，请重新选择备份目录。\n\(error.localizedDescription)"
            homeFailure = .directoryUnavailable
        }
    }

    func backupIfNeeded(library: JournalSQLiteStore) {
        guard !folderBookmark.isEmpty else { return }
        let pendingCount = (try? library.pendingBackupCount()) ?? 0
        guard pendingCount > 0 || BackupChangeTracker().hasPendingChanges else { return }
        if isWorking {
            retryRequestedAfterCurrentBackup = true
            return
        }
        backupNow(library: library)
    }

    func backupNow(library: JournalSQLiteStore) {
        guard !isWorking else { return }
        var activeFolderURL: URL?

        do {
            let (folderURL, isStale) = try resolveSavedFolder()
            guard folderURL.startAccessingSecurityScopedResource() else {
                throw BackupWorkflowError.authorizationUnavailable
            }
            activeFolderURL = folderURL
            if isStale {
                saveBookmark(try makeBookmark(for: folderURL))
            }

            let libraryID = currentOrCreateLibraryID()
            let changeTracker = BackupChangeTracker()
            let backupGeneration = changeTracker.generation
            let databaseGeneration = library.dataGeneration
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
                    queueFollowupBackupIfRequested(using: library)
                }

                do {
                    let records = try await Task.detached(priority: .utility) {
                        try library.allRecords().map(\.record)
                    }.value
                    guard library.dataGeneration == databaseGeneration else {
                        throw JournalSQLiteStoreError.sqliteFailure("备份期间资料库发生变化，请重新备份。")
                    }
                    let result = try await Task.detached(priority: .utility) {
                        let catalogRepository = MenuCatalogRepository()
                        guard let catalogURL = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
                            throw BackupSnapshotError.invalidCatalogManifest
                        }
                        let bundledCatalog = try MenuCatalog.decode(Data(contentsOf: catalogURL))
                        let catalog = try catalogRepository.catalog(from: bundledCatalog)
                        let catalogState = try catalogRepository.loadUserState()
                        let nutritionDataPack = NutritionUpdateRepository().load()
                        let brandLogoAssets = try AppStoragePaths.brandLogoAssets()
                        let snapshot = try BackupSnapshot(
                            libraryID: libraryID,
                            records: records,
                            catalogState: catalogState,
                            brandLogoAssets: brandLogoAssets,
                            catalog: catalog,
                            nutritionDataPack: nutritionDataPack,
                            preserveRecordPrecision: true
                        )
                        var photoData: [UUID: Data] = [:]
                        for asset in snapshot.photos {
                            photoData[asset.id] = try photoStore.load(asset)
                        }
                        var brandLogoData: [UUID: Data] = [:]
                        for asset in snapshot.brandLogoAssets ?? [] {
                            brandLogoData[asset.id] = try brandLogoStore.load(asset)
                        }
                        return try backupStore.writeSQLite(
                            snapshot: snapshot,
                            library: library,
                            changeGeneration: backupGeneration,
                            databaseGeneration: databaseGeneration,
                            photoData: photoData,
                            brandLogoData: brandLogoData
                        )
                    }.value

                    snapshots = try await Task.detached(priority: .utility) {
                        try backupStore.listSnapshots()
                    }.value
                    homeFailure = nil
                    if changeTracker.generation == backupGeneration,
                       try library.markAllBackedUp(ifDataGenerationMatches: databaseGeneration),
                       changeTracker.markBackedUp(ifGenerationMatches: backupGeneration) {
                        NotificationCenter.default.post(name: .ganfanLibraryBackupStateChanged, object: nil)
                        let snapshotResult = result.didCreateSnapshot ? "已写入新快照" : "内容未变化，沿用已有快照"
                        let legacyText = result.legacyIssueCount == 0 ? "" : "、\(result.legacyIssueCount) 条无法解析的旧记录已原样保留"
                        status = "\(snapshotResult)：\(result.recordCount) 条可读取记录\(legacyText)、\(result.photoCount) 张原图、\(result.brandLogoCount) 个自定义图案、\(result.brandCount) 个品牌、\(result.drinkCount) 款饮品目录和营养数据（更新包 \(result.nutritionEntryCount) 条）。iCloud 同步状态由系统处理，App 未确认云端上传。"
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
            activeFolderURL = nil
        } catch {
            activeFolderURL?.stopAccessingSecurityScopedResource()
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

    func restoreSelectedSnapshot(library: JournalSQLiteStore) {
        guard !isWorking else { return }
        guard let counts = try? library.migrationCounts(), counts.records == 0, counts.legacy == 0 else {
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
                var temporaryDatabaseSnapshotURL: URL?
                defer {
                    folderURL.stopAccessingSecurityScopedResource()
                    if let temporaryDatabaseSnapshotURL {
                        try? FileManager.default.removeItem(at: temporaryDatabaseSnapshotURL)
                    }
                    isWorking = false
                }

                do {
                    let archive = try await Task.detached(priority: .utility) {
                        try backupStore.loadSnapshot(named: selectedSnapshot.fileName)
                    }.value
                    temporaryDatabaseSnapshotURL = archive.databaseSnapshotURL
                    try await JournalLibraryRestoreService.restore(
                        archive,
                        photoStore: photoStore,
                        catalogRepository: MenuCatalogRepository(),
                        brandLogoStore: brandLogoStore,
                        nutritionRepository: NutritionUpdateRepository(),
                        into: library
                    )
                    saveLibraryID(archive.snapshot.libraryID)
                    let changeTracker = BackupChangeTracker()
                    _ = changeTracker.markBackedUp(ifGenerationMatches: changeTracker.generation)
                    let catalogSummary = archive.snapshot.catalog.map {
                        "\($0.brands.count) 个品牌、\($0.drinks.count) 款饮品及营养数据（更新包 \(archive.snapshot.nutritionDataPack?.entries.count ?? 0) 条）"
                    } ?? "此旧快照未包含饮品目录和营养数据"
                    NotificationCenter.default.post(name: .ganfanJournalRecordsRestored, object: nil)
                    NotificationCenter.default.post(name: .ganfanLibraryBackupStateChanged, object: nil)
                    let restoredCounts = try library.migrationCounts()
                    let legacyText = restoredCounts.legacy == 0 ? "" : "，另有 \(restoredCounts.legacy) 条无法解析的旧记录已原样保留"
                    status = "恢复完成：\(restoredCounts.records) 条可读取记录\(legacyText)、\(archive.snapshot.photos.count) 张原图、\((archive.snapshot.brandLogoAssets ?? []).count) 个自定义图案、\(catalogSummary)。图片与菜单数据已保存在本机，可离线使用。"
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

    private func queueFollowupBackupIfRequested(using library: JournalSQLiteStore) {
        guard retryRequestedAfterCurrentBackup else { return }
        retryRequestedAfterCurrentBackup = false
        Task { @MainActor in
            await Task.yield()
            backupIfNeeded(library: library)
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
