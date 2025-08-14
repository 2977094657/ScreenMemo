# 屏忆

一个基于Flutter的智能屏幕截图和备忘录应用，专为Android平台设计，具备强大的无障碍服务截图功能。

## 功能特性

### 🔥 核心功能
- **智能截图**: 基于AccessibilityService的无权限截图
- **定时监控**: 可设置间隔时间自动截图
- **应用识别**: 智能识别前台应用并分类保存
- **图库管理**: 完整的截图浏览和管理功能
- **统计分析**: 详细的使用统计和数据分析

### 🛡️ 权限管理
- **无障碍服务**: 核心截图功能
- **存储权限**: 截图文件保存
- **通知权限**: 服务状态提醒
- **电池优化**: 智能保活机制
- **OEM兼容**: 支持小米、华为、OPPO等厂商

### 🎨 用户界面
- **Material Design 3**: 现代化设计语言
- **深色/浅色主题**: 自适应主题切换
- **响应式布局**: 适配不同屏幕尺寸
- **流畅动画**: 优雅的交互体验

## 技术架构

### 前端技术栈
- **Flutter 3.x**: 跨平台UI框架
- **Dart**: 编程语言
- **Material Design 3**: UI设计系统
- **SQLite**: 本地数据库

### Android原生技术
- **Kotlin**: Android开发语言
- **AccessibilityService**: 无障碍截图服务
- **AIDL**: 进程间通信
- **JobScheduler**: 后台任务调度
- **Foreground Service**: 前台服务保活

### 服务架构
```
┌─────────────────────┐
│   Flutter UI Layer  │
├─────────────────────┤
│   Method Channel    │
├─────────────────────┤
│   MainActivity      │
├─────────────────────┤
│ AccessibilityBridge │
├─────────────────────┤
│AccessibilityService │
└─────────────────────┘
```

## 快速开始

### 环境要求
- Flutter SDK 3.0+
- Android SDK 21+
- Kotlin 1.8+
- Gradle 8.0+

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

3. **运行应用**
```bash
flutter run
```

### 权限配置

应用首次运行时需要配置以下权限：

1. **无障碍服务**: 设置 → 辅助功能 → 屏忆 → 启用
2. **存储权限**: 应用会自动请求
3. **通知权限**: 应用会自动请求
4. **电池优化**: 设置 → 电池 → 电池优化 → 屏忆 → 不优化

## 项目结构

```
lib/
├── main.dart                 # 应用入口
├── models/                   # 数据模型
├── pages/                    # 页面组件
├── services/                 # 业务服务
├── theme/                    # 主题配置
└── widgets/                  # 通用组件

android/app/src/main/kotlin/com/fqyw/screen_memo/
├── MainActivity.kt                        # 主Activity
├── ScreenCaptureAccessibilityService.kt   # 无障碍服务
├── AccessibilityBridgeService.kt          # AIDL桥接服务
├── ScreenCaptureService.kt               # 前台服务
├── KeepAliveJobService.kt                # 保活服务
├── FileLogger.kt                         # 日志系统
├── PermissionGuideHelper.kt              # 权限助手
└── OEMCompatibilityHelper.kt             # OEM兼容
```

## 开发说明

### 调试模式
应用内置了完整的调试功能：
- 服务状态监控
- 权限状态检查
- 日志文件查看
- 性能统计

### 日志系统
- 自动生成调试日志
- 文件路径: `/Android/data/com.fqyw.screen_memo/files/logs/`
- 支持实时查看和导出

### 测试
```bash
# 运行单元测试
flutter test

# 运行Android测试
cd android && ./gradlew test
```

## 兼容性

### Android版本
- 最低支持: Android 5.0 (API 21)
- 推荐版本: Android 8.0+ (API 26)
- 完全兼容: Android 14 (API 34)

### 设备厂商
- ✅ 小米 (MIUI)
- ✅ 华为 (EMUI/HarmonyOS)
- ✅ OPPO (ColorOS)
- ✅ Vivo (FuntouchOS)
- ✅ 三星 (One UI)
- ✅ 原生Android

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 贡献

欢迎提交 Issue 和 Pull Request！

## 更新日志

### v1.0.0 (2025-01-25)
- 🎉 初始版本发布
- ✅ 完整的截图功能
- ✅ 无障碍服务实现
- ✅ 多平台支持
- ✅ 权限管理系统
- ✅ OEM厂商兼容
