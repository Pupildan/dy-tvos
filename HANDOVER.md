1. 项目背景与终极目标
纯原生 tvOS 抖音客户端，绝对不使用 WebView 作为 UI。

完全原生的 AVPlayer + 原生焦点遥控器控制。

内容偏好：竖屏内容与横屏比例为 7:3。

追求无限向下刷新，绝对不要卡在 42 条。

2. 环境与构建约束
开发机：Windows，无 Xcode，无本地模拟器。

构建：GitHub Actions (仅编译 CODE_SIGNING_ALLOWED=NO)。

签名推送：本地 Docker 自签推送至 Apple TV，存在 7 天过期问题。

3. 现有架构与技术栈
核心播放器：AVPlayer 已接管。

签名算法：已从 myDV 提取 abogus.js 和 bdms.js，通过 Swift 的 JavaScriptCore (JSC) 实现本地原生签名。

当前数据流：WebView 只做隐藏的数据泵，但目前遇到了无限刷卡死的问题。

4. 已填的坑与避雷指南（极其重要）
403 问题：因为缺少 Referer、Cookie、uifid、x-secsdk-csrf-token 等鉴权头，目前已查明必须在原生请求头中 1:1 补齐。

42 条封印：之前盲目 Hook 网页版 module/feed 接口，池子太小。现已确认必须转向 tab/feed 接口，或者直接使用移动端接口 aweme/v2/feed。

WebView 滚动无效：不要再去试图模拟网页滚动或 Hook IntersectionObserver，网页不可见时事件会死锁。

5. 当前卡点与下一步行动（给下一个 AI 的明确指令）
当前卡点：原生无法实现无限刷。你刚才刚刚发现 myDV 的 classes2.dex 里藏了移动端真实分页路径 aweme/v2/feed，正准备提取它的请求构造，但对话中断了。

下一步必须做的事：下一轮对话，立刻去读本地已经解包好的 myDV 产物（注意：不需要重新下载 JDK/jadx，直接读现有的 .java/.kt 或解压好的源码）。找到 myDV 里请求 tab/feed 或 v2/feed 的完整 Kotlin 函数，提取它的 URL 参数拼接顺序、max_cursor 游标递增逻辑、以及完整的 HTTP Headers。然后 1:1 翻译成 Swift 的 URLSession 请求。