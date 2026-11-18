import SwiftData
import SwiftUI

@main
struct GanfanHandbookApp: App {
    private let startupError: String?
    @StateObject private var bootstrap: JournalAppBootstrapModel

    init() {
        let databaseExists = FileManager.default.fileExists(atPath: JournalDatabasePaths.libraryURL().path)
        if databaseExists {
            startupError = nil
            _bootstrap = StateObject(wrappedValue: JournalAppBootstrapModel(legacyContainer: nil))
        } else {
            do {
                let container = try ModelContainer(for: StoredJournalRecord.self)
                startupError = nil
                _bootstrap = StateObject(wrappedValue: JournalAppBootstrapModel(legacyContainer: container))
            } catch {
                startupError = error.localizedDescription
                _bootstrap = StateObject(wrappedValue: JournalAppBootstrapModel(legacyContainer: nil))
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let startupError {
                AppStorageErrorView(message: startupError)
            } else if let library = bootstrap.library {
                GanfanMainTabView()
                    .environment(\.journalSQLiteStore, library)
            } else if let error = bootstrap.error {
                AppStorageErrorView(message: error, retry: { Task { await bootstrap.start() } })
            } else {
                JournalMigrationProgressView(progress: bootstrap.progress, total: bootstrap.total)
                    .task { await bootstrap.start() }
            }
        }
    }
}

@MainActor
private final class JournalAppBootstrapModel: ObservableObject {
    @Published private(set) var library: JournalSQLiteStore?
    @Published private(set) var error: String?
    @Published private(set) var progress = 0
    @Published private(set) var total = 0

    private let legacyContainer: ModelContainer?
    private var isStarting = false

    init(legacyContainer: ModelContainer?) {
        self.legacyContainer = legacyContainer
    }

    func start() async {
        guard !isStarting else { return }
        isStarting = true
        error = nil
        do {
            library = try await JournalDatabaseBootstrapper.open(
                at: JournalDatabasePaths.libraryURL(),
                migratingFrom: legacyContainer,
                progress: { [weak self] complete, total in
                    self?.progress = complete
                    self?.total = total
                }
            )
        } catch {
            self.error = error.localizedDescription
        }
        isStarting = false
    }

}

private struct JournalMigrationProgressView: View {
    let progress: Int
    let total: Int

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: total > 0 ? Double(progress) : nil, total: Double(max(total, 1)))
                .frame(maxWidth: 260)
            Text(total > 0 ? "正在安全整理本机记录（\(progress)/\(total)）" : "正在检查本机资料库")
                .font(.headline)
            Text("首次整理期间会保留旧资料库；请保持 App 打开。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GanfanPalette.canvas)
    }
}

private struct AppStorageErrorView: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label("无法打开本机资料库", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("App 保留了现有文件，没有自动重置资料库。请重新启动 App；如果问题仍在，请先保留设备数据。\n\n\(message)")
        } actions: {
            if let retry {
                Button("重试", action: retry)
            }
        }
    }
}

private struct JournalSQLiteStoreEnvironmentKey: EnvironmentKey {
    static let defaultValue: JournalSQLiteStore? = nil
}

extension EnvironmentValues {
    var journalSQLiteStore: JournalSQLiteStore? {
        get { self[JournalSQLiteStoreEnvironmentKey.self] }
        set { self[JournalSQLiteStoreEnvironmentKey.self] = newValue }
    }
}
