import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import 'home_page.dart';
import 'settings_page.dart';

/// 主导航页面 - 包含底部导航栏的主界面
class MainNavigationPage extends StatefulWidget {
  final ThemeService themeService;
  
  const MainNavigationPage({super.key, required this.themeService});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;
  
  late final List<Widget> _pages;
  
  @override
  void initState() {
    super.initState();
    _pages = [
      HomePage(themeService: widget.themeService),
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
      icon: Icon(Icons.settings_outlined),
      activeIcon: Icon(Icons.settings),
      label: '',
    ),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          final Color selectedColor = theme.colorScheme.primary;
          final Color unselectedColor = isDark
              ? theme.colorScheme.onSurface.withOpacity(0.7)
              : theme.colorScheme.onSurfaceVariant;

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
              backgroundColor: theme.cardColor,
              elevation: 8,
              showSelectedLabels: false,
              showUnselectedLabels: false,
              items: _navigationItems,
            ),
          );
        },
      ),
    );
  }
}
