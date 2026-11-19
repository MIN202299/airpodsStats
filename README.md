# AirPods 佩戴统计（耳机统计）

一个 SwiftUI iOS 应用，读取「健康」App 里的耳机历史，统计 AirPods 的佩戴时长。界面仿照参考截图：蓝黑网格背景、圆角卡片、白色渐变柱形图。

## 功能

**统计页**
- 个人纪录：单日佩戴最长、单次佩戴最长（含起止时间）、连续记录最长（天数 + 日期范围）、单月佩戴最长
- 最常戴耳机：设备名称 + 累计佩戴时长
- 周 / 月 / 年 / 总共 切换，左右箭头切换周期（点标题回到当前周期），切换栏滚动时吸顶
- 累计佩戴时长：总时长、和上一周期对比（如“较前一年 +1305 h 1 min”）、柱形图（Y 轴在右侧，以 h/min 显示），轻点柱形查看明细
- 周期概览：有记录日平均、有记录天数 / 周期总天数、周期最长单日、佩戴次数
- 右上角筛选：全部耳机 / 仅 AirPods / 任选几副耳机

**今天页**：今日佩戴时长（和昨天对比）、24 小时分布、今日次数 / 最长一次 / 本周累计 / 近 7 日平均、近 7 天柱形图、今日佩戴记录列表

**设备页**（深紫夜空风格）
- 顶部右侧切换时间范围：近7天 / 近30天 / 本周 / 本月 / 全部；左侧齿轮进入设置
- 中间是缓慢旋转、闪烁的粒子球，显示该范围的总佩戴时长（开启“减弱动态效果”时会静止）
- 下方是可以左右滑动的玻璃质感设备卡片：耳机名称、产品图、时长、在总佩戴时长中的占比；底部有分页圆点
- 轻点卡片进入详情；长按卡片可以查看记录、重命名、只统计这副耳机

**设备详情页**：所选周期的时长和占比卡片；“所选周期 · 厂商 · 型号”；累计聆听时长（历史起止日期、有记录天数）；累计佩戴次数、平均每次、最长一次、平均音量 dB(A)；近 30 天聆听趋势柱形图；右上角“编辑”可以重命名

**设置**（设备页左上角）：数据来源（健康 App / 示例数据）、会话合并间隔、重新读取历史

## 数据从哪里来

iOS 不开放 AirPods 的入耳检测记录。本应用使用 HealthKit 的 **耳机音频级别**（`HKQuantityType(.headphoneAudioExposure)`）样本：耳机播放音频时，系统会持续写入带设备信息（如 “AirPods Pro”）的样本，并长期保存历史。处理流程：

1. 读取全部样本，按设备分组（名称 + 型号 + 本地标识）
2. 同一设备相邻样本间隔 ≤ N 分钟（默认 5，可调）的合并成一次“佩戴会话”
3. 跨午夜的会话按天拆开，再计算日 / 月 / 年统计和各项纪录

所以统计的是“戴着耳机播放音频的时长”：只开降噪、不放音频的时段不会被记录，也就是界面上写的 **“无记录不等于未佩戴”**。所有计算都在本机完成。

## 运行

需要 Xcode 16 或更高版本，系统要求 iOS 17 及以上。

1. 打开 `AirPodsStats.xcodeproj`
2. 在 *Signing & Capabilities* 里选择你的 Team，并把 Bundle Identifier 改成你自己的（默认是 `com.example.airpodsstats`）
3. 运行到真机，首次启动时允许读取“耳机音频级别”
4. 模拟器里没有耳机数据，可以在 设备 → 数据来源 切到“示例数据”预览界面

如果工程打不开，可以用 XcodeGen 重新生成：`brew install xcodegen && xcodegen generate`。

如果读不到数据：检查 健康 → 共享 → App → 耳机统计 是否打开了“耳机音频级别”，以及 设置 → 健康 → 耳机音频级别 是否开启。

## 代码结构

```
AirPodsStats/
  App/          入口 + TabView
  Models/       RawSample / WearSession / HeadphoneDevice / PeriodKind
  Analytics/    SessionBuilder（样本 → 会话）、StatsEngine（全部统计）、Formatting
  Services/     HealthKitService、DemoDataGenerator、SessionCache、UsageStore
  Views/        Components（主题、卡片、柱形图）、Stats、Today、Devices
Config/AirPodsStats.entitlements   HealthKit 权限
```

`StatsEngine` 只做纯计算，不依赖 UI 和 HealthKit，方便单独测试。
