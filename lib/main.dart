import 'package:flutter/material.dart';
import 'services/startup_profiler.dart';
import 'theme/app_theme.dart';
import 'services/permission_service.dart';
import 'services/screenshot_service.dart';
import 'services/theme_service.dart';
import 'pages/onboarding_page.dart';
import 'pages/main_navigation_page.dart';
import 'pages/screenshot_gallery_page.dart';
import 'pages/screenshot_viewer_page.dart';
import 'services/flutter_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 简易 Flutter 侧日志初始化
  await FlutterLogger.log('app start');
  StartupProfiler.mark('main.ensureInitialized.done');
  // 立刻构建首帧，避免阻塞到 runApp 之前
  StartupProfiler.begin('runApp');
  runApp(const ScreenMemoApp());
  StartupProfiler.end('runApp');
  // 取消首帧前的预加载，避免重复耗时；首页将按需加载
}

class ScreenMemoApp extends StatefulWidget {
  const ScreenMemoApp({super.key});

  @override
  State<ScreenMemoApp> createState() => _ScreenMemoAppState();
}

class _ScreenMemoAppState extends State<ScreenMemoApp> {
  final ThemeService _themeService = ThemeService();

  @override
  void initState() {
    super.initState();
    StartupProfiler.mark('ScreenMemoAppState.initState');
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    _themeService.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    StartupProfiler.mark('ScreenMemoAppState.build');
    return MaterialApp(
      title: '屏忆',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeService.themeMode,
      home: AppInitializer(themeService: _themeService),
      debugShowCheckedModeBanner: false,
      routes: {
        '/screenshot_gallery': (context) => const ScreenshotGalleryPage(),
        '/screenshot_viewer': (context) => const ScreenshotViewerPage(),
      },
    );
  }
}

/// 应用初始化器，决定显示引导页面还是主页面
class AppInitializer extends StatefulWidget {
  final ThemeService themeService;
  
  const AppInitializer({super.key, required this.themeService});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isLoading = true;
  bool _showOnboarding = true;

  @override
  void initState() {
    super.initState();
    StartupProfiler.begin('AppInitializer.initState');
    _checkFirstLaunch();
    // 首帧回调
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupProfiler.mark('firstFrame.displayed');
    });
    StartupProfiler.end('AppInitializer.initState');
  }

  Future<void> _checkFirstLaunch() async {
    StartupProfiler.begin('AppInitializer._checkFirstLaunch');
    try {
      final permissionService = PermissionService.instance;
      StartupProfiler.mark('AppInitializer.permissionService.ready');

      // 初始化ScreenshotService以确保Method Channel Handler被设置
      StartupProfiler.begin('AppInitializer.init.ScreenshotService');
      ScreenshotService.instance;
      StartupProfiler.end('AppInitializer.init.ScreenshotService');

      // 首先检查引导是否已完成
      StartupProfiler.begin('AppInitializer.check.onboardingCompleted');
      final onboardingCompleted = await permissionService.isOnboardingCompleted();
      StartupProfiler.end('AppInitializer.check.onboardingCompleted');

      if (onboardingCompleted) {
        // 如果引导已完成，直接进入主页，不再检查权限
        setState(() {
          _showOnboarding = false;
          _isLoading = false;
        });
        StartupProfiler.end('AppInitializer._checkFirstLaunch');
        return;
      }

      // 如果引导未完成，检查是否首次启动
      StartupProfiler.begin('AppInitializer.check.isFirstLaunch');
      final isFirstLaunch = await permissionService.isFirstLaunch();
      StartupProfiler.end('AppInitializer.check.isFirstLaunch');

      setState(() {
        _showOnboarding = isFirstLaunch;
        _isLoading = false;
      });
    } catch (e) {
      print('初始化失败: $e');
      setState(() {
        _isLoading = false;
        _showOnboarding = true;
      });
    }
    StartupProfiler.end('AppInitializer._checkFirstLaunch');
  }

  @override
  Widget build(BuildContext context) {
    StartupProfiler.mark('AppInitializer.build');
    // 冷启动阶段直接进入主页面（原生冷启动已展示品牌页）
    if (_isLoading) {
      return MainNavigationPage(themeService: widget.themeService);
    }

    return _showOnboarding
        ? OnboardingPage(themeService: widget.themeService)
        : MainNavigationPage(themeService: widget.themeService);
  }
}


