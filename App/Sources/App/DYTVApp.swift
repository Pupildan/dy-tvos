import SwiftUI

/// App 入口。tvOS App 命令场景（无 SceneDelegate，SwiftUI App 生命周期）。
@main
struct DYTVApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
