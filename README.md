<div align="center">

<img src="logo.png" alt="ScreenMemo Logo" width="120"/>

# ScreenMemo

智能截屏备忘录 & 信息管理工具

「屏幕无痕，记忆有痕」

[![Dart](https://img.shields.io/badge/Dart-3.8.1+-0175C2?logo=dart)](https://dart.dev) [![Android](https://img.shields.io/badge/Android-3DDC84?logo=android)](https://www.android.com) [![License](https://img.shields.io/badge/License-Private-red.svg)](LICENSE)

一款基于 Flutter 开发的智能截屏管理应用，帮助你高效捕获、组织和回顾重要信息

[项目简介与应用场景](#项目简介与应用场景) • [功能特性](#功能特性) • [技术架构](#技术架构) • [快速开始](#快速开始) • [构建发布](#构建发布)

</div>

---

## 项目简介与应用场景

ScreenMemo 是一款在本地运行的智能截屏备忘与检索工具：自动记录你在 Android 设备上的屏幕画面，通过 OCR 与 AI 总结让信息可检索、可回顾、可沉淀，帮助你在需要时迅速找回线索、还原上下文。

可以做什么：
- 找回曾在不同 App 里出现过的文字内容（如文章片段、聊天记录、字幕台词等），即使原内容已被撤回或下架，也能在本地历史中检索到。
- 追溯“我看过但想不起来在哪看到”的线索，支持时间范围与应用筛选，快速定位当时屏幕画面。
- 对同一时间段的多张截图进行 AI 总结，形成“每日总结”，用于回顾一天的重点活动、关键操作与内容要点。
- 导出/备份本地资料库，迁移或归档你的“第二记忆”。

典型使用场景：
- 回忆被撤回/删除的消息或页面内容；找回误点关闭的窗口信息。
- 通过关键词检索多日来回出现的台词、术语或关键字段，串联记忆碎片，支持多次出现的统计与回看。
- 复盘重要阶段（如做项目、写毕业设计、准备评审/绩效），用“每日总结”快速回顾当日要点，降低整理成本。
- 用于“记忆寻宝”：翻看以往被忽略的细节或灵感片段，启发创作与决策。

---

## 功能特性

- 无感截屏
- 单应用自定义设置
- 自定义截屏间隔
- 深度链接
- 过期清理
- 智能压缩
- 图片搜索
- 首页统计显示监测天数
- AI事件和每日总结
- 数据导入导出
- 多语言国际化

---

## 性能优化

- AI 对话页面图片点击卡顿优化（2025-10）
  - 将 Markdown 内联证据图片点击的前置数据库与应用列表查询改为“立即导航 + 页面内懒加载”，显著缩短点击到进入查看器的时间。
  - 查看器支持仅传入 `paths`，在页面内部后台补全 `ScreenshotRecord/AppInfo`。
  - 在查看器中对当前与相邻图片执行 `precacheImage`，降低首帧/翻页时解码卡顿。
  - 缩略图组件 `ScreenshotImageWidget` 支持 `targetWidth`，默认用 `ResizeImage(FileImage)` 降低缩略图解码成本。
  - 关键路径添加轻量日志，便于复现与跟踪（Release 下自动降级为 error 级别）。

---

## 快速开始

### 环境要求

- **Flutter SDK**: 3.8.1 或更高版本
- **Dart SDK**: 3.8.1+
- **Android Studio** / **VS Code** + Flutter 插件
- **Android SDK**:
  - 最低版本（minSdkVersion）: 21
  - 目标版本（targetSdkVersion）: 34
- 平台要求：自动截屏功能依赖 Android 11（API 30）及以上（使用无障碍 `takeScreenshot`）
- **JDK**: 11 或更高版本

### 安装步骤

1. **克隆项目**
   ```bash
   git clone <repository-url>
   cd screen_memo
   ```

2. **安装依赖**
   ```bash
   flutter pub get
   ```

3. **生成国际化文件**
   ```bash
   flutter gen-l10n
   ```

4. **运行应用**（开发模式）
   ```bash
   # 连接 Android 设备或启动模拟器
   flutter run
   ```

### 开发命令

```bash
# 构建 Debug APK
flutter build apk --debug

# 安装到设备
flutter install

# 查看日志
adb logcat | findstr "ScreenMemo"  # Windows
adb logcat | grep "ScreenMemo"     # Linux/macOS

# 代码检查
flutter analyze
```

---

## 构建发布

### 一键优化构建（推荐）

生成按 ABI 拆分的优化 APK（体积最小化）：

```powershell
flutter clean
flutter pub get
flutter build apk --release --split-per-abi --tree-shake-icons --obfuscate --split-debug-info=build/symbols
```

**产物位置**：
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` （约 8-9 MB）
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`

### Google Play 上架

使用 App Bundle 格式上传：

```powershell
flutter build appbundle --release --tree-shake-icons --obfuscate --split-debug-info=build/symbols
```

**产物位置**：`build/app/outputs/bundle/release/app-release.aab`

---

## 权限说明

应用需要以下权限以提供完整功能：

| 权限 | 用途 | 必需性 |
|------|------|--------|
| 存储权限 | 保存截屏和数据文件 | 必需 |
| 通知权限 | 展示服务状态与提醒通知 | 必需 |
| 无障碍服务 | 自动截屏与前台应用识别 | 必需 |
| 使用统计权限 | 获取前台应用（Usage Stats） | 必需 |

> 所有权限均在首次运行时引导用户授予，并可随时在系统设置中撤销。

---

## 国际化

当前支持语言：
- 简体中文（默认）
- English
- 日本語
- 한국어

### 添加新语言

1. 在 `lib/l10n/` 目录创建新的 `.arb` 文件（如 `app_ja.arb`）
2. 复制 `app_en.arb` 的内容并翻译
3. 运行 `flutter gen-l10n` 生成代码
4. 在 `LocaleService` 中注册新语言

---

## 贡献指南

欢迎贡献代码、报告问题或提出建议！

1. Fork 本项目
2. 创建特性分支（`git checkout -b feature/AmazingFeature`）
3. 提交更改（`git commit -m 'feat: add some amazing feature'`）
4. 推送到分支（`git push origin feature/AmazingFeature`）
5. 提交 Pull Request

请确保：
- 代码通过 `flutter analyze` 检查
- 添加必要的测试用例
- 更新相关文档

---

## License

本项目为私有项目，未经授权不得使用、复制或分发。

---

## 致谢

感谢以下开源项目：
- [Flutter](https://flutter.dev) - UI 框架
- [Google ML Kit](https://developers.google.com/ml-kit) - 文本识别
- [SQLite](https://www.sqlite.org/) - 数据库引擎
- 所有贡献者和依赖包的维护者

