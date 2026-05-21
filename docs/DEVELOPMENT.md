# 开发文档

本文面向项目维护者，记录本地构建、发布和 Android 签名相关流程。不要在公开文档、Issue、日志或提交中暴露真实签名密码、keystore 内容或 GitHub Secret 值。

## Android 签名配置

为避免 GitHub Release 之间、以及本地开发包与 Release 包之间出现“签名冲突”，正式发包必须使用同一份稳定 keystore。

- `flutter build apk --release` 要求存在 `android/key.properties`，否则会直接失败，不再退回 debug 签名。
- 本地配置了 `android/key.properties` 后，`debug` / `profile` / `release` 构建都会使用同一份 keystore，方便直接覆盖 GitHub Release 版本做真机调试。
- 如果没有配置 `android/key.properties`，普通 `flutter run` / debug 构建仍会使用 Android 默认 debug 签名，但不能覆盖正式 Release 包。
- `android/key.properties`、`*.jks` 和 `private_backups/` 已被 `.gitignore` 排除，不要提交到仓库。

### 本地文件

维护者本地需要保存：

```text
android/app/upload-keystore.jks
android/key.properties
```

`android/key.properties` 示例：

```properties
storePassword=<store-password>
keyPassword=<key-password>
keyAlias=upload
storeFile=upload-keystore.jks
storeType=PKCS12
certSha256=<release-certificate-sha256>
```

其中 `storeFile` 相对于 `android/app/`，例如上面的文件路径是 `android/app/upload-keystore.jks`。

> 注意：已经正式发布后不要重新生成或更换 keystore，否则用户需要卸载旧版后重新安装新版。

### 复用已有本地 debug 签名

如果维护者手机上已经安装了大量本地开发构建数据，并且这些构建一直使用本机 Android debug keystore，则可以把本机 debug keystore 固定为后续发布签名，避免维护者本人迁移数据。

本机 debug keystore 默认位置：

```powershell
$env:USERPROFILE\.android\debug.keystore
```

默认参数：

```properties
storePassword=android
keyPassword=android
keyAlias=androiddebugkey
storeFile=upload-keystore.jks
storeType=PKCS12
```

复制到项目签名位置：

```powershell
Copy-Item "$env:USERPROFILE\.android\debug.keystore" android/app/upload-keystore.jks -Force
```

再读取 SHA-256 并写入 `android/key.properties` 的 `certSha256`：

```powershell
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android -alias androiddebugkey -keypass android | findstr /C:"SHA256"
```

当前维护者本机 debug 签名 SHA-256：

```text
5383db4b85af2b86c769577135609e0c937557887fc8d77d18b08d28a0036e38
```

> 风险：debug keystore 的默认密码是公开约定值，安全性主要依赖 keystore 文件本身不泄露。若该文件泄露，其他人可以签出可覆盖安装的 APK。对公开生产项目更推荐单独 release keystore；对需要保留现有本地数据的维护者设备，可以选择复用本机 debug keystore。

### 生成新 keystore

仅在首次建立发布签名时执行。已经使用某个 keystore 发版后，应继续复用同一份文件。

```powershell
keytool -genkeypair -v `
  -keystore android/app/upload-keystore.jks `
  -storetype PKCS12 `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias upload
```

查看证书指纹，填入 `key.properties` 的 `certSha256`，并同步到 GitHub Secret：

```powershell
keytool -list -v -keystore android/app/upload-keystore.jks -alias upload | findstr /C:"SHA256"
```

### 生成 GitHub Secrets

GitHub Actions 需要配置这些 Secrets：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_SIGNING_CERT_SHA256`

从本地文件读取参数：

```powershell
$props = ConvertFrom-StringData (Get-Content android/key.properties -Raw)
$props.storePassword
$props.keyPassword
$props.keyAlias
$props.certSha256
```

生成 `ANDROID_KEYSTORE_BASE64`：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/upload-keystore.jks")) | Set-Clipboard
```

如果安装了 GitHub CLI，可以直接写入 Secrets：

```powershell
$props = ConvertFrom-StringData (Get-Content android/key.properties -Raw)

