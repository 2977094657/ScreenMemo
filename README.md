<div align="center">

<img src="logo.png" alt="ScreenMemo Logo" width="120"/>

# ScreenMemo

本地运行的智能截屏备忘与检索工具：自动记录 Android 屏幕，通过 OCR 与 AI 助手让内容可检索、可回顾。

「屏幕无痕，记忆有痕」

[![Dart](https://img.shields.io/badge/Dart-3.8.1+-0175C2?logo=dart)](https://dart.dev) [![Android](https://img.shields.io/badge/Android-3DDC84?logo=android)](https://www.android.com) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE) [![QQ 群](https://img.shields.io/badge/QQ-%E5%B1%8F%E5%BF%86%20640740880-12B7F5?logo=tencentqq&logoColor=white)](https://qm.qq.com/q/ob2NMRDzna) [<img src="https://gh-down-badges.linkof.link/2977094657/ScreenMemo" alt="Downloads" />](https://github.com/2977094657/ScreenMemo/releases)

</div>

<p align="center">
  <b>语言</b>:
  简体中文 |
  <a href="README.en.md">English</a> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.ko.md">한국어</a>
</p>

---

## 项目概览

ScreenMemo 是一款在本地运行的智能截屏备忘与检索工具：自动记录你在 Android 设备上的屏幕画面，通过 OCR 与 AI 助手让信息可检索，帮助你在需要时迅速找回线索、还原上下文。

### 从今天开始构建你的个人数字记忆

**为什么现在就要开始？**

- **不可逆的知识流失**：当越来越多人开始用日常数据喂养个人 AI，每一天的未曾记录，都在让你未来的 AI 助手少了一分“懂你”的底气。
- **悄然拉开的时间复利**：数据无法速成。今天就开始沉淀数字标本的人，在未来 AI 迎来质变时，将天然拥有一座别人难以追赶的专属记忆库。
- **打捞散落的数字自我**：你最宝贵的上下文往往碎落在不同的 App 与设备里；如果没有 ScreenMemo 去妥善收留，它们终将随流逝的时间消散，再难被完整唤醒。

## 应用截图

下面展示的是一些高频页面截图，更多细节和页面没有一一展开，欢迎体验。

<table>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/home-overview.jpg" alt="首页概览" width="240" loading="lazy" />
      <div align="center"><sub>首页概览</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/search-semantic-results.jpg" alt="语义搜索" width="240" loading="lazy" />
      <div align="center"><sub>语义搜索</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/timeline-replay-generation.jpg" alt="时间线与回放" width="240" loading="lazy" />
      <div align="center"><sub>时间线与回放</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/event-detail.jpg" alt="Activity 详情" width="240" loading="lazy" />
      <div align="center"><sub>Activity 详情</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/favorites-notes.jpg" alt="收藏与备注" width="240" loading="lazy" />
      <div align="center"><sub>收藏与备注</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/settings-overview.jpg" alt="设置总览" width="240" loading="lazy" />
      <div align="center"><sub>设置总览</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/daySummary.jpg" alt="每日总结" width="240" loading="lazy" />
      <div align="center"><sub>每日总结</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/storage-analysis.jpg" alt="存储分析" width="240" loading="lazy" />
      <div align="center"><sub>存储分析</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/ai-review-chat.jpg" alt="AI 回顾对话" width="240" loading="lazy" />
      <div align="center"><sub>AI 回顾对话</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/addAi.jpg" alt="AI 提供商" width="240" loading="lazy" />
      <div align="center"><sub>AI 提供商</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/prompt.jpg" alt="Prompt 管理" width="240" loading="lazy" />
      <div align="center"><sub>Prompt 管理</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/nsfw-search-results.jpg" alt="NSFW 搜索结果" width="240" loading="lazy" />
      <div align="center"><sub>NSFW 搜索结果</sub></div>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top">
      <img src="assets/screenshots/ai-sensitive-content-analysis.jpg" alt="敏感内容分析" width="240" loading="lazy" />
      <div align="center"><sub>敏感内容分析</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/ai-tool-calling-report.jpg" alt="AI 工具调用报告" width="240" loading="lazy" />
      <div align="center"><sub>AI 工具调用报告</sub></div>
    </td>
    <td align="center" valign="top">
      <img src="assets/screenshots/deep-link-entry.jpg" alt="深度链接" width="240" loading="lazy" />
      <div align="center"><sub>深度链接</sub></div>
    </td>
  </tr>
</table>

## 快速开始

### 普通用户

如果你只是想在手机上使用 ScreenMemo，推荐直接安装 GitHub Releases 中已经构建好的 APK

1. 打开 [GitHub Releases](https://github.com/2977094657/ScreenMemo/releases)，进入最新版本。
2. 在 **Assets** 中下载适合手机的 `screen_memo-...-app-*-release.apk` 安装包。大多数近几年的 Android 手机优先选择 `arm64-v8a`；

### 开发者

#### 环境要求

- **Flutter SDK**：`3.35.7`（当前 CI 验证版本）
- **Dart SDK**：`3.9.2`（随 Flutter `3.35.7` 提供；项目约束为 `>=3.8.1`）
- **JDK**：推荐 `17`（CI 使用 `17`；Android 代码仍以 Java 11 字节码为目标）
- **Android SDK**：发布工作流使用 `Platform 36`、`Build-Tools 36.0.0`、`NDK 27.0.12077973`
- **APK 当前构建配置**：`minSdk 24`、`targetSdk 36`
- **主功能平台要求**：自动截屏依赖 Android 11（API 30）及以上
- **截屏间隔**：默认与最低值已调整为 `1` 秒，截图采集与后处理在后台异步执行，不会阻塞下一次截屏触发
- **IDE**：Android Studio / VS Code + Flutter 插件

#### 安装与运行

1. **克隆项目**
   ```bash
   git clone <repository-url>
   cd screen_memo
   ```

2. **安装依赖**
   ```bash
   flutter pub get
   ```

3. **生成国际化代码**
   ```bash
   flutter gen-l10n
   ```

4. **运行应用**
   ```bash
   flutter run
   ```

#### 在电脑上通过 Android 模拟器测试

1. 在 Android Studio 的 **Device Manager** 中创建 Android 11+ 模拟器
2. 启动模拟器后执行：
   ```bash
   flutter emulators
   flutter devices
   flutter run -d <device_id>
   ```

更多维护者开发说明见 [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)。

#### 开发与验证命令

```bash
# 代码检查
flutter analyze

# Flutter 测试
flutter test

# i18n 审计
dart run tool/i18n_audit.dart --check

# Debug APK
flutter build apk --debug

# Release APK（按 ABI 拆分）
flutter build apk --release --split-per-abi --tree-shake-icons --obfuscate --split-debug-info=build/symbols
```

> 本地开发构建如果没有显式传入 `--build-name`，会使用 `pubspec.yaml` 中的默认版本 `999.999.999+999999999`。
> 这样可避免自构建包因为低于 GitHub Releases 最新版本而触发云端更新提示。
> 正式发布工作流会从 Git tag 解析真实版本，并通过 `--build-name` / `--build-number` 覆盖该默认值。Android 覆盖安装实际比较的是 `versionCode`（即 `+` 后面的 build number），不是界面显示的 `versionName`。

Android 原生 JVM 单元测试：

**Windows**
```powershell
cd android
.\gradlew.bat test
```

**macOS / Linux**
```bash
cd android
./gradlew test
```

## MCP 服务

ScreenMemo 可以在手机上手动开启只读的局域网 MCP 服务，让同一局域网内的 AI 客户端读取动态摘要、搜索结果、上下文片段和少量显式请求的证据图片。

- 在 Android App 的“设置 → MCP 服务”中手动开启局域网 MCP 服务。
- Endpoint 固定为 `http://<手机局域网IP>:37621/mcp`，请求必须带 `Authorization: Bearer <token>`。
- 默认不会返回 OCR 原文或图片 base64。只有工具参数显式开启 `include_ocr`，或调用 `get_evidence_images` 时才会返回敏感内容，并带有数量/长度限制。
- 若端口 `37621` 被占用，设置页会显示启动错误，不会自动切换随机端口。

## 支持项目

如果 ScreenMemo 帮你找回过重要线索，欢迎支持 ScreenMemo 赞赏作者

<div align="center">
  <table>
    <tr>
      <td align="center" valign="top">
        <img src="assets/donate/wechat_qr.png" alt="微信赞赏码" width="240" loading="lazy" />
        <div align="center"><sub>微信</sub></div>
      </td>
      <td align="center" valign="top">
        <img src="assets/donate/alipay_qr.jpg" alt="支付宝赞赏码" width="240" loading="lazy" />
        <div align="center"><sub>支付宝</sub></div>
      </td>
    </tr>
  </table>
</div>

## 社区群聊

<div align="center">
  <table>
    <tr>
      <td align="center" valign="top">
        <a href="https://qm.qq.com/q/ob2NMRDzna">
          <img src="assets/screenshots/qrcode_1774681804122.jpg" alt="QQ群二维码" width="320" loading="lazy" />
        </a>
        <div align="center"><sub>QQ群：640740880</sub></div>
        <div align="center"><sub><a href="https://qm.qq.com/q/ob2NMRDzna">点击链接加入群聊【屏忆】</a></sub></div>
      </td>
    </tr>
  </table>
</div>

## 常见问题（FAQ）

<details>
<summary>每月大概占用多少存储空间？</summary>

- 经验值示例：若压缩后约 50 KB / 张，且按每分钟 1 张截图，30 天约 43,200 张，约 2.1 GB / 月。
- 估算公式：月占用（GB）≈ `(60 ÷ 截屏间隔秒) × 60 × 24 × 30 × 单张大小(KB) ÷ 1024 ÷ 1024`
- 降占用建议：增大截屏间隔、启用目标大小压缩、打开过期清理、只对需要的应用开启采集
- 已有历史截图可在“设置 → 截屏设置 → 全局历史压缩”中按目标大小进行全局压缩，取消时会立即停止启动新的图片处理
- 回放视频保存到系统相册成功后，会自动删除应用内部的临时视频副本；已有历史回放副本可在“存储分析 → 回放视频”中清理
</details>

<details>
<summary>数据会上传到云端吗？</summary>

- 默认不会。截图、OCR、索引、统计和大多数配置都保存在本地
- 只有在你显式启用 AI 能力并配置提供商后，相关总结 / 对话请求才会发往你配置的模型服务
</details>

<details>
<summary>支持哪些 AI 提供商？</summary>

- 当前内置提供商类型包括 `OpenAI`、`Azure OpenAI`、`Claude`、`Gemini` 和 `Custom`
- `Custom` 适合接入兼容 OpenAI 风格接口的自建或第三方中转服务
- 不同 AI 上下文可以分别绑定不同的提供商与模型
</details>

<details>
<summary>如何备份 / 迁移数据？</summary>

- 在“数据与备份”里可以导出 ZIP 备份；导出前会先扫描范围、生成 manifest，并展示分类进度
- 导入时支持“覆盖导入”和“合并导入”；合并模式会尽量去重并保留现有数据
- 合并导入只合并 `output` 下的截图、索引和数据库数据；全量备份里的 `shared_prefs`、`app_flutter`、`no_backup` 等运行配置根目录会自动跳过
- 多个大备份建议使用桌面合并工具在电脑上处理，再回传到手机
- 如果导入后发现索引或 OCR 缺失，可在“导入诊断”中执行诊断与 OCR 修复
- 备份默认不包含 cache、code cache、临时缩略图和外部日志
</details>

<details>
<summary>对电量与性能的影响如何？</summary>

- 主要取决于截屏间隔、压缩策略、AI 重建频率和后台保活状态
- 建议启用目标大小压缩、过期清理，并按应用细分策略，避免对不重要应用持续采集
</details>

## 桌面数据合并工具

手机端处理多个大备份 ZIP 时速度有限，因此项目额外提供桌面合并入口 `lib/main_desktop_merger.dart`。

- 选择多个 ZIP 备份文件和输出目录
- 合并前执行结构预检，尽量提前发现坏包或不兼容数据
- 合并备份中的 `output` 数据树：截图文件、分片数据库和主库元数据，并跳过重复内容
- 合并收藏、NSFW 标记和用户设置等元数据
- 实时显示处理进度、告警、影响应用和去重结果
- 处理完成后将合并结果重新打包成新的 ZIP

### 构建命令

**Windows**
```powershell
flutter build windows -t lib/main_desktop_merger.dart --release
```

**macOS**
```bash
flutter build macos -t lib/main_desktop_merger.dart --release
```

**Linux**
```bash
flutter build linux -t lib/main_desktop_merger.dart --release
```

## 权限说明

| 权限 | 作用 | 建议 |
| --- | --- | --- |
| 通知权限 | 前台服务、导出 / 修复 / 重建进度、每日提醒 | 建议开启 |
| 无障碍服务 | 自动截屏、Activity 重建、部分后台 AI 流程 | 主功能必需 |
| 使用统计权限 | 前台应用识别、应用维度筛选与统计 | 强烈建议 |
| 已安装应用可见性 | 读取已安装应用列表，用于应用选择、筛选与统计 | 主功能需要 |
| 忽略电池优化 / 自启动 | 提高后台持续采集与重建稳定性 | 强烈建议 |
| 精确闹钟 | 每日总结提醒 | 可选 |
| 相册 / 下载写入 | 保存截图、回放视频或导出结果 | 可选 |

## 国际化

当前 README 与应用界面都维护以下四种语言：

- 简体中文
- 英文
- 日本語
- 한국어

应用界面文案统一维护在 `lib/l10n/app_*.arb`，原生 Android 通知、权限说明与前台服务文案维护在 `android/app/src/main/res/values*/strings.xml`。新增 UI 文案时不要直接写在 Dart Widget 或 Android XML 属性中，应先补齐对应语言资源并重新运行 `flutter gen-l10n`。

常用命令：

```bash
# 生成 l10n 代码
flutter gen-l10n

# 检查 ARB / 平台层 / UI 硬编码回归
dart run tool/i18n_audit.dart --check

# 在确认例外后更新 baseline
dart run tool/i18n_audit.dart --update-baseline
```

`flutter test` 会自动运行 `test/i18n_audit_test.dart`，用于阻止新的多语言回归。

## 贡献指南

欢迎贡献代码、报告问题或提出建议。

1. Fork 本项目
2. 创建分支：`git checkout -b feature/your-change`
3. 提交修改：`git commit -m "feat: describe your change"`
4. 推送分支：`git push origin feature/your-change`
5. 提交 Pull Request

提交前建议至少运行：

- `flutter analyze`
- `flutter test`
- `dart run tool/i18n_audit.dart --check`
