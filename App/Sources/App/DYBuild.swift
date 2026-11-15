import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v181"
    static let changes = "v181: v180真机首屏count=50→n=43/41(40多条✓)但SESSION PAGE-NATIVE PAGING零次,滚动泵触发6次页面自己始终不发翻页请求→「页面原生翻页」路线也判死; ①count 50→100探服务端上限(唯一还能多拿的匿名手段,myDV u11的count由调用方传入) ②新增全端点透视:hook在XHR.open记录所有/aweme/v1/web/ URL(去重+限60/tick),drain打SESSION page-url日志,查页面作者页滚动到底走哪个端点(可能不是aweme/post);同时探测need_time_list=1响应的time_list按年月分组(CAP post TIME LIST),若存在可走time_list_query=1按月取数据绕过翻页墙 ③作品屏文案改「服务端仅开放首批」,去掉误导性的继续下滑自动加载更多"
}
