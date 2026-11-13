import SwiftData
import SwiftUI

@main
struct GanfanHandbookApp: App {
    private let modelContainer: ModelContainer?
    private let startupError: String?

    init() {
        do {
            modelContainer = try ModelContainer(for: StoredJournalRecord.self)
            startupError = nil
        } catch {
            modelContainer = nil
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                GanfanMainTabView()
                    .modelContainer(modelContainer)
            } else {
                AppStorageErrorView(message: startupError ?? "未知存储错误")
            }
        }
    }
}

private struct AppStorageErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("无法打开本机资料库", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("App 保留了现有文件，没有自动重置资料库。请重新启动 App；如果问题仍在，请先保留设备数据。\n\n\(message)")
        }
    }
}
