import SwiftUI

@main
struct QuizLockApp: App {
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase) {
            // アプリのライフサイクルに応じて制限同期を開始/停止
            switch scenePhase {
            case .active:
                // フォアグラウンドに戻ったとき
                model.syncBlocking()
                model.startRestrictionSync()
            case .background, .inactive:
                // バックグラウンドに移行したとき
                model.stopRestrictionSync()
            @unknown default:
                break
            }
        }
    }
}
