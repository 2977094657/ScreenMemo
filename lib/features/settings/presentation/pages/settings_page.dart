import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:intl/intl.dart' as intl;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/utils/byte_formatter.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/core/widgets/ui_dialog.dart';
import 'package:screen_memo/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:screen_memo/features/permissions/application/permission_service.dart';
import 'package:screen_memo/core/theme/theme_service.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/features/capture/application/screenshot_service.dart';
import 'package:screen_memo/core/constants/user_settings_keys.dart';
import 'package:screen_memo/features/apps/application/app_selection_service.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/data/settings/user_settings_service.dart';
import 'package:screen_memo/models/app_info.dart';
import 'package:file_picker/file_picker.dart';
import 'package:screen_memo/features/settings/presentation/pages/nsfw_settings_page.dart';
import 'package:screen_memo/features/storage_analysis/presentation/pages/storage_analysis_page.dart';
import 'package:screen_memo/features/backup/presentation/pages/import_diagnostics_page.dart';
import 'package:screen_memo/features/backup/presentation/pages/export_backup_page.dart';
import 'package:screen_memo/features/daily_summary/application/daily_summary_service.dart';
import 'package:screen_memo/features/diagnostics/application/log_export_service.dart';
import 'package:screen_memo/features/nsfw/application/nsfw_preference_service.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/features/app_health/application/app_health_service.dart';
import 'package:screen_memo/features/mcp/application/mcp_client_service.dart';
import 'package:screen_memo/features/mcp/application/mcp_service.dart';
import 'package:screen_memo/features/skills/application/skill_service.dart';
import 'package:screen_memo/features/updater/presentation/update_prompt_coordinator.dart';
import 'package:url_launcher/url_launcher.dart';

part 'settings_page_about_part.dart';
part 'settings_page_backup_part.dart';
part 'settings_page_permissions_part.dart';
part 'settings_page_layout_part.dart';
part 'settings_page_segment_part.dart';
part 'settings_page_display_advanced_part.dart';
part 'settings_page_screenshot_part.dart';
part 'settings_page_nsfw_part.dart';
part 'settings_page_daily_notify_part.dart';
part 'settings_page_app_health_part.dart';
part 'settings_page_logs_part.dart';
part 'settings_page_mcp_part.dart';
part 'settings_page_skills_part.dart';
part 'settings_page_support_part.dart';

enum _ImportMode { overwrite, merge }

enum _SettingsSubPage {
  home,
  permissions,
  display,
  screenshot,
  segmentSummary,
  dailyReminder,
  appHealth,
  mcpService,
  skills,
  dataBackup,
  logManagement,
  advanced,
  about,
  support,
}

class SettingsPageController {
  _SettingsPageState? _state;
  final ValueNotifier<bool> isInSubPage = ValueNotifier<bool>(false);

  bool handleBack() {
    final state = _state;
    if (state == null) return false;
    return state._handleBackToSettingsHome();
  }

  void _attach(_SettingsPageState state) {
    _state = state;
    isInSubPage.value = state._subPage != _SettingsSubPage.home;
  }

  void _detach(_SettingsPageState state) {
    if (_state == state) {
      _state = null;
      isInSubPage.value = false;
    }
  }

  void _onSubPageChanged(_SettingsSubPage subPage) {
    isInSubPage.value = subPage != _SettingsSubPage.home;
  }

  void dispose() {
    _state = null;
    isInSubPage.dispose();
  }
}

/// 设置页面
class SettingsPage extends StatefulWidget {
  final ThemeService themeService;
  final SettingsPageController? controller;

  const SettingsPage({super.key, required this.themeService, this.controller});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  _SettingsSubPage _subPage = _SettingsSubPage.home;

