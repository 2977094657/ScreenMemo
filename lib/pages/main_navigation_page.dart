import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      const SizedBox.shrink(),
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
      const BottomNavigationBarItem(
        icon: Icon(Icons.auto_awesome_outlined),
        activeIcon: Icon(Icons.auto_awesome),
        label: '',
      ),
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

  Widget _buildBottomNavigationBar(BuildContext context) {
    final theme = Theme.of(context);
    final List<BottomNavigationBarItem> items = _buildNavigationItems(context);
    final Color navBg =
        theme.bottomNavigationBarTheme.backgroundColor ??
        theme.scaffoldBackgroundColor;
    final Color topBorder = theme.colorScheme.outline.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.40 : 0.60,
    );
    final Color selectedColor =
        theme.bottomNavigationBarTheme.selectedItemColor ??
        theme.colorScheme.primary;
    final Color unselectedColor =
        theme.bottomNavigationBarTheme.unselectedItemColor ??
        theme.colorScheme.onSurfaceVariant;
    final double selectedSize =
        theme.bottomNavigationBarTheme.selectedIconTheme?.size ?? 20;
    final double unselectedSize =
        theme.bottomNavigationBarTheme.unselectedIconTheme?.size ?? 18;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: topBorder, width: 0.5)),
      ),
      child: Material(
        color: navBg,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 52,
            child: Row(
              children: List<Widget>.generate(items.length, (index) {
                final BottomNavigationBarItem item = items[index];
                final bool selected = _currentIndex == index;
                final Widget icon = selected ? item.activeIcon : item.icon;

                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: selected,
                    child: InkWell(
                      onTap: () => _onTabTapped(index),
                      child: SizedBox.expand(
                        child: Center(
                          child: IconTheme.merge(
                            data: IconThemeData(
                              color: selected ? selectedColor : unselectedColor,
                              size: selected ? selectedSize : unselectedSize,
                            ),
                            child: icon,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  void _onTabTapped(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (index == 2) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const EventHomePage()));
      return;
    }
    setState(() {
      _currentIndex = index;
    });
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool shouldExit = await _onWillPop();
        if (shouldExit) {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: _pages),
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: _settingsPageController.isInSubPage,
          builder: (context, isInSubPage, _) {
            if (_currentIndex == 4 && isInSubPage) {
              return const SizedBox.shrink();
            }
            return _buildBottomNavigationBar(context);
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
