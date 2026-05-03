import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_memo/core/lifecycle/app_lifecycle_service.dart';
import 'package:screen_memo/core/localization/locale_service.dart';
import 'package:screen_memo/core/performance/startup_profiler.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/theme/theme_service.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/features/capture/presentation/pages/app_screenshot_settings_page.dart';
import 'package:screen_memo/app/navigation/main_navigation_page.dart';
import 'package:screen_memo/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:screen_memo/features/gallery/presentation/pages/screenshot_gallery_page.dart';
import 'package:screen_memo/features/gallery/presentation/pages/screenshot_viewer_page.dart';
import 'package:screen_memo/features/search/presentation/pages/search_page.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/features/daily_summary/application/daily_summary_service.dart';
import 'package:screen_memo/app/navigation/navigation_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_maintenance_service.dart';
import 'package:screen_memo/features/nocturne_memory/application/nocturne_memory_rebuild_service.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/features/capture/application/screenshot_service.dart';

class ScreenMemoApp extends StatefulWidget {
  const ScreenMemoApp({
    super.key,
    required this.initialShowOnboarding,
    required this.isFirstLaunch,
  });

  final bool initialShowOnboarding;
  final bool isFirstLaunch;

  @override
  State<ScreenMemoApp> createState() => _ScreenMemoAppState();
}

class _ScreenMemoAppState extends State<ScreenMemoApp>
    with WidgetsBindingObserver {
  final ThemeService _themeService = ThemeService();
  final LocaleService _localeService = LocaleService.instance;
  // 全局导航Key：由 NavigationService 提供

  @override
  void initState() {
    super.initState();
    StartupProfiler.mark('ScreenMemoAppState.initState');
    _themeService.addListener(_onThemeChanged);
    _localeService.addListener(_onLocaleChanged);
    // 监听应用生命周期，用于页面自动刷新
    WidgetsBinding.instance.addObserver(this);
    // 首帧后触发“首次进入 UI”事件（冷启动或UI首次展示）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLifecycleService.instance.emitFirstUiResumed();
      // 安排每日总结的自动预生成（08:00、12:00、17:00 + 提醒前1分钟）
      // ignore: discarded_futures
      DailySummaryService.instance.refreshAutoRefreshSchedule();
      // ignore: discarded_futures
      NocturneMemoryRebuildService.instance.ensureInitialized(autoResume: true);
      // ignore: discarded_futures
      NocturneMemoryMaintenanceService.instance.ensureInitialized(
        autoResume: true,
      );
    });
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    _themeService.dispose();
    _localeService.removeListener(_onLocaleChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  void _onLocaleChanged() {
    // 语言切换时重建以生效
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回到前台：通知页面执行进入应用后的自动刷新
      AppLifecycleService.instance.emitResumed();
      // 回到前台时刷新一次“自动预生成”调度
      // ignore: discarded_futures
      DailySummaryService.instance.refreshAutoRefreshSchedule();
      // ignore: discarded_futures
      NocturneMemoryRebuildService.instance.ensureInitialized(autoResume: true);
      // ignore: discarded_futures
      NocturneMemoryMaintenanceService.instance.ensureInitialized(
        autoResume: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    StartupProfiler.mark('ScreenMemoAppState.build');
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeService.themeMode,
      locale: _localeService.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppInitializer(
        themeService: _themeService,
        initialShowOnboarding: widget.initialShowOnboarding,
        isFirstLaunch: widget.isFirstLaunch,
      ),
      debugShowCheckedModeBanner: false,
      navigatorKey: NavigationService.instance.navigatorKey,
      routes: {
        '/screenshot_gallery': (context) => const ScreenshotGalleryPage(),
        '/screenshot_viewer': (context) => const ScreenshotViewerPage(),
        '/search': (context) => const SearchPage(),
        '/app_screenshot_settings': (context) =>
            const AppScreenshotSettingsPage(),
      },
    );
  }
}

/// 应用初始化器，决定显示引导页面还是主页面
class AppInitializer extends StatefulWidget {
  final ThemeService themeService;
  final bool initialShowOnboarding;
  final bool isFirstLaunch;

  const AppInitializer({
    super.key,
    required this.themeService,
    required this.initialShowOnboarding,
    required this.isFirstLaunch,
  });

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  late bool _showOnboarding;

  @override
  void initState() {
    super.initState();
    _showOnboarding = widget.initialShowOnboarding;
    // 非首次启动时，在后台异步清理一次过期截图（不阻塞首屏）
    if (!widget.isFirstLaunch) {
      unawaited(ScreenshotService.instance.cleanupExpiredScreenshotsIfNeeded());
      unawaited(
        AISettingsService.instance.cleanupExpiredRawResponsesIfNeeded(),
      );
    }
    unawaited(_resumeBackgroundTasksIfNeeded());
  }

  Future<void> _resumeBackgroundTasksIfNeeded() async {
    try {
      await ScreenshotDatabase.instance.ensureImportOcrRepairTaskResumed();
    } catch (_) {}
    try {
      await ScreenshotDatabase.instance.ensureDynamicRebuildTaskResumed();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return _showOnboarding
        ? OnboardingPage(themeService: widget.themeService)
        : MainNavigationPage(themeService: widget.themeService);
  }
}