  final PermissionService _permissionService = PermissionService.instance;
  final ScreenshotDatabase _screenshotDatabase = ScreenshotDatabase.instance;
  final AppSelectionService _appService = AppSelectionService.instance;
  Map<String, bool> _permissions = {};
  Map<String, bool> _keepAlivePermissions = {};
  bool _isLoading = true;
  bool _isLoadingKeepAlive = true;
  int _screenshotInterval = 5;
  bool _autoAddNewAppsToCapture = false;
  bool _windowScreenshotApiEnabled = false;
  bool _privacyMode = true; // 隐私模式，默认开启
  // 段落采样设置
  int _segmentSampleIntervalSec = 20; // 最小5秒
  int _segmentDurationMin = 5; // 以分钟显示，最小1分钟
  // AI 请求最小间隔（秒）
  int _aiRequestIntervalSec = 3; // 默认3秒，最低1秒
  // 动态总结格式不符合要求时的自动重试次数（0=关闭）
  int _segmentsJsonAutoRetryMax = 1; // 默认 1
  bool _aiRawResponseCleanupEnabled = true; // 默认开启
  int _aiRawResponseCleanupDays = 30; // 默认保留 30 天
  // 动态合并限制（分钟；0 表示不限制）
  int _dynamicMergeMaxSpanMin = 180; // 默认 3h
  int _dynamicMergeMaxGapMin = 60; // 默认 1h
  int _dynamicMergeMaxImages = 200; // 默认 200（0 表示不限制）
  // 截图质量设置（仅通过编码压缩，不修改分辨率）
  String _imageFormat = 'webp_lossy'; // jpeg | png | webp_lossy | webp_lossless
  int _imageQuality = 90; // 备用项，已被"目标大小"策略覆盖
  bool _useTargetSize = false; // 默认关闭
  int _targetSizeKb = 50; // 默认 50KB（最低仅支持 50KB）
  int _globalCompressDays = 0; // 全局历史压缩的时间范围；0 表示全部历史
  bool _compressingGlobalHistory = false;
  CompressionProgress? _globalCompressionProgress;
  String _screenshotDedupeMode =
      'balanced'; // exact | conservative | balanced | aggressive
  String _aiImageSendFormat = 'original'; // original | jpeg | png
  // 电池权限检查定时器
  Timer? _batteryPermissionTimer;
  int _batteryCheckCount = 0;
  bool _exportingDb = false;
  bool _importingData = false;
  // 导入/导出全屏进度状态
  // 截图过期清理设置
  bool _expireEnabled = false; // 是否启用过期自动删除
  int _expireDays = 30; // 过期天数，下限 1
  // 每日总结提醒设置
  bool _dailyNotifyEnabled = true;
  int _dailyNotifyHour = 22;
  int _dailyNotifyMinute = 0;
  // 日志开关（默认开启）
  bool _loggingEnabled = true;
  // 分类日志开关：AI 与 截图
  bool _aiLoggingEnabled = false;
  bool _screenshotLoggingEnabled = false;
  // 流式期间实时渲染图片（影响 AI 对话性能的全局开关）
  bool _renderImagesDuringStreaming = false;
  // AIChat 性能日志悬浮窗（默认关闭，避免默认刷屏）
  bool _aiChatPerfOverlayEnabled = false;
  // 动态页“每日总结”右侧的日志图标（默认关闭）
  bool _dynamicEntryLogIconEnabled = false;
  // 最近一次导入模式，默认合并
  _ImportMode _lastImportMode = _ImportMode.merge;
  bool _recalculatingAll = false;
  bool _appHealthLoading = false;
  AppHealthDashboardSnapshot? _appHealthSnapshot;
  String _appHealthEventFilter = 'all';
  Duration _appHealthRange = AppHealthService.defaultRange;
  Duration _appHealthSlotSize = AppHealthService.defaultSlotSize;
  Timer? _appHealthWindowDebounce;
  bool _appHealthReloadQueued = false;
  LogDirectoryListing? _logDirectoryListing;
  String _logDirectoryRelativePath = '';
  bool _logManagementLoading = false;
  bool _logManagementSharing = false;
  bool _logManagementDeleting = false;
  McpServerStatus? _mcpStatus;
  bool _mcpLoading = false;
  bool _externalMcpLoading = false;
  List<McpClientServer> _externalMcpServers = <McpClientServer>[];
  final Set<String> _externalMcpSyncingIds = <String>{};
  final Set<String> _externalMcpServerBusyIds = <String>{};
  final Set<String> _externalMcpToolBusyNames = <String>{};
  bool _skillsLoading = false;
  List<SkillMetadata> _skills = <SkillMetadata>[];
  late final Future<PackageInfo> _packageInfoFuture =
      PackageInfo.fromPlatform();
  int _aboutVersionTapCount = 0;

  // NSFW 设置 - 域名清单管理
  final TextEditingController _nsfwDomainController = TextEditingController();
  bool _nsfwLoading = false;
  List<Map<String, dynamic>> _nsfwRules = <Map<String, dynamic>>[];
  int? _nsfwPreviewCount;

  bool _handleBackToSettingsHome() {
    if (_subPage != _SettingsSubPage.home) {
      _switchSubPage(_SettingsSubPage.home);
      return true;
    }
    return false;
  }

  // part 文件中的扩展方法不能直接调用 State.setState（会触发 protected 成员告警）。
  // 统一通过当前 State 实例内的包装方法刷新 UI，保持拆分前的行为不变。
  void _settingsSetState(VoidCallback fn) => setState(fn);

  Color _settingsBackgroundColor(BuildContext context) {
    return Theme.of(context).scaffoldBackgroundColor;
  }

