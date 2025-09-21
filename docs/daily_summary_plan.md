# 每日总结提醒与横幅+图表方案（MVP 与扩展）

## 目标与范围
- 在“设置”里支持选择每日提醒时间，触发本地通知提醒用户查看当日总结。
- 在首页“当日日期”下方新增横幅（Banner）入口，展示关键概览，点击进入“每日总结”详情页。
- 详情页可视化展示：当日总使用时长、按应用分布（环形图）、小时维度堆叠柱状图、重要操作列表；支持后续 AI 深度总结。
- 使用时长通过“截图时间序列”近似推算（当前无专门的应用使用统计）。

落点文件：
- 横幅入口： [lib/pages/timeline_page.dart](lib/pages/timeline_page.dart)
- 详情页： [lib/pages/daily_summary_page.dart](lib/pages/daily_summary_page.dart)
- 概览统计服务： [lib/services/daily_summary_service.dart](lib/services/daily_summary_service.dart)
- 通知与排程封装： [lib/services/notification_service.dart](lib/services/notification_service.dart)
- 依赖与配置： [pubspec.yaml](pubspec.yaml)

数据与现有能力参考：
- 截图服务/数据库： [lib/services/screenshot_database.dart](lib/services/screenshot_database.dart)
- 截图记录模型： [lib/models/screenshot_record.dart](lib/models/screenshot_record.dart)
- 事件时间线 UI： [lib/widgets/event_timeline.dart](lib/widgets/event_timeline.dart)
- 设置页： [lib/pages/settings_page.dart](lib/pages/settings_page.dart)

---

## 实施方案选项

### 方案 A（推荐首发，跨平台本地定时通知）
- 使用本地定时通知（Flutter 插件），在用户设定时间展示通知；点击通知打开“每日总结”详情页并加载/展示当日总结。
- 优点：Android/iOS/桌面统一，开发快、稳定性高，免复杂后台。
- 注意：iOS 后台执行受限，通知正文建议使用“概览或占位文案 + 点击查看详情”。

### 方案 B（Android 扩展：定时前后台预生成）
- Android 端在设定时间前 T-5 分钟通过后台任务预生成总结文本，通知直接展示成品内容。
- 优点：更“即点即得”；缺点：仅 Android 稳可控，iOS 仍受限。

### 方案 C（纯前台增量缓存）
- App 回到前台或有新截图入库时，轻量更新“今日概览缓存”；通知只做入口。
- 优点：零后台更稳；缺点：当天若未打开 App，概览可能滞后。

建议路径：先上“方案 A + C（MVP）”，Android 再按需补“方案 B”。

---

## UI 与交互设计

### 横幅（Banner）
- 位置：放置在首页“当日日期”下方（文件： [lib/pages/timeline_page.dart](lib/pages/timeline_page.dart)）。
- 展示信息： 
  - 今日总使用时长（格式如：3h 12m）
  - Top 应用 1–2 个（名称 + 占比/时长）
  - 概要一句话（如：“Longest focus: 1h05m on Notion”）
- 状态：
  - 正常展示：读取“今日概览缓存”，无网络也可展示。
  - 空数据：展示占位引导（如“暂无数据，开始使用吧”）。
- 点击：跳转“每日总结”详情页（文件： [lib/pages/daily_summary_page.dart](lib/pages/daily_summary_page.dart)）。

### 详情页
- 头部：当日总使用时长（大字），日期范围说明（如“统计窗口 04:00~次日 04:00”）。
- 图表区：
  - 环形图（应用占比 TopN + 其他）
  - 小时维度堆叠柱状图（X=小时，Y=分钟，堆叠项=TopN 应用）
- 重要操作列表（规则见后）
- 可选：AI 深度总结卡片（按钮触发或进入后自动加载，复用现有 AI 能力）
- 空数据处理：展示占位和简短引导。

---

## 使用时长推算算法（基于截图时间）

输入数据：
- 当日时间窗口内（默认 04:00~次日 04:00）的截图记录序列，按时间升序；
- 每条记录含时间戳和“归属应用/包名”或能映射到应用标识（依赖当前数据结构）。

核心近似逻辑（稳健 MVP）：
1. 设置“统计窗口”：本地“今日” = 当天 04:00 ~ 次日 04:00（减少跨夜分割的影响）。
2. 对相邻截图 i、i+1，计算 Δt = min(time[i+1] - time[i], cap)。
3. 若 Δt > idleThreshold，则视为 Idle，不计入使用时长。
4. 将 Δt 归属到截图 i 的应用。
5. 去噪：极短抖动（< 5s）可忽略或合并。
6. 产物：
   - 总使用时长（sum of Δt）
   - 应用→时长映射
   - 小时桶分布（供堆叠柱状图）

推荐参数（可配置）：
- cap = 3 分钟（防止跨长间隔高估）
- idleThreshold = 10 分钟（超过视为休息/离开）
- TopN 应用 = 5
- 统计窗口：04:00 ~ 次日 04:00

边界与修正：
- 首尾补偿：首条记录前不推算；末条记录可按 cap 上限补偿但不超过统计窗口末尾。
- 应用识别缺失：记为 Unknown/Other。
- 高频切换：短时间内频繁切换应用，按时间切片累积即可。

---

## 重要操作提取（启发式 + 可叠加 AI 精炼）

