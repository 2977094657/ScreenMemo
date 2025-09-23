import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import '../widgets/ui_components.dart';
import 'home_page.dart';
import 'settings_page.dart';
import 'segment_status_page.dart';
import 'timeline_page.dart';
import '../theme/app_theme.dart';
import '../services/app_lifecycle_service.dart';

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
  
  late final List<Widget> _pages;
  
  @override
  void initState() {
    super.initState();
    _pages = [
      HomePage(themeService: widget.themeService),
      const TimelinePage(),
      const SegmentStatusPage(),
      SettingsPage(themeService: widget.themeService),
    ];
  }

  final List<BottomNavigationBarItem> _navigationItems = [
    const BottomNavigationBarItem(
      icon: Icon(Icons.home_outlined),
      activeIcon: Icon(Icons.home),
      label: '',
    ),
    const BottomNavigationBarItem(
      icon: Icon(Icons.timeline_outlined),
      activeIcon: Icon(Icons.timeline),
      label: '',
    ),
    const BottomNavigationBarItem(
      icon: Icon(Icons.event_note_outlined),
      activeIcon: Icon(Icons.event_note),
      label: '',
    ),
    const BottomNavigationBarItem(
      icon: Icon(Icons.settings_outlined),
      activeIcon: Icon(Icons.settings),
      label: '',
    ),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
    // 每次进入“时间线”页（索引1）都触发刷新事件
    if (index == 1) {
      AppLifecycleService.instance.emitTimelineShown();
    }
  }
  
  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPressedAt == null ||
        now.difference(_lastBackPressedAt!) > const Duration(seconds: 2)) {
      _lastBackPressedAt = now;
      UINotifier.center(context, '再按一次退出屏忆');
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          // 更直观的选中色：浅色主题用信息蓝，深色主题用更醒目的蓝色强调
          final Color selectedColor = isDark ? AppTheme.darkSelectedAccent : AppTheme.info;
          // 未选中色：浅色使用静默前景灰，深色使用 onSurface 70% 不透明度
          final Color unselectedColor = isDark
              ? theme.colorScheme.onSurface.withOpacity(0.7)
              : AppTheme.mutedForeground;

          return SizedBox(
            height: 52,
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: selectedColor,
              unselectedItemColor: unselectedColor,
              selectedIconTheme: IconThemeData(color: selectedColor, size: 20),
              unselectedIconTheme: IconThemeData(color: unselectedColor, size: 18),
              backgroundColor: theme.colorScheme.surfaceVariant,
              elevation: 0,
              showSelectedLabels: false,
              showUnselectedLabels: false,
              items: _navigationItems,
            ),
          );
        },
      ),
      ),
    );
  }
}