  BorderSide _settingsDividerSide(BuildContext context) {
    final theme = Theme.of(context);
    final double opacity = theme.brightness == Brightness.dark ? 0.35 : 0.18;
    return BorderSide(
      color: theme.colorScheme.outline.withValues(alpha: opacity),
      width: 1,
    );
  }

  Future<void> _restoreDailySummaryScheduleOnStartup() async {
    try {
      final bool enabled = await UserSettingsService.instance.getBool(
        UserSettingKeys.dailyNotifyEnabled,
        defaultValue: true,
        legacyPrefKeys: const <String>['daily_notify_enabled'],
      );
      final int hour = await UserSettingsService.instance.getInt(
        UserSettingKeys.dailyNotifyHour,
        defaultValue: 22,
        legacyPrefKeys: const <String>['daily_notify_hour'],
      );
      final int minute = await UserSettingsService.instance.getInt(
        UserSettingKeys.dailyNotifyMinute,
        defaultValue: 0,
        legacyPrefKeys: const <String>['daily_notify_minute'],
      );
      await DailySummaryService.instance.scheduleDailyNotification(
        hour: hour.clamp(0, 23),
        minute: minute.clamp(0, 59),
        enabled: enabled,
      );
      await DailySummaryService.instance.refreshAutoRefreshSchedule();
    } catch (_) {}
  }

  void _switchSubPage(_SettingsSubPage next) {
    if (_subPage == next) return;
    FocusManager.instance.primaryFocus?.unfocus();

    if (_subPage == _SettingsSubPage.permissions &&
        next != _SettingsSubPage.permissions) {
      _stopBatteryPermissionCheck();
    }

    setState(() {
      _subPage = next;
      if (next == _SettingsSubPage.permissions) {
        _isLoading = true;
        _isLoadingKeepAlive = true;
      }
    });
    widget.controller?._onSubPageChanged(next);

    switch (next) {
      case _SettingsSubPage.home:
        break;
      case _SettingsSubPage.permissions:
        unawaited(_loadAllPermissions());
        break;
      case _SettingsSubPage.display:
        unawaited(_loadPrivacyMode());
        break;
      case _SettingsSubPage.screenshot:
        unawaited(_loadScreenshotInterval());
        unawaited(_loadAutoAddNewAppsToCapture());
        unawaited(_loadWindowScreenshotApiEnabled());
        unawaited(_loadScreenshotDedupeMode());
        unawaited(_loadScreenshotQualitySettings());
        unawaited(_loadScreenshotExpireSettings());
        _restoreGlobalCompressionState();
        break;
      case _SettingsSubPage.segmentSummary:
        unawaited(_loadSegmentSettings());
        unawaited(_loadDynamicMergeLimits());
        unawaited(_loadAiRequestInterval());
        unawaited(_loadSegmentsJsonAutoRetryMax());
        unawaited(_loadAiRawResponseCleanupSettings());
        break;
      case _SettingsSubPage.dailyReminder:
        unawaited(_loadDailyNotifySettings());
        break;
      case _SettingsSubPage.appHealth:
        unawaited(_loadAppHealthStatus(refresh: true));
        break;
      case _SettingsSubPage.mcpService:
        unawaited(_loadMcpPageData());
        break;
      case _SettingsSubPage.skills:
        unawaited(_loadSkills());
        break;
      case _SettingsSubPage.dataBackup:
        break;
      case _SettingsSubPage.logManagement:
        unawaited(_loadLogDirectory());
        break;
      case _SettingsSubPage.advanced:
        unawaited(_loadLoggingEnabled());
        unawaited(_loadRenderImagesDuringStreaming());
        unawaited(_loadAiChatPerfOverlayEnabled());
        unawaited(_loadDynamicEntryLogIconEnabled());
        break;
      case _SettingsSubPage.about:
        break;
      case _SettingsSubPage.support:
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?._attach(this);
    unawaited(_restoreDailySummaryScheduleOnStartup());
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    _stopBatteryPermissionCheck();
    _appHealthWindowDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _nsfwDomainController.dispose();
    widget.controller?._detach(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (_subPage == _SettingsSubPage.permissions) {
        // 应用从后台返回前台时，刷新权限状态
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _loadAllPermissions();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _subPage == _SettingsSubPage.home,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_subPage != _SettingsSubPage.home) {
          _switchSubPage(_SettingsSubPage.home);
        }
      },
      child: Scaffold(
        appBar: _buildSettingsAppBar(context),
        backgroundColor: _settingsBackgroundColor(context),
        body: _buildSettingsBody(context),
      ),
    );
  }

  // ===== 时间段总结设置 UI =====
}