启发式规则（MVP）：
- 最长专注段：单应用连续累计时长最长的一段（起止时间、时长）。
- 高频切换时段：单位时间内应用切换次数高的时间窗（如 15 分钟内≥N 次）。
- Top 应用：按当日时长排序 Top3–Top5。
- 深夜使用：23:00~次日 04:00 的使用总时长。
- 长间隔休息：idle > 30 分钟的间隔次数与最大间隔。
- 里程碑：当天最早与最晚活跃时间（第一张与最后一张截图时间）。
- 关键词/主题（若有事件文本/段落摘要）：提取 TopN 关键词或主题，列出高频关键词。

后续可叠加：
- AI 对“重要操作列表”进行文字精炼，生成自然语言总结（支持多语言）。

---

## 数据可视化设计

图表库建议：
- 首选：fl_chart（轻量，社区常用）
- 备选：syncfusion_flutter_charts（功能强，但体量更大）

图表方案：
- 环形图（应用占比）：
  - 标签：App 名 + 占比% + 时长（h:mm）
  - 颜色：为 TopN 应用固定配色，其余为统一“Other”
- 小时堆叠柱状图：
  - X 轴：小时（05~24 或 04~03）
  - Y 轴：分钟
  - 堆叠：TopN 应用；其余合并为“Other”
- 空数据与降级：
  - 显示骨架态/占位图
  - 标签拥挤时仅保留 Top 标签 + 悬浮提示

---

## 通知与排程（MVP）

- 使用跨平台本地通知（建议 flutter_local_notifications + timezone）。
- 首次开启/变更提醒时间：创建/更新每日定时任务（zoned schedule）。
- 权限：
  - iOS/macOS 需申请通知权限；Android 13+ 亦需动态权限。
- 点击通知：打开“每日总结”详情页（路由/参数携带“目标日期”）。
- 开机重排程（Android）：复用开机广播
  - 参考： [android/app/src/main/kotlin/com/fqyw/screen_memo/BootReceiver.kt](android/app/src/main/kotlin/com/fqyw/screen_memo/BootReceiver.kt)

MVP 触发策略：
- 通知正文：短摘要或占位文案 + CTA（“Tap to view your daily summary”）
- 进入页面后加载/展示细节，避免 iOS 后台复杂度。

---

## 默认参数建议（可在设置中调整）
- 默认提醒时间：21:30
- cap：3 分钟
- idle 阈值：10 分钟
- TopN 应用：5
- 统计窗口：04:00 ~ 次日 04:00
- 图表样式：环形图 + 小时堆叠柱状图

---

## 开发任务与文件落点

1) 设置与存储
- 在设置页增加“每日总结提醒(开关) + 提醒时间(选择器)”
  - 文件： [lib/pages/settings_page.dart](lib/pages/settings_page.dart)
- 存储：沿用现有设置服务或新增字段

2) 横幅入口
- 在首页日期下方渲染横幅卡片
  - 文件： [lib/pages/timeline_page.dart](lib/pages/timeline_page.dart)
- 读取“今日概览缓存”，无则占位

3) 概览统计服务
- 读取当日截图记录，执行“使用时长推算 + 重要操作提取”
  - 新文件： [lib/services/daily_summary_service.dart](lib/services/daily_summary_service.dart)
- 产出 DTO：总时长、App 分布、小时桶、重要操作列表

4) 详情页
- 渲染指标 + 图表 + 列表 +（可选）AI 总结卡
  - 新文件： [lib/pages/daily_summary_page.dart](lib/pages/daily_summary_page.dart)

5) 通知与排程封装
- 初始化通道、权限申请、zonedSchedule、重排程
  - 新文件： [lib/services/notification_service.dart](lib/services/notification_service.dart)

6) 依赖与配置
- 添加 fl_chart、flutter_local_notifications、timezone
  - 文件： [pubspec.yaml](pubspec.yaml)

---

## 其他可总结的指标/洞察（可选）
- 专注比：最长专注段 / 总使用时长
- 切换率：单位小时 App 切换次数
- 夜间比例：深夜使用 / 总使用时长
- 对比昨日/近7日：使用上升最快的应用/主题
- 连续达标徽章：连续若干天低于自定义阈值（如社交 < 45 分钟）

---

## 兼容性与边界
- 时区/夏令时：使用 timezone 维护本地时区，变更时重排程。
- 开机自启/重排程：Android 通过 BootReceiver 恢复。
- 省电/厂商优化：通知排程对系统可控；后台预生成仅在 Android 二期尝试。
- 数据缺失/异常：容错 Unknown/Other；空数据兜底 UI。
- 性能：统计逻辑线性处理截图序列，按天范围内复杂度 O(N)。

---

## 里程碑与工期（预估）
- MVP（方案 A + C）：2–4 天（含 UI、存储、通知、概览与图表）
- Android 二期（方案 B）：2–3 天（后台预生成、重排程）
- 验证与打磨：1–2 天（多机型/时区/空数据）

---

## 待确认项
- 是否按“方案 A + C”作为首发路径；
- 默认提醒时间（建议 21:30）；
- 图表样式（建议环形 + 小时堆叠柱）；
- 统计参数：cap=3min、idle=10min、窗口 04:00~次日 04:00；
- Android 二期是否需要后台预生成。
