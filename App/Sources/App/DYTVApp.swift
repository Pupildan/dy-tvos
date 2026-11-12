import SwiftUI

/// App 入口。tvOS App 命令场景（无 SceneDelegate，SwiftUI App 生命周期）。
@main
struct DYTVApp: App {
    init() {
        // 启动局域网日志服务器：开发机 curl http://<ATV-IP>:8765/log 拉诊断日志
        DYLog.shared.log("DYTV \(DYBuild.version) launched")
        DYLog.shared.start()

        // 原生直连管线（WebView 泵已退役）：
        // DYSigner(JSC 本地签名) → DYFeedClient(签名直连 feed) → PlaybackEngine → AVPlayer
        PlaybackEngine.shared.onNeedMore = {
            DYFeedClient.shared.fetchPage(initial: false)
        }
        PlaybackEngine.shared.onRefresh = {
            DYFeedClient.shared.refetchCurrent()
        }
        DYFeedClient.shared.start()
    }
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
