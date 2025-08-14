import 'package:flutter/material.dart';
import 'services/app_selection_service.dart';
import 'theme/app_theme.dart';
import 'services/permission_service.dart';
import 'services/screenshot_service.dart';
import 'services/theme_service.dart';
import 'pages/onboarding_page.dart';
import 'pages/main_navigation_page.dart';
import 'pages/screenshot_gallery_page.dart';
import 'pages/screenshot_viewer_page.dart';
import 'pages/debug_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 预加载已选择应用到内存，避免首页首帧出现空状态
  try {
    await AppSelectionService.instance.getSelectedApps();
  } catch (_) {}
  runApp(const ScreenMemoApp());
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
        '/debug': (context) => const DebugPage(),
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
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    try {
      final permissionService = PermissionService.instance;

      // 初始化ScreenshotService以确保Method Channel Handler被设置
      ScreenshotService.instance;
      print('ScreenshotService已初始化');

      // 首先检查引导是否已完成
      final onboardingCompleted = await permissionService.isOnboardingCompleted();

      if (onboardingCompleted) {
        // 如果引导已完成，直接进入主页，不再检查权限
        setState(() {
          _showOnboarding = false;
          _isLoading = false;
        });
        return;
      }

      // 如果引导未完成，检查是否首次启动
      final isFirstLaunch = await permissionService.isFirstLaunch();

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
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        // 跟随主题
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return _showOnboarding 
        ? OnboardingPage(themeService: widget.themeService) 
        : MainNavigationPage(themeService: widget.themeService);
  }
}


