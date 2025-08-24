import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import 'home_page.dart';
import 'settings_page.dart';
import 'debug_page.dart';

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
      const DebugPage(),
      SettingsPage(themeService: widget.themeService),
    ];
  }

  final List<BottomNavigationBarItem> _navigationItems = [
    const BottomNavigationBarItem(
      icon: Icon(Icons.home),
      label: '',
    ),
    const BottomNavigationBarItem(
      icon: Icon(Icons.article_outlined),
      label: '',
    ),
    const BottomNavigationBarItem(
      icon: Icon(Icons.settings),
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
      bottomNavigationBar: SizedBox(
        height: 60, // 再次调整高度
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Theme.of(context).textTheme.bodySmall?.color,
          backgroundColor: Theme.of(context).cardColor,
          elevation: 8,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          iconSize: 22, // 保持图标大小协调
          items: _navigationItems,
        ),
      ),
    );
  }
}
