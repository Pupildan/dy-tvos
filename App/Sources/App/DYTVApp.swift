import SwiftUI

/// App 入口。tvOS App 命令场景（无 SceneDelegate，SwiftUI App 生命周期）。
@main
struct DYTVApp: App {
    init() {
        // 启动局域网日志服务器：开发机 curl http://<ATV-IP>:8765/log 拉诊断日志
        DYLog.shared.log("DYTV \(DYBuild.version) launched")
        DYLog.shared.start()

        // 原生直连管线（泵捕获模板 → DYSigner 签名 → URLSession 直连 → 引擎合并）：
        PlaybackEngine.shared.onNeedMore = {
            DYFeedClient.shared.fetchNativePage(initial: false)
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