[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/upload-keystore.jks")) | gh secret set ANDROID_KEYSTORE_BASE64 --body-file -
$props.storePassword | gh secret set ANDROID_KEYSTORE_PASSWORD --body-file -
$props.keyPassword | gh secret set ANDROID_KEY_PASSWORD --body-file -
$props.keyAlias | gh secret set ANDROID_KEY_ALIAS --body-file -
$props.certSha256 | gh secret set ANDROID_SIGNING_CERT_SHA256 --body-file -
```

### 校验签名配置

```powershell
cd android
.\gradlew.bat :app:validateReleaseSigning :app:validateSigningRelease
```

成功时会输出当前证书 SHA-256。若 `certSha256` 与 keystore 实际证书不一致，构建会失败。

### 本地覆盖安装建议

如果设备上已经装过较高 `versionCode` 的构建，签名一致后仍可能因为版本号回退导致安装失败。可以临时构建一个高 `versionCode` 的 debug 包覆盖安装：

```powershell
flutter build apk --debug --build-number=999999
```

生成文件：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

GitHub Release 的用户可见版本号始终来自 tag，例如 `v1.2.3` 会构建为 `versionName=1.2.3`。Android 还要求一个整数 `versionCode`，工作流会从 tag 派生：

```text
versionCode = major * 1000000 + minor * 1000 + patch
```

例如 `v1.2.3` 对应 `versionCode=1002003`，可以继续覆盖上面的本地调试包。

发布工作流会在创建 GitHub Release 前，根据上一个稳定 tag 到当前 tag 的提交记录生成 `release-notes.md`，并把它作为 Release body 写入；客户端只负责读取这份 body 并以虚拟列表展示。

### 旧签名版本升级说明

由于早期 GitHub APK 已经存在签名不一致的问题，修复签名后的第一个稳定版本仍无法覆盖旧签名版本。旧用户需要先在旧版中导出备份，再卸载旧版、安装新签名版本并导入备份；从新签名版本开始，后续 GitHub 更新才可以直接覆盖安装。

## 项目结构

Flutter 代码按分层架构整理：

- `lib/app/`：应用入口装配、`MaterialApp`、全局路由与启动后的后台任务恢复
- `lib/core/`：跨功能基础设施，包括主题、通用组件、日志、性能记录、生命周期、语言服务和通用工具
- `lib/data/`：跨功能数据、平台与安全基础设施，例如数据库、路径、设置和安全存储
- `lib/features/`：按功能收拢页面、组件与应用服务代码，例如应用选择、收藏、备份、AI、AI 对话、诊断、桌面合并、图库、搜索、存储分析、设置、权限、采集、App 运行状态、NSFW、每日总结与时间线
  - `lib/features/settings/presentation/pages/settings_page*.dart`：设置页按功能拆成入口状态、布局、权限、截图、段落总结、备份、显示/高级、App 运行状态、NSFW 与每日提醒等 part 文件，避免继续形成单个超大页面文件
  - `lib/features/search/presentation/pages/search_page*.dart`：搜索页按搜索加载、筛选、视图、文档、动态结果和通用组件拆分
  - `lib/features/timeline/presentation/pages/segment_status_page*.dart`：动态状态页按状态辅助、动态重建、详情、时间轴和单条动态卡片拆分
  - `lib/features/ai_providers/presentation/pages/provider_edit_page*.dart`：AI 提供商编辑页按状态、批量维护、保存、模型卡片、Key 管理和表单 UI 拆分
  - `lib/features/capture/presentation/pages/home_page*.dart`：首页按数据加载、诊断、晨间建议、权限 UI、内容列表和语言切换拆分
  - `lib/features/gallery/presentation/pages/screenshot_gallery_page*.dart`：截图图库页按日期 Tab、数据加载、操作、网格、单项和批量选择拆分
  - `lib/features/ai_chat/presentation/widgets/chat_context_sheet*.dart`：对话上下文面板按状态刷新、导出/操作和展示卡片拆分
- `lib/models/` 与 `lib/l10n/`：保留共享模型与生成的国际化代码

首页首屏加载需要保持“缓存优先、后台刷新”的节奏：`home_page_data_part.dart` 先读取已保存监控应用和统计缓存并渲染列表，再等待已安装应用扫描、最新统计和权限检查。不要把“列表尚未加载完成”直接展示为“暂无监控应用”；应用列表缓存过期时也应先返回旧缓存，再在后台刷新安装状态和图标。

Android 原生层按职责建立子包，入口类保留在 `android/app/src/main/kotlin/com/fqyw/screen_memo/`，其余能力按下列目录组织：

- `app/`：原生应用上下文基础设施
- `capture/`：无障碍截屏、前台截屏服务、无障碍状态监控与桥接
- `channel/`：Flutter `MethodChannel` 分发与低耦合原生能力适配
- `daily/`：每日总结通知、调度、广播接收器与 Worker
- `database/`：原生数据库辅助写入和查询
- `diagnostics/`：运行诊断与 OEM 兼容信息
- `dynamic/`：动态重建前台任务
- `importing/`：导入后 OCR 修复任务
- `logging/`：原生日志与输出日志
- `network/`：原生网络客户端工厂
- `permissions/`：权限引导与权限报告
- `replay/`：时间线回放视频生成与通知
- `segment/`：原生动态分段与段落总结
- `service/`：启动、自恢复、保活相关 Service/Receiver
- `settings/`：原生设置读写、AI 配置和每应用设置桥接
- `storage/`：原生存储统计与迁移

原生动态总结大文件继续拆出以下辅助文件：

- `android/app/src/main/kotlin/com/fqyw/screen_memo/segment/SegmentSummaryMergeHelpers.kt`：文本优先合并、结构化 JSON 与图片引用归一化辅助逻辑
- `android/app/src/main/kotlin/com/fqyw/screen_memo/segment/SegmentSummaryAiResponseParser.kt`：OpenAI/Gemini 兼容响应、流式 SSE、Responses API 输出提取与 URL 规范化
- `android/app/src/main/kotlin/com/fqyw/screen_memo/segment/SegmentSummaryJsonRepair.kt`：动态总结 JSON 修复、自动重试提示和修复元数据

结构调整原则：优先做“移动文件 + 修复 import + 验证”，避免在目录迁移时同时重写业务逻辑。

## 发布检查清单

发布 tag 前建议确认：

- 本地和 GitHub Actions 使用同一份 release keystore。
- `ANDROID_SIGNING_CERT_SHA256` 与 `android/key.properties` 中的 `certSha256` 一致。
- `flutter analyze` 通过。
- `flutter test` 通过。
- `dart run tool/i18n_audit.dart --check` 通过。
