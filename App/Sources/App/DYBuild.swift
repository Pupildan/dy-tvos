import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v144"
    static let changes = "v144: PC版UI按用户测试反馈修正——①去左下 desc/话题重复(desc 剔除话题串,话题独立行);②话题与标题分不同行;③标题 numberOfLines=3 自动换行;④去右轨上下箭头;⑤去左下头像(保留右轨头像);⑥昵称字号32>标题26;⑦昵称后显示发布时间(f16/create_time 格式化 MM月dd日)"
}
