import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import '../widgets/ui_components.dart';
import 'home_page.dart';
import 'settings_page.dart';
import 'timeline_page.dart';
import 'favorites_page.dart';
import 'event_home_page.dart';
import '../services/app_lifecycle_service.dart';
import '../services/timeline_jump_service.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../services/flutter_logger.dart';

/// 主导航页面 - 包含底部导航栏的主界面
class MainNavigationPage extends StatefulWidget {
  final ThemeService themeService;

  const MainNavigationPage({super.key, required this.themeService});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;
  DateTime? _lastBackPressedAt;

  final SettingsPageController _settingsPageController =
      SettingsPageController();

  late final List<Widget> _pages;
  VoidCallback? _jumpListener;

  @override
  void initState() {
    super.initState();
    _pages = [
      HomePage(themeService: widget.themeService),
      const FavoritesPage(),
      const EventHomePage(),
      const TimelinePage(),
      SettingsPage(
        themeService: widget.themeService,
        controller: _settingsPageController,
      ),
    ];

    // 监听时间线跳转请求：切换到底部索引3（时间线）
    _jumpListener = () {
      final req = TimelineJumpService.instance.requestNotifier.value;
      if (req != null) {
        if (mounted && _currentIndex != 3) {
          setState(() {
            _currentIndex = 3;
          });
          AppLifecycleService.instance.emitTimelineShown();
        }
      }
    };
    TimelineJumpService.instance.requestNotifier.addListener(_jumpListener!);
  }

  List<BottomNavigationBarItem> _buildNavigationItems(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return [
      const BottomNavigationBarItem(
        icon: Icon(Icons.home_outlined),
        activeIcon: Icon(Icons.home),
        label: '',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.favorite_outline),
        activeIcon: Icon(Icons.favorite),
        label: '',
      ),
      // 事件（AI）Tab：星星图标 + 渐变激活态（随主题主色/次色）
      BottomNavigationBarItem(
        icon: const Icon(Icons.auto_awesome_outlined),
        activeIcon: ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, cs.secondary],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: const Icon(Icons.auto_awesome, color: Colors.white),
        ),
        label: '',
      ),
      // 时间线 Tab
      const BottomNavigationBarItem(
        icon: Icon(Icons.timeline_outlined),
        activeIcon: Icon(Icons.timeline),
        label: '',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.settings_outlined),
        activeIcon: Icon(Icons.settings),
        label: '',
      ),
    ];
  }

  void _onTabTapped(int index) {
    // 切换底部标签时，统一取消当前焦点，避免隐藏页的输入框仍然保留焦点导致键盘误弹
    FocusManager.instance.primaryFocus?.unfocus();
    // 事件（AI）Tab：沉浸式全屏进入，不显示底部菜单
    if (index == 2) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const EventHomePage()));
      return;
    }
    setState(() {
      _currentIndex = index;
    });
    // 每次进入"时间线"页（索引3，因为收藏页插入到了索引1）都触发刷新事件
    if (index == 3) {
      try {
        FlutterLogger.nativeInfo('MainNav', '切换到时间线Tab，发出timelineShown');
      } catch (_) {}
      AppLifecycleService.instance.emitTimelineShown();
    }
  }

  Future<bool> _onWillPop() async {
    // 让当前 Tab 优先处理自己的“返回”（例如设置二级页返回到设置首页）
    if (_currentIndex == 4) {
      final handled = _settingsPageController.handleBack();
      if (handled) return false;
    }

    final now = DateTime.now();
    if (_lastBackPressedAt == null ||
        now.difference(_lastBackPressedAt!) > const Duration(seconds: 2)) {
      _lastBackPressedAt = now;
      UINotifier.center(
        context,
        AppLocalizations.of(context).pressBackAgainToExit,
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: _pages),
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: _settingsPageController.isInSubPage,
          builder: (context, isInSubPage, _) {
            if (_currentIndex == 4 && isInSubPage) {
              return const SizedBox.shrink();
            }
            final theme = Theme.of(context);
            final Color navBg =
                theme.bottomNavigationBarTheme.backgroundColor ??
                theme.scaffoldBackgroundColor;
            final Color topBorder = theme.colorScheme.outline.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.40 : 0.60,
            );
            return DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: topBorder, width: 0.5)),
              ),
              child: SizedBox(
                height: 52,
                child: BottomNavigationBar(
                  backgroundColor: navBg,
                  elevation: 0,
                  currentIndex: _currentIndex,
                  onTap: _onTabTapped,
                  showSelectedLabels: false,
                  showUnselectedLabels: false,
                  // Force a compact bar (labels are hidden anyway).
                  selectedFontSize: 0,
                  unselectedFontSize: 0,
                  items: _buildNavigationItems(context),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    try {
      if (_jumpListener != null) {
        TimelineJumpService.instance.requestNotifier.removeListener(
          _jumpListener!,
        );
      }
    } catch (_) {}
    _settingsPageController.dispose();
    super.dispose();
  }
}
