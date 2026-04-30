import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import '../services/permission_service.dart';
import '../services/theme_service.dart';
import '../services/screenshot_database.dart';
import '../services/screenshot_service.dart';
import '../constants/user_settings_keys.dart';
import '../services/app_selection_service.dart';
import '../services/flutter_logger.dart';
import '../services/user_settings_service.dart';
import '../models/app_info.dart';
import 'package:file_picker/file_picker.dart';
import 'nsfw_settings_page.dart';
import 'storage_analysis_page.dart';
import 'import_diagnostics_page.dart';
import 'export_backup_page.dart';
import '../services/daily_summary_service.dart';
import '../services/nsfw_preference_service.dart';
import '../services/ai_settings_service.dart';

enum _ImportMode { overwrite, merge }

enum _SettingsSubPage {
  home,
  permissions,
  display,
  screenshot,
  segmentSummary,
  dailyReminder,
  dataBackup,
  advanced,
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
  bool _privacyMode = true; // 隐私模式，默认开启
  // 段落采样设置
  int _segmentSampleIntervalSec = 20; // 最小5秒
  int _segmentDurationMin = 5; // 以分钟显示，最小1分钟
  // AI 请求最小间隔（秒）
  int _aiRequestIntervalSec = 3; // 默认3秒，最低1秒
  // 动态(segments) structured_json 解析失败时的自动重试次数（0=关闭）
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
  bool _grayscale = false; // 已移除，保持为 false
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
        unawaited(_loadScreenshotQualitySettings());
        unawaited(_loadScreenshotExpireSettings());
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
      case _SettingsSubPage.dataBackup:
        break;
      case _SettingsSubPage.advanced:
        unawaited(_loadLoggingEnabled());
        unawaited(_loadRenderImagesDuringStreaming());
        unawaited(_loadAiChatPerfOverlayEnabled());
        unawaited(_loadDynamicEntryLogIconEnabled());
        break;
    }
  }

  Future<void> _recalculateAllStatistics() async {
    if (_recalculatingAll) return;
    final AppLocalizations t = AppLocalizations.of(context);
    setState(() {
      _recalculatingAll = true;
    });

    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    bool dialogClosed = false;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'recalculate_progress',
      pageBuilder: (BuildContext dialogContext, _, __) {
        final ThemeData theme = Theme.of(dialogContext);
        return WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacing4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.recalculateAllProgress,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      const Center(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    try {
      await ScreenshotService.instance.recomputeAllAppStats();
      if (mounted) {
        if (!dialogClosed) {
          try {
            navigator.pop();
            dialogClosed = true;
          } catch (_) {}
        }
        UINotifier.success(context, t.recalculateAllSuccess);
      }
    } catch (e) {
      if (mounted) {
        if (!dialogClosed) {
          try {
            navigator.pop();
            dialogClosed = true;
          } catch (_) {}
        }
        await showUIDialog<void>(
          context: context,
          barrierDismissible: false,
          title: t.recalculateAllFailedTitle,
          content: Text(e.toString()),
          actions: [
            UIDialogAction(
              text: t.dialogOk,
              style: UIDialogActionStyle.primary,
            ),
          ],
        );
      }
    } finally {
      if (!dialogClosed) {
        try {
          navigator.pop();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _recalculatingAll = false;
        });
      }
    }
  }

  Future<void> _showMergeResultDialog(MergeReport report) async {
    if (!mounted) return;
    final AppLocalizations t = AppLocalizations.of(context);
    final List<String> affectedPackages = report.affectedPackages.toList()
      ..sort();
    final String affectedLabel = affectedPackages.join(', ');
    final Map<String, AppInfo> appInfoMap = {
      for (final app in await _appService.getAllInstalledApps())
        app.packageName: app,
    };
    final ThemeData theme = Theme.of(context);
    final double maxHeight = ((MediaQuery.of(context).size.height * 0.6).clamp(
      280.0,
      420.0,
    )).toDouble();

    final Widget statsSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.mergeReportInserted(report.insertedScreenshots),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppTheme.spacing2),
        Text(
          t.mergeReportSkipped(report.skippedScreenshotDuplicates),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppTheme.spacing2),
        Text(
          t.mergeReportCopied(report.copiedFiles),
          style: theme.textTheme.bodyMedium,
        ),
        if (affectedPackages.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacing3),
          Text(
            t.mergeReportAffectedPackages(affectedLabel),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppTheme.spacing1),
          Wrap(
            spacing: AppTheme.spacing2,
            runSpacing: AppTheme.spacing2,
            children: affectedPackages
                .map((pkg) => _buildAffectedPackageChip(appInfoMap[pkg], pkg))
                .toList(),
          ),
        ],
        const SizedBox(height: AppTheme.spacing3),
        Text(
          t.mergeReportWarnings,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTheme.spacing1),
        if (report.warnings.isEmpty)
          Text(t.mergeReportNoWarnings, style: theme.textTheme.bodySmall)
        else
          ...report.warnings.map(
            (w) => Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacing1),
              child: Text(t.warningBullet(w), style: theme.textTheme.bodySmall),
            ),
          ),
      ],
    );

    await showUIDialog<void>(
      context: context,
      barrierDismissible: false,
      title: t.mergeCompleteTitle,
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: AppTheme.spacing1),
          child: statsSection,
        ),
      ),
      actions: [
        UIDialogAction(text: t.dialogOk, style: UIDialogActionStyle.primary),
      ],
    );
  }

  Future<_ImportMode?> _selectImportMode() async {
    final AppLocalizations t = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final _ImportMode initial = _lastImportMode;

    return showModalBottomSheet<_ImportMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return UISheetSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppTheme.spacing3),
              const UISheetHandle(),
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacing4),
                child: Text(
                  t.importModeTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildImportModeOption(
                sheetContext: sheetContext,
                title: t.importModeOverwriteTitle,
                description: t.importModeOverwriteDesc,
                icon: Icons.warning_amber_rounded,
                iconColor: theme.colorScheme.error,
                mode: _ImportMode.overwrite,
                selectedMode: initial,
              ),
              _buildImportModeOption(
                sheetContext: sheetContext,
                title: t.importModeMergeTitle,
                description: t.importModeMergeDesc,
                icon: Icons.merge_type_rounded,
                iconColor: theme.colorScheme.primary,
                mode: _ImportMode.merge,
                selectedMode: initial,
              ),
              const SizedBox(height: AppTheme.spacing3),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext, null),
                  child: Text(t.dialogCancel),
                ),
              ),
              const SizedBox(height: AppTheme.spacing2),
            ],
          ),
        );
      },
    );
  }

  // 已移除导入来源选择（统一通过 ZIP 导入）

  Widget _buildImportModeOption({
    required BuildContext sheetContext,
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
    required _ImportMode mode,
    required _ImportMode selectedMode,
  }) {
    final bool isSelected = mode == selectedMode;
    final ColorScheme scheme = Theme.of(sheetContext).colorScheme;

    return InkWell(
      onTap: () {
        _lastImportMode = mode;
        Navigator.pop(sheetContext, mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing4,
          vertical: AppTheme.spacing3,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withOpacity(0.08)
              : Colors.transparent,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(sheetContext).textTheme.bodyLarge?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing1),
                  Text(
                    description,
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(left: AppTheme.spacing2),
                child: Icon(Icons.check, color: scheme.primary, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAffectedPackageChip(AppInfo? app, String packageName) {
    final String label = app?.appName.isNotEmpty == true
        ? app!.appName
        : packageName;
    final ImageProvider? iconImage =
        (app?.icon != null && app!.icon!.isNotEmpty)
        ? MemoryImage(app.icon!)
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: AppTheme.spacing1 + 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(0.12),
            backgroundImage: iconImage,
            child: iconImage == null
                ? Text(
                    label.isNotEmpty ? label.characters.first : '?',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: AppTheme.spacing1 + 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsDropdown(BuildContext context) {
    return Column(
      children: [
        _buildPermissionItem(
          context: context,
          icon: Icons.folder_outlined,
          title: AppLocalizations.of(context).storagePermissionTitle,
          description: AppLocalizations.of(context).storagePermissionDesc,
          isGranted: _permissions['storage'] ?? false,
          onRequest: () => _requestPermission('storage'),
        ),
        _buildPermissionItem(
          context: context,
          icon: Icons.notifications_outlined,
          title: AppLocalizations.of(context).notificationPermissionTitle,
          description: AppLocalizations.of(context).notificationPermissionDesc,
          isGranted: _permissions['notification'] ?? false,
          onRequest: () => _requestPermission('notification'),
        ),
        _buildPermissionItem(
          context: context,
          icon: Icons.accessibility_new_outlined,
          title: AppLocalizations.of(context).accessibilityPermissionTitle,
          description: AppLocalizations.of(context).accessibilityPermissionDesc,
          isGranted: _permissions['accessibility'] ?? false,
          onRequest: () => _requestPermission('accessibility'),
        ),
        _buildPermissionItem(
          context: context,
          icon: Icons.analytics_outlined,
          title: AppLocalizations.of(context).usageStatsPermissionTitle,
          description: AppLocalizations.of(context).usageStatsPermissionDesc,
          isGranted: _permissions['usage_stats'] ?? false,
          onRequest: () => _requestPermission('usage_stats'),
        ),
        _buildPermissionItem(
          context: context,
          icon: Icons.battery_saver_outlined,
          title: AppLocalizations.of(context).batteryOptimizationTitle,
          description: AppLocalizations.of(context).batteryOptimizationDesc,
          isGranted: _keepAlivePermissions['battery_optimization'] ?? false,
          onRequest: () => _requestPermission('battery_optimization'),
        ),
        _buildPermissionItem(
          context: context,
          icon: Icons.power_settings_new_outlined,
          title: AppLocalizations.of(context).autostartPermissionTitle,
          description: AppLocalizations.of(context).autostartPermissionDesc,
          isGranted: _keepAlivePermissions['autostart'] ?? false,
          onRequest: () => _requestPermission('autostart'),
          showBottomBorder: false,
        ),
      ],
    );
  }

  Future<void> _loadLoggingEnabled() async {
    try {
      _loggingEnabled = FlutterLogger.enabled;
      _aiLoggingEnabled = await FlutterLogger.getCategoryEnabled('ai');
      _screenshotLoggingEnabled = await FlutterLogger.getCategoryEnabled(
        'screenshot',
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _updateLoggingEnabled(bool enabled) async {
    try {
      await FlutterLogger.setEnabled(enabled);
      if (mounted) setState(() => _loggingEnabled = enabled);
    } catch (_) {}
  }

  Future<void> _updateAiLoggingEnabled(bool enabled) async {
    try {
      await FlutterLogger.setCategoryEnabled('ai', enabled);
      if (mounted) setState(() => _aiLoggingEnabled = enabled);
    } catch (_) {}
  }

  Future<void> _updateScreenshotLoggingEnabled(bool enabled) async {
    try {
      await FlutterLogger.setCategoryEnabled('screenshot', enabled);
      if (mounted) setState(() => _screenshotLoggingEnabled = enabled);
    } catch (_) {}
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
    WidgetsBinding.instance.removeObserver(this);
    _nsfwDomainController.dispose();
    widget.controller?._detach(this);
    super.dispose();
  }

  Future<void> _loadRenderImagesDuringStreaming() async {
    try {
      final v = await AISettingsService.instance
          .getRenderImagesDuringStreaming();
      if (mounted) setState(() => _renderImagesDuringStreaming = v);
    } catch (_) {}
  }

  Future<void> _updateRenderImagesDuringStreaming(bool enabled) async {
    try {
      await AISettingsService.instance.setRenderImagesDuringStreaming(enabled);
      if (mounted) setState(() => _renderImagesDuringStreaming = enabled);
    } catch (_) {}
  }

  Future<void> _loadAiChatPerfOverlayEnabled() async {
    try {
      final v = await AISettingsService.instance.getAiChatPerfOverlayEnabled();
      if (mounted) setState(() => _aiChatPerfOverlayEnabled = v);
    } catch (_) {}
  }

  Future<void> _updateAiChatPerfOverlayEnabled(bool enabled) async {
    try {
      await AISettingsService.instance.setAiChatPerfOverlayEnabled(enabled);
      if (mounted) setState(() => _aiChatPerfOverlayEnabled = enabled);
    } catch (_) {}
  }

  Future<void> _loadDynamicEntryLogIconEnabled() async {
    try {
      final bool enabled = await UserSettingsService.instance.getBool(
        UserSettingKeys.dynamicEntryLogIconEnabled,
        defaultValue: false,
      );
      if (mounted) {
        setState(() => _dynamicEntryLogIconEnabled = enabled);
      }
    } catch (_) {}
  }

  Future<void> _updateDynamicEntryLogIconEnabled(bool enabled) async {
    try {
      await UserSettingsService.instance.setBool(
        UserSettingKeys.dynamicEntryLogIconEnabled,
        enabled,
      );
      if (mounted) {
        setState(() => _dynamicEntryLogIconEnabled = enabled);
      }
    } catch (_) {}
  }

  String _formatImportExportStageLabel(
    AppLocalizations t,
    String? stage,
    bool isExport,
  ) {
    final String code = t.localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');

    if (stage == 'scanning') {
      if (isZh) {
        return isExport ? '正在扫描文件…' : '正在扫描压缩包…';
      }
      return isExport ? 'Scanning files...' : 'Scanning archive...';
    }
    if (stage == 'packing') {
      if (isZh) {
        return '正在打包数据…';
      }
      return 'Packing data...';
    }
    if (stage == 'extracting') {
      if (isZh) {
        return '正在解压数据…';
      }
      return 'Extracting data...';
    }
    if (stage == 'merge_extracting') {
      return _formatImportExportStageLabel(t, 'extracting', isExport);
    }
    if (stage == 'merge_copying_files') {
      return t.mergeProgressCopying;
    }
    if (stage == 'merge_copying_generic') {
      return t.mergeProgressCopyingGeneric;
    }
    if (stage == 'merge_shard_databases') {
      return t.mergeProgressMergingDb;
    }
    if (stage == 'merge_finalizing') {
      return t.mergeProgressFinalizing;
    }

    if (isZh) {
      return isExport ? '导出数据进行中…' : '导入数据进行中…';
    }
    return isExport ? 'Exporting data...' : 'Importing data...';
  }

  String _importExportDialogTitle(AppLocalizations t, bool isExport) {
    final String code = t.localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    if (isZh) {
      return isExport ? '正在导出数据' : '正在导入数据';
    }
    return isExport ? 'Exporting data' : 'Importing data';
  }

  String _importExportDoNotCloseHint(AppLocalizations t) {
    final String code = t.localeName.toLowerCase();
    final bool isZh = code.startsWith('zh');
    if (isZh) {
      return '请保持应用打开，不要离开此页面。';
    }
    return 'Please keep the app open and do not leave this page.';
  }

  Future<void> _showImportExportOverlayDialog({
    required bool isExport,
    required ValueListenable<double> progressNotifier,
    required ValueListenable<String?> stageNotifier,
    required ValueListenable<String?> entryNotifier,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'import_export_progress',
      barrierColor: Colors.black54,
      pageBuilder: (BuildContext dialogContext, _, __) {
        final ThemeData theme = Theme.of(dialogContext);
        final AppLocalizations t = AppLocalizations.of(dialogContext);
        final String title = _importExportDialogTitle(t, isExport);

        return WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacing4),
                  child: ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (_, double value, __) {
                      // 不再展示百分比进度，统一使用循环进度条
                      return ValueListenableBuilder<String?>(
                        valueListenable: stageNotifier,
                        builder: (_, String? stage, ___) {
                          final String stageLabel =
                              _formatImportExportStageLabel(t, stage, isExport);
                          return ValueListenableBuilder<String?>(
                            valueListenable: entryNotifier,
                            builder: (_, String? entry, ____) {
                              final String? entryLabel =
                                  _shortenImportExportEntry(entry);
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: AppTheme.spacing3),
                                  Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppTheme.spacing2),
                                  Text(
                                    stageLabel,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (entryLabel != null) ...[
                                    const SizedBox(height: AppTheme.spacing1),
                                    Text(
                                      entryLabel,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontFamily: 'monospace',
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                  const SizedBox(height: AppTheme.spacing2),
                                  Text(
                                    _importExportDoNotCloseHint(t),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String? _shortenImportExportEntry(String? entry) {
    if (entry == null || entry.isEmpty) return null;
    const int maxLen = 48;
    if (entry.length <= maxLen) return entry;
    return '...' + entry.substring(entry.length - maxLen);
  }

  Future<void> _showNativeExportDialog() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'native_export_progress',
      barrierColor: Colors.black54,
      pageBuilder: (BuildContext dialogContext, _, __) {
        final ThemeData theme = Theme.of(dialogContext);
        final AppLocalizations t = AppLocalizations.of(dialogContext);
        final String title = _importExportDialogTitle(t, true);
        final String hint = _importExportDoNotCloseHint(t);
        return WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacing4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      const UIProgress(value: null, height: 4),
                      const SizedBox(height: AppTheme.spacing2),
                      Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 导出数据到下载目录
  Future<void> _exportDatabase() async {
    if (_exportingDb) return;
    setState(() {
      _exportingDb = true;
    });
    try {
      await FlutterLogger.nativeInfo('UI_EXPORT', '开始导出');
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const ExportBackupPage()),
      );
    } catch (e) {
      if (!mounted) return;
      await showUIDialog<void>(
        context: context,
        barrierDismissible: false,
        title: '导出失败',
        content: Text(e.toString()),
        actions: const [
          UIDialogAction(text: '确定', style: UIDialogActionStyle.primary),
        ],
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportingDb = false;
        });
      }
    }
  }

  Future<void> _importData() async {
    if (_importingData) return;

    final _ImportMode? mode = await _selectImportMode();
    if (!mounted) return;
    if (mode == null) {
      await FlutterLogger.nativeWarn('UI_IMPORT', '用户取消选择导入模式');
      return;
    }

    setState(() {
      _importingData = true;
    });

    final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);
    final ValueNotifier<String?> stageNotifier = ValueNotifier<String?>(null);
    final ValueNotifier<String?> entryNotifier = ValueNotifier<String?>(null);
    bool overlayShown = false;
    String? selectedFileName;
    String? selectedFilePath;

    try {
      await FlutterLogger.nativeInfo('UI_IMPORT', '打开文件选择器');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: false,
        allowMultiple: false,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        await FlutterLogger.nativeWarn('UI_IMPORT', '用户取消选择文件');
        return;
      }

      final file = result.files.first;
      final Uint8List? bytes = file.bytes;
      final String? path = file.path;
      selectedFileName = file.name;
      selectedFilePath = path;
      await FlutterLogger.nativeInfo(
        'UI_IMPORT',
        '已选择 文件名=${file.name} 大小=${bytes?.length ?? 0} 路径=${path ?? ''}',
      );

      unawaited(
        _showImportExportOverlayDialog(
          isExport: false,
          progressNotifier: progressNotifier,
          stageNotifier: stageNotifier,
          entryNotifier: entryNotifier,
        ),
      );
      overlayShown = true;

      // 停止截图服务以避免导入过程中的DB/FS冲突
      final bool wasRunning = ScreenshotService.instance.isRunning;
      if (wasRunning) {
        await FlutterLogger.nativeInfo('UI_IMPORT', '导入前停止服务');
        try {
          await ScreenshotService.instance.stopScreenshotService();
        } catch (_) {}
      }

      void handleProgress(ImportExportProgress p) {
        progressNotifier.value = p.value;
        stageNotifier.value = p.stage;
        entryNotifier.value = p.currentEntry;
      }

      Map<String, dynamic>? importRes;
      MergeReport? mergeReport;

      if (mode == _ImportMode.merge) {
        mergeReport = await _screenshotDatabase.mergeDataFromZip(
          zipPath: path,
          zipBytes: bytes,
          onProgress: handleProgress,
          throwOnError: true,
        );
      } else {
        // 覆盖导入优先走原生 ZIP 导入（依赖 zipPath），无法获取路径时回退到 Dart 流式实现
        if (path != null && path.isNotEmpty) {
          stageNotifier.value = 'import_native_zip';
          progressNotifier.value = 0.02;
          final res = await _screenshotDatabase.importDataFromZip(
            zipPath: path,
            zipBytes: null,
            overwrite: true,
            onProgress: handleProgress,
          );
          importRes = res;
          progressNotifier.value = 1.0;
        } else if (bytes != null && bytes.isNotEmpty) {
          importRes = await _screenshotDatabase.importDataFromZipStreaming(
            zipBytes: bytes,
            onProgress: handleProgress,
          );
        }
      }

      if (!mounted) return;
      if (mode == _ImportMode.merge) {
        if (mergeReport != null) {
          await _resyncScreenshotSettingsAfterImport();
          await FlutterLogger.nativeInfo(
            'UI_IMPORT',
            '合并成功 插入截图=${mergeReport.insertedScreenshots} 跳过重复=${mergeReport.skippedScreenshotDuplicates}',
          );
          await ScreenshotService.instance.invalidateStatsCache();
          ScreenshotService.instance.invalidateAvailableDayCountCache();
          await _showMergeResultDialog(mergeReport);
        } else {
          await FlutterLogger.nativeWarn('UI_IMPORT', '合并结果为 null');
          await showUIDialog<void>(
            context: context,
            barrierDismissible: false,
            title: AppLocalizations.of(context).importFailedTitle,
            message: AppLocalizations.of(context).importFailedCheckZip,
            actions: [
              UIDialogAction(
                text: AppLocalizations.of(context).dialogOk,
                style: UIDialogActionStyle.primary,
              ),
            ],
          );
        }
      } else if (importRes != null) {
        await _resyncScreenshotSettingsAfterImport();
        await FlutterLogger.nativeInfo(
          'UI_IMPORT',
          '导入成功 已解压=' +
              (importRes['extracted']?.toString() ?? 'null') +
              ' 目标=' +
              (importRes['targetDir']?.toString() ?? ''),
        );
        await ScreenshotService.instance.invalidateStatsCache();
        ScreenshotService.instance.invalidateAvailableDayCountCache();
        final bool requiresRestart = importRes['requiresRestart'] == true;
        await showUIDialog<void>(
          context: context,
          barrierDismissible: false,
          title: AppLocalizations.of(context).importCompleteTitle,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context).dataExtractedTo),
              const SizedBox(height: AppTheme.spacing2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.spacing3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Text(
                  (importRes['targetDir'] as String?) ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (requiresRestart) ...[
                const SizedBox(height: AppTheme.spacing3),
                Text(
                  Localizations.localeOf(context).languageCode.toLowerCase() ==
                          'zh'
                      ? '本次导入已恢复偏好设置或应用级目录。为了让这些内容立即生效，建议重启应用一次。'
                      : 'This restore updated preferences or app-level directories. Restart the app once so every change takes effect immediately.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            UIDialogAction(
              text: AppLocalizations.of(context).dialogOk,
              style: UIDialogActionStyle.primary,
            ),
          ],
        );
      } else {
        await FlutterLogger.nativeWarn('UI_IMPORT', '导入结果为 null');
        await showUIDialog<void>(
          context: context,
          barrierDismissible: false,
          title: AppLocalizations.of(context).importFailedTitle,
          message: AppLocalizations.of(context).importFailedCheckZip,
          actions: [
            UIDialogAction(
              text: AppLocalizations.of(context).dialogOk,
              style: UIDialogActionStyle.primary,
            ),
          ],
        );
      }
    } catch (e, st) {
      if (!mounted) return;
      await FlutterLogger.handle(e, st, tag: 'UI_IMPORT', message: '导入异常');

      final l10n = AppLocalizations.of(context);
      final detailText = StringBuffer()
        ..writeln('fileName: ${selectedFileName ?? ''}')
        ..writeln('path: ${selectedFilePath ?? ''}')
        ..writeln('stage: ${stageNotifier.value ?? ''}')
        ..writeln('entry: ${entryNotifier.value ?? ''}')
        ..writeln('error: ${e.runtimeType}: $e')
        ..writeln('stackTrace:')
        ..writeln(st);

      await showUIDialog<void>(
        context: context,
        barrierDismissible: false,
        title: l10n.importFailedTitle,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: SelectableText(
              detailText.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ),
        actions: [
          UIDialogAction(
            text: l10n.copyResultsTooltip,
            closeOnPress: false,
            onPressed: (_) async {
              final text = detailText.toString();
              try {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.copySuccess)));
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.copyFailed)));
              }
            },
          ),
          UIDialogAction(
            text: l10n.dialogOk,
            style: UIDialogActionStyle.primary,
          ),
        ],
      );
    } finally {
      try {
        await FlutterLogger.nativeInfo('UI_IMPORT', '导入流程结束');
      } catch (_) {}
      if (mounted) {
        setState(() {
          _importingData = false;
        });
      }
      try {
        if (mounted && overlayShown) {
          final NavigatorState nav = Navigator.of(context, rootNavigator: true);
          if (nav.canPop()) {
            nav.pop();
          }
        }
      } catch (_) {}
      progressNotifier.dispose();
      stageNotifier.dispose();
      entryNotifier.dispose();
    }
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

  Future<void> _loadAllPermissions() async {
    await Future.wait([_loadPermissions(), _loadKeepAlivePermissions()]);
  }

  Future<void> _loadPermissions() async {
    try {
      final permissions = await _permissionService.checkAllPermissions();
      if (mounted) {
        setState(() {
          _permissions = permissions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadKeepAlivePermissions() async {
    try {
      if (mounted) {
        setState(() {
          _isLoadingKeepAlive = true;
        });
      }

      // 使用与引导页面相同的权限检测方法和通道
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      final result = await platform.invokeMethod('getPermissionStatus');
      if (mounted) {
        setState(() {
          _keepAlivePermissions = Map<String, bool>.from(result ?? {});
          _isLoadingKeepAlive = false;
        });
      }
      print('保活权限状态更新完成: ' + _keepAlivePermissions.toString());
    } catch (e) {
      print('加载保活权限失败: $e');
      if (mounted) {
        setState(() {
          _keepAlivePermissions = {
            'battery_optimization': false,
            'autostart': false,
            'background': false,
            'battery_whitelist_actual': false,
          };
          _isLoadingKeepAlive = false;
        });
      }
    }
  }

  /// 启动电池权限定时检查
  void _startBatteryPermissionCheck() {
    print('启动电池权限定时检查...');
    _batteryCheckCount = 0;
    _batteryPermissionTimer?.cancel();
    _batteryPermissionTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) async {
        _batteryCheckCount++;
        print('电池权限检查第 ' + _batteryCheckCount.toString() + ' 次');
        try {
          const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
          final permissionStatus = await platform.invokeMethod(
            'getPermissionStatus',
          );
          final newBatteryStatus =
              permissionStatus?['battery_optimization'] ?? false;
          final oldBatteryStatus =
              _keepAlivePermissions['battery_optimization'] ?? false;
          print(
            '定时检查 - 旧状态: ' +
                oldBatteryStatus.toString() +
                ', 新状态: ' +
                newBatteryStatus.toString(),
          );
          if (newBatteryStatus != oldBatteryStatus) {
            print('检测到电池权限状态变化，更新UI');
            await _loadKeepAlivePermissions();
            if (newBatteryStatus) {
              print('电池权限已授权，停止定时检查');
              timer.cancel();
            }
          }
        } catch (e) {
          print('定时检查权限失败: ' + e.toString());
        }
      },
    );
  }

  /// 停止电池权限定时检查
  void _stopBatteryPermissionCheck() {
    _batteryPermissionTimer?.cancel();
    _batteryPermissionTimer = null;
    _batteryCheckCount = 0;
  }

  /// 显示自启动权限确认弹窗
  Future<bool> _showAutoStartConfirmDialog() async {
    return await showUIDialog<bool>(
          context: context,
          barrierDismissible: false,
          title: AppLocalizations.of(context).confirmPermissionSettingsTitle,
          message: AppLocalizations.of(context).confirmAutostartQuestion,
          actions: [
            UIDialogAction<bool>(
              text: AppLocalizations.of(context).notYet,
              result: false,
            ),
            UIDialogAction<bool>(
              text: AppLocalizations.of(context).done,
              style: UIDialogActionStyle.primary,
              result: true,
            ),
          ],
        ) ??
        false;
  }

  Future<void> _requestPermission(String permissionType) async {
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      switch (permissionType) {
        case 'storage':
          await _permissionService.requestStoragePermission();
          break;
        case 'notification':
          await _permissionService.requestNotificationPermission();
          break;
        case 'accessibility':
          await _permissionService.requestAccessibilityPermission();
          break;
        case 'usage_stats':
          await _permissionService.requestUsageStatsPermission();
          break;
        case 'mediaProjection':
          // 不再需要 MediaProjection 权限
          UINotifier.info(
            context,
            AppLocalizations.of(context).noMediaProjectionNeeded,
          );
          break;
        case 'battery_optimization':
          if (mounted) {
            UINotifier.info(
              context,
              AppLocalizations.of(context).pleaseCompleteInSystemSettings,
              duration: const Duration(seconds: 2),
            );
          }
          await platform.invokeMethod('openBatteryOptimizationSettings');
          _startBatteryPermissionCheck();
          break;
        case 'autostart':
          await platform.invokeMethod('openAutoStartSettings');
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            final confirmed = await _showAutoStartConfirmDialog();
            if (confirmed) {
              await platform.invokeMethod('markPermissionConfigured', {
                'type': 'autostart',
              });
              await _loadKeepAlivePermissions();
              if (mounted) {
                UINotifier.success(
                  context,
                  AppLocalizations.of(context).autostartPermissionMarked,
                  duration: const Duration(seconds: 2),
                );
              }
            }
          }
          break;
      }

      // 延迟刷新权限状态
      await Future.delayed(const Duration(seconds: 1));
      if (permissionType == 'storage' ||
          permissionType == 'notification' ||
          permissionType == 'accessibility' ||
          permissionType == 'mediaProjection') {
        _loadPermissions();
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).requestPermissionFailed(e.toString()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_subPage != _SettingsSubPage.home) {
          _switchSubPage(_SettingsSubPage.home);
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: _buildSettingsAppBar(context),
        backgroundColor: _settingsBackgroundColor(context),
        body: _buildSettingsBody(context),
      ),
    );
  }

  PreferredSizeWidget _buildSettingsAppBar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String title = l10n.settingsTitle;
    if (_subPage == _SettingsSubPage.permissions) {
      title = l10n.permissionsSectionTitle;
    } else if (_subPage == _SettingsSubPage.display) {
      title = l10n.displaySectionTitle;
    } else if (_subPage == _SettingsSubPage.screenshot) {
      title = l10n.screenshotSectionTitle;
    } else if (_subPage == _SettingsSubPage.segmentSummary) {
      title = l10n.segmentSummarySectionTitle;
    } else if (_subPage == _SettingsSubPage.dailyReminder) {
      title = l10n.dailyReminderSectionTitle;
    } else if (_subPage == _SettingsSubPage.dataBackup) {
      title = l10n.dataBackupSectionTitle;
    } else if (_subPage == _SettingsSubPage.advanced) {
      title = l10n.advancedSectionTitle;
    }

    final bool canPop = Navigator.of(context).canPop();
    return AppBar(
      toolbarHeight: 36,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leadingWidth: kToolbarHeight,
      leading: _subPage == _SettingsSubPage.home
          ? (canPop
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                : const SizedBox.shrink())
          : IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _switchSubPage(_SettingsSubPage.home),
            ),
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.only(top: 2.0),
        child: Text(title),
      ),
      backgroundColor: _settingsBackgroundColor(context),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      actions: [
        if (_subPage == _SettingsSubPage.permissions)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllPermissions,
            tooltip: l10n.refreshPermissionStatus,
          ),
        if (_subPage != _SettingsSubPage.permissions)
          const SizedBox(width: kToolbarHeight),
      ],
    );
  }

  Widget _buildSettingsBody(BuildContext context) {
    switch (_subPage) {
      case _SettingsSubPage.home:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildNavItem(
                  context: context,
                  icon: Icons.verified_user_outlined,
                  title: AppLocalizations.of(context).permissionsSectionTitle,
                  showBottomBorder: true,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.permissions),
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.palette_outlined,
                  title: AppLocalizations.of(context).displaySectionTitle,
                  showBottomBorder: true,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.display),
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.photo_library_outlined,
                  title: AppLocalizations.of(context).screenshotSectionTitle,
                  showBottomBorder: true,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.screenshot),
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.insights_outlined,
                  title: AppLocalizations.of(
                    context,
                  ).segmentSummarySectionTitle,
                  showBottomBorder: true,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.segmentSummary),
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.notifications_outlined,
                  title: AppLocalizations.of(context).dailyReminderSectionTitle,
                  showBottomBorder: true,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.dailyReminder),
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.storage_outlined,
                  title: AppLocalizations.of(context).dataBackupSectionTitle,
                  showBottomBorder: false,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.dataBackup),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing3),
            _buildCard(
              context: context,
              children: [
                _buildNavItem(
                  context: context,
                  icon: Icons.tune,
                  title: AppLocalizations.of(context).advancedSectionTitle,
                  showBottomBorder: false,
                  isRootPageItem: true,
                  onTap: () => _switchSubPage(_SettingsSubPage.advanced),
                ),
              ],
            ),
          ],
        );
      case _SettingsSubPage.permissions:
        if (_isLoading || _isLoadingKeepAlive) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [_buildPermissionsDropdown(context)],
            ),
          ],
        );
      case _SettingsSubPage.display:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildThemeModeItem(context),
                _buildPrivacyModeItem(context),
                _buildNsfwEntryItem(context),
              ],
            ),
          ],
        );
      case _SettingsSubPage.screenshot:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildScreenshotIntervalItem(context),
                _buildScreenshotQualityItem(context),
                _buildScreenshotExpireItem(context),
              ],
            ),
          ],
        );
      case _SettingsSubPage.segmentSummary:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildSegmentSampleItem(context),
                _buildSegmentDurationItem(context),
                _buildDynamicMergeMaxSpanItem(context),
                _buildDynamicMergeMaxGapItem(context),
                _buildDynamicMergeMaxImagesItem(context),
                _buildAiRequestIntervalItem(context),
                _buildSegmentsJsonAutoRetryMaxItem(context),
                _buildAiRawResponseCleanupItem(context),
              ],
            ),
          ],
        );
      case _SettingsSubPage.dailyReminder:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildDailyNotifyItem(context),
                _buildDailyNotifyBannerItem(context),
                _buildDailyNotifyTestItem(context),
              ],
            ),
          ],
        );
      case _SettingsSubPage.dataBackup:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildStorageAnalysisItem(context),
                _buildExportItem(context),
                _buildImportItem(context),
                _buildImportDiagnosticsItem(context),
                _buildRecalculateAllItem(context),
              ],
            ),
          ],
        );
      case _SettingsSubPage.advanced:
        return ListView(
          padding: _settingsListPadding(),
          children: [
            _buildCard(
              context: context,
              children: [
                _buildStreamRenderImagesItem(context),
                _buildAiChatPerfOverlayItem(context),
                _buildDynamicEntryLogIconItem(context),
                _buildLoggingToggleItem(context),
              ],
            ),
          ],
        );
    }
  }

  Widget _buildCard({
    required BuildContext context,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  EdgeInsets _settingsListPadding() {
    return const EdgeInsets.fromLTRB(
      AppTheme.spacing4,
      AppTheme.spacing2,
      AppTheme.spacing4,
      AppTheme.spacing4,
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required bool showBottomBorder,
    bool isRootPageItem = false,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final borderSide = _settingsDividerSide(context);
    final EdgeInsetsGeometry padding = EdgeInsets.symmetric(
      horizontal: AppTheme.spacing4,
      vertical: isRootPageItem ? AppTheme.spacing3 : AppTheme.spacing3 - 2,
    );
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          border: Border(
            bottom: showBottomBorder ? borderSide : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            _buildSettingsLeadingIcon(context, icon),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacing2),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsLeadingIcon(
    BuildContext context,
    IconData icon, {
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 20,
      height: 20,
      child: Center(
        child: Icon(
          icon,
          color: color ?? colorScheme.onSurfaceVariant,
          size: 18,
        ),
      ),
    );
  }

  // ===== 时间段总结设置 UI =====
  Widget _buildSegmentSampleItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.photo_library_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).segmentSampleIntervalTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).segmentSampleIntervalDesc(_segmentSampleIntervalSec),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showSegmentSampleDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentDurationItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.schedule_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).segmentDurationTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).segmentDurationDesc(_segmentDurationMin),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showSegmentDurationDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  // ===== 动态合并限制 UI =====
  Widget _buildDynamicMergeMaxSpanItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: _settingsDividerSide(context),
          bottom: _settingsDividerSide(context),
        ),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.merge_type_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).dynamicMergeMaxSpanTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).dynamicMergeMaxSpanDesc(_dynamicMergeMaxSpanMin),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showDynamicMergeMaxSpanDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicMergeMaxGapItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.more_time_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).dynamicMergeMaxGapTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).dynamicMergeMaxGapDesc(_dynamicMergeMaxGapMin),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showDynamicMergeMaxGapDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicMergeMaxImagesItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.image_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).dynamicMergeMaxImagesTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).dynamicMergeMaxImagesDesc(_dynamicMergeMaxImages),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showDynamicMergeMaxImagesDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  // ===== AI请求间隔设置 UI =====
  Widget _buildAiRequestIntervalItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.speed_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).aiRequestIntervalTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).aiRequestIntervalDesc(_aiRequestIntervalSec),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showAiRequestIntervalDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  // ===== 动态(segments) structured_json 自动重试次数 =====
  Widget _buildSegmentsJsonAutoRetryMaxItem(BuildContext context) {
    final bool isZh = (() {
      try {
        return Localizations.localeOf(
          context,
        ).languageCode.toLowerCase().startsWith('zh');
      } catch (_) {
        return true;
      }
    })();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.autorenew_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isZh ? '自动重试次数' : 'Auto Retry Times',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  isZh
                      ? 'structured_json 解析失败时自动重试（0=关闭，默认1）。当前：$_segmentsJsonAutoRetryMax'
                      : 'Auto retry when structured_json fails to parse (0=off, default 1). Current: $_segmentsJsonAutoRetryMax',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showSegmentsJsonAutoRetryMaxDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  bool _isZhLocale(BuildContext context) {
    try {
      return Localizations.localeOf(
        context,
      ).languageCode.toLowerCase().startsWith('zh');
    } catch (_) {
      return true;
    }
  }

  Widget _buildAiRawResponseCleanupItem(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.cleaning_services_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.rawResponseCleanupTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            l10n.rawResponseCleanupKeepLabel,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(width: AppTheme.spacing1),
                          GestureDetector(
                            onTap: _showAiRawResponseCleanupDaysDialog,
                            child: Text(
                              l10n.rawResponseCleanupRetentionDays(
                                _aiRawResponseCleanupDays,
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing1),
                          Flexible(
                            child: Text(
                              l10n.rawResponseCleanupDesc,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: -1,
                  right: 0,
                  child: Transform.scale(
                    scale: 0.9,
                    child: Switch(
                      value: _aiRawResponseCleanupEnabled,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) async {
                        if (v) {
                          _showAiRawResponseCleanupEnableConfirmDialog();
                        } else {
                          setState(() {
                            _aiRawResponseCleanupEnabled = false;
                          });
                          await _saveAiRawResponseCleanupSettings();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(BuildContext context, ThemeMode mode) {
    final AppLocalizations t = AppLocalizations.of(context);
    switch (mode) {
      case ThemeMode.system:
        return t.themeModeAuto;
      case ThemeMode.light:
        return t.themeModeLight;
      case ThemeMode.dark:
        return t.themeModeDark;
    }
  }

  Widget _buildThemeModeItem(BuildContext context) {
    final String currentMode = _themeModeLabel(
      context,
      widget.themeService.themeMode,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.brightness_6_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).themeModeTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  currentMode,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showThemeModeSheet,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(currentMode),
          ),
        ],
      ),
    );
  }

  void _showThemeModeSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        final ThemeMode currentMode = widget.themeService.themeMode;
        final BorderSide dividerSide = BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.45),
          width: 0.8,
        );

        Widget buildOption({
          required ThemeMode mode,
          required IconData icon,
          required String label,
          required bool showDivider,
        }) {
          final bool selected = currentMode == mode;
          return InkWell(
            onTap: () async {
              await widget.themeService.setThemeMode(mode);
              if (mounted) {
                Navigator.of(sheetContext).pop();
                setState(() {});
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
                vertical: AppTheme.spacing3,
              ),
              decoration: BoxDecoration(
                border: showDivider ? Border(bottom: dividerSide) : null,
                color: selected
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
            ),
          );
        }

        return UISheetSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppTheme.spacing3),
              const UISheetHandle(),
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacing4),
                child: Text(
                  AppLocalizations.of(context).themeModeTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              buildOption(
                mode: ThemeMode.system,
                icon: Icons.brightness_auto_outlined,
                label: _themeModeLabel(context, ThemeMode.system),
                showDivider: true,
              ),
              buildOption(
                mode: ThemeMode.light,
                icon: Icons.brightness_high_outlined,
                label: _themeModeLabel(context, ThemeMode.light),
                showDivider: true,
              ),
              buildOption(
                mode: ThemeMode.dark,
                icon: Icons.brightness_4_outlined,
                label: _themeModeLabel(context, ThemeMode.dark),
                showDivider: false,
              ),
              const SizedBox(height: AppTheme.spacing2),
            ],
          ),
        );
      },
    );
  }

  void _showAiRequestIntervalDialog() {
    final TextEditingController controller = TextEditingController(
      text: _aiRequestIntervalSec.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).aiRequestIntervalTitle,
      content: _numberField(
        controller,
        hint: AppLocalizations.of(context).intervalInputHint,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed < 1) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).intervalInvalidError,
              );
              return;
            }
            final v = parsed.clamp(1, 60);
            try {
              const platform = MethodChannel(
                'com.fqyw.screen_memo/accessibility',
              );
              await platform.invokeMethod('setAiRequestIntervalSec', {
                'seconds': v,
              });
              if (mounted)
                setState(() {
                  _aiRequestIntervalSec = v;
                });
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                UINotifier.success(
                  ctx,
                  AppLocalizations.of(ctx).intervalSavedSuccess(v),
                );
              }
            } catch (e) {
              if (ctx.mounted)
                UINotifier.error(
                  ctx,
                  AppLocalizations.of(
                    ctx,
                  ).requestPermissionFailed(e.toString()),
                );
            }
          },
        ),
      ],
    );
  }

  void _showSegmentsJsonAutoRetryMaxDialog() {
    final TextEditingController controller = TextEditingController(
      text: _segmentsJsonAutoRetryMax.toString(),
    );
    final l10n = AppLocalizations.of(context);

    showUIDialog<void>(
      context: context,
      title: l10n.segmentsJsonAutoRetryTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.segmentsJsonAutoRetryDesc,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacing3),
          _numberField(controller, hint: l10n.segmentsJsonAutoRetryHint),
        ],
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).resetToDefault,
          style: UIDialogActionStyle.destructive,
          closeOnPress: false,
          onPressed: (ctx) async {
            const int v = 1;
            try {
              await AISettingsService.instance.setSegmentsJsonAutoRetryMax(v);
              if (mounted) {
                setState(() {
                  _segmentsJsonAutoRetryMax = v;
                });
              }
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                UINotifier.success(
                  ctx,
                  AppLocalizations.of(ctx).resetToDefaultValue(v),
                );
              }
            } catch (e) {
              if (ctx.mounted) {
                UINotifier.error(
                  ctx,
                  AppLocalizations.of(ctx).saveFailedError(e.toString()),
                );
              }
            }
          },
        ),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).numberInputRequired,
              );
              return;
            }
            final v = parsed.clamp(0, 5);
            try {
              await AISettingsService.instance.setSegmentsJsonAutoRetryMax(v);
              if (mounted) {
                setState(() {
                  _segmentsJsonAutoRetryMax = v;
                });
              }
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                UINotifier.success(ctx, AppLocalizations.of(ctx).valueSaved(v));
              }
            } catch (e) {
              if (ctx.mounted) {
                UINotifier.error(
                  ctx,
                  AppLocalizations.of(ctx).saveFailedError(e.toString()),
                );
              }
            }
          },
        ),
      ],
    );
  }

  void _showAiRawResponseCleanupEnableConfirmDialog() {
    final l10n = AppLocalizations.of(context);
    showUIDialog<void>(
      context: context,
      title: l10n.rawResponseCleanupEnableTitle,
      content: Text(
        l10n.rawResponseCleanupEnableMessage(_aiRawResponseCleanupDays),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: l10n.rawResponseCleanupEnableAction,
          style: UIDialogActionStyle.primary,
          onPressed: (ctx) async {
            setState(() {
              _aiRawResponseCleanupEnabled = true;
            });
            await _saveAiRawResponseCleanupSettings();
            unawaited(
              AISettingsService.instance.cleanupExpiredRawResponsesIfNeeded(
                force: true,
              ),
            );
          },
        ),
      ],
    );
  }

  void _showAiRawResponseCleanupDaysDialog() {
    final TextEditingController controller = TextEditingController(
      text: _aiRawResponseCleanupDays.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).rawResponseRetentionDaysTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: AppLocalizations.of(
                  context,
                ).rawResponseRetentionDaysLabel,
                hintText: AppLocalizations.of(
                  context,
                ).rawResponseRetentionDaysHint,
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(AppTheme.spacing3),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: AppTheme.fontSizeBase,
              ),
            ),
          ),
        ],
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final int? days = int.tryParse(controller.text.trim());
            if (days == null || days < 1) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(context).rawResponseRetentionDaysHint,
              );
              return;
            }
            setState(() {
              _aiRawResponseCleanupDays = days;
            });
            await _saveAiRawResponseCleanupSettings();
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(
                  context,
                ).rawResponseRetentionUpdatedDays(days),
              );
            }
            if (_aiRawResponseCleanupEnabled) {
              unawaited(
                AISettingsService.instance.cleanupExpiredRawResponsesIfNeeded(
                  force: true,
                ),
              );
            }
          },
        ),
      ],
    );
  }

  void _showDynamicMergeMaxSpanDialog() {
    final TextEditingController controller = TextEditingController(
      text: _dynamicMergeMaxSpanMin.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).dynamicMergeMaxSpanTitle,
      content: _numberField(
        controller,
        hint: AppLocalizations.of(context).dynamicMergeLimitInputHint,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed < 0) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).dynamicMergeLimitInvalidError,
              );
              return;
            }
            final v = parsed.clamp(0, 7 * 24 * 60);
            final ok = await _saveDynamicMergeLimits(
              maxSpanMin: v,
              maxGapMin: _dynamicMergeMaxGapMin,
              maxImages: _dynamicMergeMaxImages,
            );
            if (ctx.mounted && ok) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, AppLocalizations.of(ctx).saveSuccess);
            }
          },
        ),
      ],
    );
  }

  void _showDynamicMergeMaxGapDialog() {
    final TextEditingController controller = TextEditingController(
      text: _dynamicMergeMaxGapMin.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).dynamicMergeMaxGapTitle,
      content: _numberField(
        controller,
        hint: AppLocalizations.of(context).dynamicMergeLimitInputHint,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed < 0) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).dynamicMergeLimitInvalidError,
              );
              return;
            }
            final v = parsed.clamp(0, 7 * 24 * 60);
            final ok = await _saveDynamicMergeLimits(
              maxSpanMin: _dynamicMergeMaxSpanMin,
              maxGapMin: v,
              maxImages: _dynamicMergeMaxImages,
            );
            if (ctx.mounted && ok) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, AppLocalizations.of(ctx).saveSuccess);
            }
          },
        ),
      ],
    );
  }

  void _showDynamicMergeMaxImagesDialog() {
    final TextEditingController controller = TextEditingController(
      text: _dynamicMergeMaxImages.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).dynamicMergeMaxImagesTitle,
      content: _numberField(
        controller,
        hint: AppLocalizations.of(context).dynamicMergeLimitInputHint,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed < 0) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).dynamicMergeLimitInvalidError,
              );
              return;
            }
            final v = parsed.clamp(0, 100000);
            final ok = await _saveDynamicMergeLimits(
              maxSpanMin: _dynamicMergeMaxSpanMin,
              maxGapMin: _dynamicMergeMaxGapMin,
              maxImages: v,
            );
            if (ctx.mounted && ok) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, AppLocalizations.of(ctx).saveSuccess);
            }
          },
        ),
      ],
    );
  }

  Future<void> _loadSegmentSettings() async {
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      final res = await platform.invokeMethod('getSegmentSettings');
      final map = Map<String, dynamic>.from(res ?? {});
      if (mounted) {
        setState(() {
          _segmentSampleIntervalSec = ((map['sampleIntervalSec'] as int?) ?? 20)
              .clamp(5, 3600);
          final durSec = ((map['segmentDurationSec'] as int?) ?? 300).clamp(
            60,
            24 * 3600,
          );
          _segmentDurationMin = (durSec / 60).round();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDynamicMergeLimits() async {
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      final res = await platform.invokeMethod('getDynamicMergeLimits');
      final map = Map<String, dynamic>.from(res ?? {});
      final int spanSec = (map['maxSpanSec'] as int?) ?? 3 * 3600;
      final int gapSec = (map['maxGapSec'] as int?) ?? 3600;
      final int maxImages = (map['maxImages'] as int?) ?? 200;
      if (mounted) {
        setState(() {
          _dynamicMergeMaxSpanMin = ((spanSec / 60).round())
              .clamp(0, 7 * 24 * 60)
              .toInt();
          _dynamicMergeMaxGapMin = ((gapSec / 60).round())
              .clamp(0, 7 * 24 * 60)
              .toInt();
          _dynamicMergeMaxImages = maxImages.clamp(0, 100000).toInt();
        });
      }
    } catch (_) {
      // keep defaults
    }
  }

  // 读取AI请求最小间隔（秒），默认3，最低1
  Future<void> _loadAiRequestInterval() async {
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      final sec = await platform.invokeMethod('getAiRequestIntervalSec');
      final v = (sec as int?) ?? 3;
      if (mounted) {
        setState(() {
          _aiRequestIntervalSec = v.clamp(1, 60);
        });
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _aiRequestIntervalSec = 3;
        });
    }
  }

  Future<void> _loadSegmentsJsonAutoRetryMax() async {
    try {
      final v = await AISettingsService.instance.getSegmentsJsonAutoRetryMax();
      if (mounted) {
        setState(() {
          _segmentsJsonAutoRetryMax = v;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _segmentsJsonAutoRetryMax = 1;
        });
      }
    }
  }

  Future<void> _loadAiRawResponseCleanupSettings() async {
    try {
      final bool enabled = await AISettingsService.instance
          .getRawResponseCleanupEnabled();
      final int days = await AISettingsService.instance
          .getRawResponseCleanupDays();
      if (mounted) {
        setState(() {
          _aiRawResponseCleanupEnabled = enabled;
          _aiRawResponseCleanupDays = days < 1 ? 1 : days;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _aiRawResponseCleanupEnabled = true;
          _aiRawResponseCleanupDays = 30;
        });
      }
    }
  }

  void _showSegmentSampleDialog() {
    final TextEditingController controller = TextEditingController(
      text: _segmentSampleIntervalSec.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).segmentSampleIntervalTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _numberField(
            controller,
            hint: AppLocalizations.of(context).intervalInputHint,
          ),
          // hint removed
        ],
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final v = int.tryParse(controller.text.trim());
            if (v == null || v < 5) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).intervalInvalidError,
              );
              return;
            }
            final ok = await _saveSegmentSettings(
              sample: v,
              durationMin: _segmentDurationMin,
            );
            if (ctx.mounted && ok) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).intervalSavedSuccess(v),
              );
            }
          },
        ),
      ],
    );
  }

  void _showSegmentDurationDialog() {
    final TextEditingController controller = TextEditingController(
      text: _segmentDurationMin.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).segmentDurationTitle,
      content: _numberField(
        controller,
        hint: AppLocalizations.of(context).intervalInputHint,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final v = int.tryParse(controller.text.trim());
            if (v == null || v < 1) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).intervalInvalidError,
              );
              return;
            }
            final ok = await _saveSegmentSettings(
              sample: _segmentSampleIntervalSec,
              durationMin: v,
            );
            if (ctx.mounted && ok) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).expireDaysSavedSuccess(v),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController c, {required String hint}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: hint,
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(AppTheme.spacing3),
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
      ),
    );
  }

  Future<bool> _saveSegmentSettings({
    required int sample,
    required int durationMin,
  }) async {
    final sampleClamped = sample < 5 ? 5 : sample;
    final durationSec = (durationMin <= 0 ? 1 : durationMin) * 60;
    try {
      try {
        await FlutterLogger.nativeInfo(
          'Settings',
          '设置动态参数：sampleIntervalSec=$sampleClamped，segmentDurationSec=$durationSec',
        );
      } catch (_) {}
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      await platform.invokeMethod('setSegmentSettings', {
        'sampleIntervalSec': sampleClamped,
        'segmentDurationSec': durationSec,
      });
      try {
        final res = await platform.invokeMethod('getSegmentSettings');
        await FlutterLogger.nativeInfo(
          'Settings',
          '保存后读取 getSegmentSettings：$res',
        );
      } catch (e) {
        try {
          await FlutterLogger.nativeWarn(
            'Settings',
            '保存后读取 getSegmentSettings 失败：$e',
          );
        } catch (_) {}
      }
      setState(() {
        _segmentSampleIntervalSec = sampleClamped;
        _segmentDurationMin = durationMin;
      });
      return true;
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
      try {
        await FlutterLogger.nativeError('Settings', 'setSegmentSettings 失败：$e');
      } catch (_) {}
      return false;
    }
  }

  Future<void> _saveAiRawResponseCleanupSettings() async {
    try {
      final int days = _aiRawResponseCleanupDays < 1
          ? 1
          : _aiRawResponseCleanupDays;
      await AISettingsService.instance.setRawResponseCleanupEnabled(
        _aiRawResponseCleanupEnabled,
      );
      await AISettingsService.instance.setRawResponseCleanupDays(days);
      if (mounted) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).rawResponseCleanupSaved,
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
    }
  }

  Future<bool> _saveDynamicMergeLimits({
    required int maxSpanMin,
    required int maxGapMin,
    required int maxImages,
  }) async {
    final int spanMinClamped = maxSpanMin < 0 ? 0 : maxSpanMin;
    final int gapMinClamped = maxGapMin < 0 ? 0 : maxGapMin;
    final int maxImagesClamped = maxImages.clamp(0, 100000).toInt();
    final int spanSec = spanMinClamped * 60;
    final int gapSec = gapMinClamped * 60;
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      await platform.invokeMethod('setDynamicMergeLimits', {
        'maxSpanSec': spanSec,
        'maxGapSec': gapSec,
        'maxImages': maxImagesClamped,
      });
      if (mounted) {
        setState(() {
          _dynamicMergeMaxSpanMin = spanMinClamped;
          _dynamicMergeMaxGapMin = gapMinClamped;
          _dynamicMergeMaxImages = maxImagesClamped;
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
      return false;
    }
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppTheme.spacing1,
            bottom: AppTheme.spacing3,
          ),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.8),
              width: 1,
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildPermissionItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onRequest,
    bool showBottomBorder = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBottomBorder
              ? _settingsDividerSide(context)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(
            context,
            isGranted ? Icons.check : icon,
            color: isGranted ? AppTheme.success : null,
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          if (isGranted)
            Text(
              AppLocalizations.of(context).grantedLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            TextButton(
              onPressed: onRequest,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing3,
                  vertical: AppTheme.spacing1 - 1,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: Size.zero,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(AppLocalizations.of(context).authorizeAction),
            ),
        ],
      ),
    );
  }

  Widget _buildStorageAnalysisItem(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.storage_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.storageAnalysisEntryTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.storageAnalysisEntryDesc,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StorageAnalysisPage(),
                ),
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(l10n.actionEnter),
          ),
        ],
      ),
    );
  }

  Widget _buildExportItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.file_download_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).exportDataTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).exportDataDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _exportingDb ? null : _exportDatabase,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: _exportingDb
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(AppLocalizations.of(context).actionExport),
          ),
        ],
      ),
    );
  }

  Widget _buildImportItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.file_upload_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).importDataTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).importDataDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _importingData ? null : _importData,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: _importingData
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(AppLocalizations.of(context).actionImport),
          ),
        ],
      ),
    );
  }

  Widget _buildImportDiagnosticsItem(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.fact_check_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '导入诊断',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '导入完成后自检当前 output/数据库/索引状态，定位“文件存在但无数据”问题',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _importingData
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ImportDiagnosticsPage(),
                      ),
                    );
                  },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(l10n.actionEnter),
          ),
        ],
      ),
    );
  }

  Widget _buildRecalculateAllItem(BuildContext context) {
    final AppLocalizations t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.sync),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.recalculateAllTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  t.recalculateAllDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _recalculatingAll ? null : _recalculateAllStatistics,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: _recalculatingAll
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(t.recalculateAllAction),
          ),
        ],
      ),
    );
  }

  Widget _buildNsfwEntryItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.shield_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).nsfwSettingsSectionTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).blockedDomainListTitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NsfwSettingsPage()),
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionEnter),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyModeItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.privacy_tip_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).privacyModeTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).privacyModeDesc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: _privacyMode,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => _updatePrivacyMode(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoggingToggleItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Row(
                children: [
                  _buildSettingsLeadingIcon(context, Icons.event_note_outlined),
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 72),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).loggingTitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(context).loggingDesc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: -1,
                right: 0,
                child: Transform.scale(
                  scale: 0.9,
                  child: Switch(
                    value: _loggingEnabled,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => _updateLoggingEnabled(v),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing3),
          // 子列表整体：随主开关禁用并灰化
          IgnorePointer(
            ignoring: !_loggingEnabled,
            child: Opacity(
              opacity: _loggingEnabled ? 1.0 : 0.5,
              child: Column(
                children: [
                  // 子项：AI 日志
                  Container(
                    padding: const EdgeInsets.only(
                      left: AppTheme.spacing3,
                      top: AppTheme.spacing3,
                      bottom: AppTheme.spacing3,
                    ),
                    decoration: BoxDecoration(
                      border: Border(bottom: _settingsDividerSide(context)),
                    ),
                    child: Stack(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSettingsLeadingIcon(
                              context,
                              Icons.smart_toy_outlined,
                            ),
                            const SizedBox(width: AppTheme.spacing3),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 72),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      ).loggingAiTitle,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      ).loggingAiDesc,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          top: -1,
                          right: 0,
                          child: Transform.scale(
                            scale: 0.9,
                            child: Switch(
                              value: _aiLoggingEnabled,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) => _updateAiLoggingEnabled(v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 子项：截图日志
                  Container(
                    padding: const EdgeInsets.only(
                      left: AppTheme.spacing3,
                      top: AppTheme.spacing3,
                      bottom: AppTheme.spacing3,
                    ),
                    decoration: BoxDecoration(
                      border: Border(bottom: _settingsDividerSide(context)),
                    ),
                    child: Stack(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSettingsLeadingIcon(
                              context,
                              Icons.image_search_outlined,
                            ),
                            const SizedBox(width: AppTheme.spacing3),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 72),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      ).loggingScreenshotTitle,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      ).loggingScreenshotDesc,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          top: -1,
                          right: 0,
                          child: Transform.scale(
                            scale: 0.9,
                            child: Switch(
                              value: _screenshotLoggingEnabled,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) =>
                                  _updateScreenshotLoggingEnabled(v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamRenderImagesItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildSettingsLeadingIcon(context, Icons.image_outlined),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).streamRenderImagesTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppLocalizations.of(context).streamRenderImagesDesc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: -1,
            right: 0,
            child: Transform.scale(
              scale: 0.9,
              child: Switch(
                value: _renderImagesDuringStreaming,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => _updateRenderImagesDuringStreaming(v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiChatPerfOverlayItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildSettingsLeadingIcon(context, Icons.speed_outlined),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).aiChatPerfOverlayTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppLocalizations.of(context).aiChatPerfOverlayDesc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: -1,
            right: 0,
            child: Transform.scale(
              scale: 0.9,
              child: Switch(
                value: _aiChatPerfOverlayEnabled,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => _updateAiChatPerfOverlayEnabled(v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicEntryLogIconItem(BuildContext context) {
    final bool isZh = AppLocalizations.of(
      context,
    ).localeName.toLowerCase().startsWith('zh');
    final String title = isZh
        ? '动态页每日总结右侧日志图标'
        : 'Dynamic page summary-side log icon';
    final String desc = isZh
        ? '控制动态页中“每日总结”图标右侧日志入口是否显示，默认关闭。'
        : 'Show the log entry next to the daily summary icon on the dynamic page. Off by default.';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildSettingsLeadingIcon(context, Icons.receipt_long_outlined),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: -1,
            right: 0,
            child: Transform.scale(
              scale: 0.9,
              child: Switch(
                value: _dynamicEntryLogIconEnabled,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => _updateDynamicEntryLogIconEnabled(v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotIntervalItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.timer_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).screenshotIntervalTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).screenshotIntervalDesc(_screenshotInterval),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showIntervalDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotQualityItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSettingsLeadingIcon(context, Icons.image_outlined),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Stack(
                  children: [
                    // 文本区域右侧预留空间，避免与右上角开关重叠
                    Padding(
                      padding: const EdgeInsets.only(right: 72),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).screenshotQualityTitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          // 说明行（根据开关禁用/启用与灰化）
                          IgnorePointer(
                            ignoring: !_useTargetSize,
                            child: Opacity(
                              opacity: _useTargetSize ? 1.0 : 0.5,
                              child: Row(
                                children: [
                                  Text(
                                    AppLocalizations.of(
                                      context,
                                    ).currentTimeLabel,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(width: AppTheme.spacing1),
                                  GestureDetector(
                                    onTap: _useTargetSize
                                        ? _showTargetSizeDialog
                                        : null,
                                    child: Text(
                                      '${_targetSizeKb}KB',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                            decoration: _useTargetSize
                                                ? TextDecoration.underline
                                                : TextDecoration.none,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: AppTheme.spacing1),
                                  Flexible(
                                    child: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).clickToModifyHint,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 右上角悬浮圆形开关（不占据垂直排布空间）
                    Positioned(
                      top: -1,
                      right: 0,
                      child: Transform.scale(
                        scale: 0.9,
                        child: Switch(
                          value: _useTargetSize,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) async {
                            setState(() {
                              _useTargetSize = v;
                            });
                            await _saveScreenshotQualitySettings();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 与"截屏间隔"项保持一致的内边距与间距（去除多余的底部空白）
        ],
      ),
    );
  }

  Future<void> _loadScreenshotInterval() async {
    final interval = await _appService.getScreenshotInterval();
    if (mounted) {
      setState(() {
        _screenshotInterval = interval;
      });
    }
  }

  Future<void> _updateScreenshotInterval(int interval) async {
    await _appService.saveScreenshotInterval(interval);
    setState(() {
      _screenshotInterval = interval;
    });
  }

  void _showIntervalDialog() {
    final TextEditingController controller = TextEditingController(
      text: _screenshotInterval.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).setIntervalDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).intervalSecondsLabel,
                hintText: AppLocalizations.of(context).intervalInputHint,
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(AppTheme.spacing3),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: AppTheme.fontSizeBase,
              ),
            ),
          ),
        ],
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final input = controller.text.trim();
            final interval = int.tryParse(input);
            if (interval == null || interval < 5 || interval > 60) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).intervalInvalidError,
              );
              return;
            }
            await _updateScreenshotInterval(interval);
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).intervalSavedSuccess(interval),
              );
            }
          },
        ),
      ],
    );
  }

  void _showTargetSizeDialog() {
    final TextEditingController controller = TextEditingController(
      text: _targetSizeKb.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).setTargetSizeDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).targetSizeKbLabel,
                contentPadding: EdgeInsets.all(AppTheme.spacing3),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: AppTheme.fontSizeBase,
              ),
            ),
          ),
        ],
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final input = controller.text.trim();
            final kb = int.tryParse(input);
            if (kb == null || kb < 50) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).targetSizeInvalidError,
              );
              return;
            }
            setState(() {
              _useTargetSize = true;
              _targetSizeKb = kb;
            });
            await _saveScreenshotQualitySettings();
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).targetSizeSavedSuccess(kb),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildScreenshotExpireItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.auto_delete_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).screenshotExpireTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            AppLocalizations.of(context).currentTimeLabel,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(width: AppTheme.spacing1),
                          GestureDetector(
                            onTap: _showExpireDaysDialog,
                            child: Text(
                              AppLocalizations.of(
                                context,
                              ).expireDaysUnit(_expireDays),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing1),
                          Flexible(
                            child: Text(
                              AppLocalizations.of(context).clickToModifyHint,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: -1,
                  right: 0,
                  child: Transform.scale(
                    scale: 0.9,
                    child: Switch(
                      value: _expireEnabled,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) async {
                        if (v) {
                          // 开启时显示二次确认对话框
                          _showExpireEnableConfirmDialog();
                        } else {
                          // 关闭时直接保存
                          setState(() {
                            _expireEnabled = false;
                          });
                          await _saveScreenshotExpireSettings();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showExpireEnableConfirmDialog() {
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).expireCleanupConfirmTitle,
      content: Text(
        AppLocalizations.of(context).expireCleanupConfirmMessage(_expireDays),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).expireCleanupConfirmAction,
          style: UIDialogActionStyle.primary,
          onPressed: (ctx) async {
            setState(() {
              _expireEnabled = true;
            });
            await _saveScreenshotExpireSettings();
            // 立即执行清理
            // ignore: unawaited_futures
            ScreenshotService.instance.cleanupExpiredScreenshotsIfNeeded(
              force: true,
            );
          },
        ),
      ],
    );
  }

  void _showExpireDaysDialog() {
    final TextEditingController controller = TextEditingController(
      text: _expireDays.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).setExpireDaysDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).expireDaysLabel,
                hintText: AppLocalizations.of(context).expireDaysInputHint,
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(AppTheme.spacing3),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: AppTheme.fontSizeBase,
              ),
            ),
          ),
        ],
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final input = controller.text.trim();
            final d = int.tryParse(input);
            if (d == null || d < 1) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).expireDaysInvalidError,
              );
              return;
            }
            setState(() {
              _expireDays = d;
            });
            await _saveScreenshotExpireSettings();
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).expireDaysSavedSuccess(d),
              );
            }
            // 如果开关已开启，则立即清理
            if (_expireEnabled) {
              // ignore: unawaited_futures
              ScreenshotService.instance.cleanupExpiredScreenshotsIfNeeded(
                force: true,
              );
            }
          },
        ),
      ],
    );
  }

  Future<void> _loadScreenshotQualitySettings() async {
    try {
      final String? format = await UserSettingsService.instance.getString(
        UserSettingKeys.imageFormat,
        defaultValue: 'webp_lossless',
        legacyPrefKeys: const <String>['image_format'],
      );
      final int quality = await UserSettingsService.instance.getInt(
        UserSettingKeys.imageQuality,
        defaultValue: 90,
        legacyPrefKeys: const <String>['image_quality'],
      );
      final bool useTarget = await UserSettingsService.instance.getBool(
        UserSettingKeys.useTargetSize,
        defaultValue: false,
        legacyPrefKeys: const <String>['use_target_size'],
      );
      final int targetKb = await UserSettingsService.instance.getInt(
        UserSettingKeys.targetSizeKb,
        defaultValue: 50,
        legacyPrefKeys: const <String>['target_size_kb'],
      );
      if (mounted) {
        setState(() {
          _imageFormat = format ?? 'webp_lossless';
          _imageQuality = quality.clamp(1, 100);
          _useTargetSize = useTarget;
          _targetSizeKb = targetKb < 50 ? 50 : targetKb;
          _grayscale = false; // 灰度已移除
        });
      }
    } catch (_) {}
  }

  Future<void> _loadScreenshotExpireSettings() async {
    try {
      final bool enabled = await UserSettingsService.instance.getBool(
        UserSettingKeys.screenshotExpireEnabled,
        defaultValue: false,
        legacyPrefKeys: const <String>['screenshot_expire_enabled'],
      );
      final int days = await UserSettingsService.instance.getInt(
        UserSettingKeys.screenshotExpireDays,
        defaultValue: 30,
        legacyPrefKeys: const <String>['screenshot_expire_days'],
      );
      if (mounted) {
        setState(() {
          _expireEnabled = enabled;
          _expireDays = days < 1 ? 1 : days;
        });
      }
    } catch (_) {}
  }

  Future<void> _resyncScreenshotSettingsAfterImport() async {
    await UserSettingsService.instance.resyncScreenshotEncodingSettings();
    await Future.wait([
      _loadScreenshotQualitySettings(),
      _loadScreenshotExpireSettings(),
    ]);
  }

  Future<void> _saveScreenshotExpireSettings() async {
    try {
      final int days = _expireDays < 1 ? 1 : _expireDays;
      await UserSettingsService.instance.setBool(
        UserSettingKeys.screenshotExpireEnabled,
        _expireEnabled,
        legacyPrefKeys: const <String>['screenshot_expire_enabled'],
      );
      await UserSettingsService.instance.setInt(
        UserSettingKeys.screenshotExpireDays,
        days,
        legacyPrefKeys: const <String>['screenshot_expire_days'],
      );
      if (mounted) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).expireCleanupSaved,
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
    }
  }

  Future<void> _loadPrivacyMode() async {
    try {
      final enabled = await _appService.getPrivacyModeEnabled();
      if (mounted) {
        setState(() {
          _privacyMode = enabled;
        });
      }
    } catch (_) {}
  }

  Future<void> _updatePrivacyMode(bool enabled) async {
    await _appService.savePrivacyModeEnabled(enabled);
    if (mounted) {
      setState(() {
        _privacyMode = enabled;
      });
      UINotifier.success(
        context,
        enabled
            ? AppLocalizations.of(context).privacyModeEnabledToast
            : AppLocalizations.of(context).privacyModeDisabledToast,
      );
    }
  }

  Future<void> _saveScreenshotQualitySettings() async {
    try {
      // 根据是否启用目标大小自动设置格式：启用->webp_lossy；关闭->webp_lossless（原画质）
      final String format = _useTargetSize ? 'webp_lossy' : 'webp_lossless';
      await UserSettingsService.instance.setString(
        UserSettingKeys.imageFormat,
        format,
        legacyPrefKeys: const <String>['image_format'],
      );
      await UserSettingsService.instance.setInt(
        UserSettingKeys.imageQuality,
        _imageQuality,
        legacyPrefKeys: const <String>['image_quality'],
      );
      await UserSettingsService.instance.setBool(
        UserSettingKeys.useTargetSize,
        _useTargetSize,
        legacyPrefKeys: const <String>['use_target_size'],
      );
      await UserSettingsService.instance.setInt(
        UserSettingKeys.targetSizeKb,
        _targetSizeKb < 50 ? 50 : _targetSizeKb,
        legacyPrefKeys: const <String>['target_size_kb'],
      );
      // 不再保存灰度
      if (mounted) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).screenshotQualitySettingsSaved,
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
    }
  }

  // ===== NSFW 域名清单管理 =====
  Future<void> _loadNsfwRules() async {
    try {
      if (mounted) setState(() => _nsfwLoading = true);
      await NsfwPreferenceService.instance.ensureRulesLoaded();
      final rows = await NsfwPreferenceService.instance.listRules();
      if (mounted) {
        setState(() {
          _nsfwRules = rows;
          _nsfwLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _nsfwLoading = false);
    }
  }

  Future<void> _previewNsfwDomain() async {
    final input = _nsfwDomainController.text.trim();
    if (input.isEmpty) return;
    try {
      final cnt = await NsfwPreferenceService.instance.previewMatchCount(input);
      if (mounted) {
        setState(() => _nsfwPreviewCount = cnt);
        UINotifier.info(
          context,
          AppLocalizations.of(context).previewAffectsCount(cnt),
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).invalidDomainInputError,
        );
      }
    }
  }

  Future<void> _addNsfwDomain() async {
    final l10n = AppLocalizations.of(context);
    final input = _nsfwDomainController.text.trim();
    if (input.isEmpty) return;
    // 先预览，避免误屏蔽
    int preview = 0;
    try {
      preview = await NsfwPreferenceService.instance.previewMatchCount(input);
    } catch (e) {
      UINotifier.error(context, l10n.invalidDomainInputError);
      return;
    }
    final ok =
        await showUIDialog<bool>(
          context: context,
          title: l10n.confirmAddRuleTitle,
          message: l10n.confirmAddRuleMessage(input),
          barrierDismissible: false,
          actions: [
            UIDialogAction<bool>(text: l10n.dialogCancel, result: false),
            UIDialogAction<bool>(
              text: l10n.dialogOk,
              style: UIDialogActionStyle.primary,
              result: true,
            ),
          ],
        ) ??
        false;
    if (!ok) return;
    final saved = await NsfwPreferenceService.instance.addRule(input);
    if (!mounted) return;
    if (saved) {
      _nsfwDomainController.clear();
      _nsfwPreviewCount = null;
      await _loadNsfwRules();
      UINotifier.success(context, l10n.ruleAddedToast);
    } else {
      UINotifier.error(context, l10n.operationFailed);
    }
  }

  Future<void> _removeNsfwDomain(String pattern) async {
    final l10n = AppLocalizations.of(context);
    final ok = await NsfwPreferenceService.instance.removeRule(pattern);
    if (!mounted) return;
    if (ok) {
      await _loadNsfwRules();
      UINotifier.success(context, l10n.ruleRemovedToast);
    } else {
      UINotifier.error(context, l10n.operationFailed);
    }
  }

  Future<void> _clearAllNsfwRules() async {
    final l10n = AppLocalizations.of(context);
    final ok =
        await showUIDialog<bool>(
          context: context,
          title: l10n.clearAllRulesConfirmTitle,
          message: l10n.clearAllRulesMessage,
          actions: const [
            UIDialogAction<bool>(text: '取消', result: false),
            UIDialogAction<bool>(
              text: '清空',
              style: UIDialogActionStyle.destructive,
              result: true,
            ),
          ],
          barrierDismissible: false,
        ) ??
        false;
    if (!ok) return;
    final n = await NsfwPreferenceService.instance.clearRules();
    if (!mounted) return;
    if (n >= 0) {
      await _loadNsfwRules();
      UINotifier.success(context, l10n.actionClear);
    } else {
      UINotifier.error(context, l10n.operationFailed);
    }
  }

  Widget _buildNsfwDomainManager(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(
                      color: _settingsDividerSide(context).color,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _nsfwDomainController,
                    decoration: InputDecoration(
                      hintText: l10n.addDomainPlaceholder,
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacing2),
              TextButton(
                onPressed: _previewNsfwDomain,
                child: Text(l10n.previewAction),
              ),
              const SizedBox(width: AppTheme.spacing1),
              ElevatedButton(
                onPressed: _addNsfwDomain,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                child: Text(l10n.addRuleAction),
              ),
            ],
          ),
          if (_nsfwPreviewCount != null) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              l10n.previewAffectsCount(_nsfwPreviewCount!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppTheme.spacing3),
          Row(
            children: [
              Text(
                l10n.blockedDomainListTitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: _nsfwRules.isEmpty ? null : _clearAllNsfwRules,
                child: Text(l10n.clearAllRules),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          if (_nsfwLoading)
            const SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_nsfwRules.isEmpty)
            Text(
              AppLocalizations.of(context).none,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _nsfwRules.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Theme.of(context).dividerColor),
              itemBuilder: (context, index) {
                final r = _nsfwRules[index];
                final pattern = (r['pattern'] as String?) ?? '';
                final isWildcard = ((r['is_wildcard'] as int?) ?? 0) == 1;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Expanded(child: Text(pattern)),
                      if (isWildcard)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSm,
                            ),
                          ),
                          child: Text(
                            '*.',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.removeAction,
                    onPressed: () => _removeNsfwDomain(pattern),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ========== 扩展：每日总结提醒设置（提示时间 + 测试按钮） ==========
extension _DailySummaryNotifyExt on _SettingsPageState {
  Future<void> _loadDailyNotifySettings() async {
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
      if (mounted) {
        setState(() {
          _dailyNotifyEnabled = enabled;
          _dailyNotifyHour = hour.clamp(0, 23);
          _dailyNotifyMinute = minute.clamp(0, 59);
        });
      }
      await FlutterLogger.nativeInfo(
        'DailySummaryUI',
        '加载设置：启用=${_dailyNotifyEnabled} 时间=${_two(_dailyNotifyHour)}:${_two(_dailyNotifyMinute)}',
      );
      final ok = await DailySummaryService.instance.scheduleDailyNotification(
        hour: _dailyNotifyHour,
        minute: _dailyNotifyMinute,
        enabled: _dailyNotifyEnabled,
      );
      // 启动一次"自动预生成"调度
      await DailySummaryService.instance.refreshAutoRefreshSchedule();
      await FlutterLogger.nativeInfo('DailySummaryUI', '加载后恢复调度 结果=$ok');
    } catch (e) {
      await FlutterLogger.nativeWarn('DailySummaryUI', '加载设置失败：$e');
    }
  }

  Future<void> _saveDailyNotifySettings({
    bool? enabled,
    int? hour,
    int? minute,
    bool toast = true,
  }) async {
    try {
      final newEnabled = enabled ?? _dailyNotifyEnabled;
      final newHour = (hour ?? _dailyNotifyHour).clamp(0, 23);
      final newMinute = (minute ?? _dailyNotifyMinute).clamp(0, 59);

      await UserSettingsService.instance.setBool(
        UserSettingKeys.dailyNotifyEnabled,
        newEnabled,
        legacyPrefKeys: const <String>['daily_notify_enabled'],
      );
      await UserSettingsService.instance.setInt(
        UserSettingKeys.dailyNotifyHour,
        newHour,
        legacyPrefKeys: const <String>['daily_notify_hour'],
      );
      await UserSettingsService.instance.setInt(
        UserSettingKeys.dailyNotifyMinute,
        newMinute,
        legacyPrefKeys: const <String>['daily_notify_minute'],
      );

      if (mounted) {
        setState(() {
          _dailyNotifyEnabled = newEnabled;
          _dailyNotifyHour = newHour;
          _dailyNotifyMinute = newMinute;
        });
      }

      final ok = await DailySummaryService.instance.scheduleDailyNotification(
        hour: newHour,
        minute: newMinute,
        enabled: newEnabled,
      );
      // 刷新"预生成"定时器，使得在提醒前1分钟自动刷新当日总结
      await DailySummaryService.instance.refreshAutoRefreshSchedule();
      if (toast && mounted) {
        if (ok) {
          UINotifier.success(
            context,
            newEnabled
                ? AppLocalizations.of(
                    context,
                  ).reminderScheduleSuccess(_two(newHour), _two(newMinute))
                : AppLocalizations.of(context).reminderDisabledSuccess,
          );
        } else {
          UINotifier.warning(
            context,
            AppLocalizations.of(context).reminderScheduleFailed,
          );
        }
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveReminderSettingsFailed(e.toString()),
        );
    }
  }

  Future<void> _pickDailyNotifyTime() async {
    final int initialHour = _dailyNotifyHour.clamp(0, 23);
    final int initialMinute = _dailyNotifyMinute.clamp(0, 59);

    final FixedExtentScrollController hourController =
        FixedExtentScrollController(initialItem: initialHour);
    final FixedExtentScrollController minuteController =
        FixedExtentScrollController(initialItem: initialMinute);

    int tempHour = initialHour;
    int tempMinute = initialMinute;

    TimeOfDay? result;
    try {
      result = await showModalBottomSheet<TimeOfDay>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final theme = Theme.of(context);
          final l10n = AppLocalizations.of(context);

          return UISheetSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppTheme.spacing3),
                const UISheetHandle(),
                const SizedBox(height: AppTheme.spacing2),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                  child: Text(
                    l10n.setReminderTimeTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  height: 240,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              l10n.hourLabel,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Expanded(
                              child: CupertinoPicker(
                                scrollController: hourController,
                                itemExtent: 36,
                                magnification: 1.12,
                                squeeze: 1.05,
                                useMagnifier: true,
                                onSelectedItemChanged: (int index) {
                                  tempHour = index;
                                },
                                children: List<Widget>.generate(
                                  24,
                                  (int index) => Center(
                                    child: Text(
                                      _two(index),
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              l10n.minuteLabel,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Expanded(
                              child: CupertinoPicker(
                                scrollController: minuteController,
                                itemExtent: 36,
                                magnification: 1.12,
                                squeeze: 1.05,
                                useMagnifier: true,
                                onSelectedItemChanged: (int index) {
                                  tempMinute = index;
                                },
                                children: List<Widget>.generate(
                                  60,
                                  (int index) => Center(
                                    child: Text(
                                      _two(index),
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacing4,
                    AppTheme.spacing3,
                    AppTheme.spacing4,
                    AppTheme.spacing4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMd,
                              ),
                            ),
                          ),
                          child: Text(l10n.dialogCancel),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacing3),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(ctx).pop(
                              TimeOfDay(hour: tempHour, minute: tempMinute),
                            );
                          },
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMd,
                              ),
                            ),
                          ),
                          child: Text(l10n.dialogDone),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      hourController.dispose();
      minuteController.dispose();
    }

    if (result != null) {
      await _saveDailyNotifySettings(hour: result.hour, minute: result.minute);
    }
  }

  Widget _buildDailyNotifyItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.schedule_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).dailyReminderTimeTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                IgnorePointer(
                  ignoring: !_dailyNotifyEnabled,
                  child: Opacity(
                    opacity: _dailyNotifyEnabled ? 1.0 : 0.5,
                    child: Row(
                      children: [
                        Text(
                          AppLocalizations.of(context).currentTimeLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        GestureDetector(
                          onTap: _dailyNotifyEnabled
                              ? _pickDailyNotifyTime
                              : null,
                          child: Text(
                            '${_two(_dailyNotifyHour)}:${_two(_dailyNotifyMinute)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  decoration: _dailyNotifyEnabled
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacing1),
                        Flexible(
                          child: Text(
                            AppLocalizations.of(context).clickToModifyHint,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: _dailyNotifyEnabled,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) async {
                await _saveDailyNotifySettings(enabled: v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyNotifyTestItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(
            context,
            Icons.notifications_active_outlined,
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).testNotificationTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).testNotificationDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: () async {
              // 先强制重新生成当日总结，确保通知内容新鲜
              final key = _todayKey();
              try {
                await DailySummaryService.instance.getOrGenerate(
                  key,
                  force: true,
                );
              } catch (_) {}
              final ok = await DailySummaryService.instance
                  .triggerNotificationNow(key);
              if (!mounted) return;
              if (ok) {
                UINotifier.success(
                  context,
                  AppLocalizations.of(context).dailyNotifyTriggered,
                );
              } else {
                UINotifier.warning(
                  context,
                  AppLocalizations.of(context).dailyNotifyTriggerFailed,
                );
              }
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionTrigger),
          ),
        ],
      ),
    );
  }

  // 打开"每日总结提醒"渠道设置（开启横幅/悬浮通知等）
  Future<void> _openDailyChannelSettings() async {
    try {
      await FlutterLogger.nativeInfo('DailySummaryUI', '打开通知渠道设置');
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      await platform.invokeMethod('openDailySummaryNotificationSettings');
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).openChannelSettingsFailed(e.toString()),
        );
      }
    }
  }

  // 打开"应用通知"总设置（可选）
  Future<void> _openAppNotificationSettings() async {
    try {
      await FlutterLogger.nativeInfo('DailySummaryUI', '打开应用通知设置');
      const platform = MethodChannel('com.fqyw/screen_memo/accessibility');
      // 兼容：统一使用正确通道名
    } catch (_) {}
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      await platform.invokeMethod('openAppNotificationSettings');
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(
            context,
          ).openAppNotificationSettingsFailed(e.toString()),
        );
      }
    }
  }

  // 行项：开启横幅/悬浮通知
  Widget _buildDailyNotifyBannerItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(
            context,
            Icons.notification_important_outlined,
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).enableBannerNotificationTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).enableBannerNotificationDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _openDailyChannelSettings,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionOpen),
          ),
        ],
      ),
    );
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${_two(now.month)}-${_two(now.day)}';
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}
