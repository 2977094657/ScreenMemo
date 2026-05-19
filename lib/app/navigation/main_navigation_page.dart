import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_memo/app/navigation/bottom_navigation_config.dart';
import 'package:screen_memo/app/navigation/customize_bottom_navigation_page.dart';
import 'package:screen_memo/core/lifecycle/app_lifecycle_service.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/core/theme/theme_service.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/features/ai_chat/presentation/pages/event_home_page.dart';
import 'package:screen_memo/features/capture/presentation/pages/home_page.dart';
import 'package:screen_memo/features/favorites/presentation/pages/favorites_page.dart';
import 'package:screen_memo/features/settings/presentation/pages/settings_page.dart';
import 'package:screen_memo/features/storage_analysis/presentation/pages/storage_analysis_page.dart';
import 'package:screen_memo/features/timeline/application/timeline_jump_service.dart';
import 'package:screen_memo/features/timeline/presentation/pages/segment_status_page.dart';
import 'package:screen_memo/features/timeline/presentation/pages/timeline_page.dart';
import 'package:screen_memo/features/updater/presentation/update_prompt_coordinator.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

/// 主导航页面 - 包含可自定义底部导航栏的主界面
class MainNavigationPage extends StatefulWidget {
  final ThemeService themeService;

  const MainNavigationPage({super.key, required this.themeService});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage>
    with WidgetsBindingObserver {
  List<BottomNavItemId> _navItems = BottomNavigationConfig.defaultItems;
  BottomNavItemId _currentItem = BottomNavItemId.home;
  DateTime? _lastBackPressedAt;

  final SettingsPageController _settingsPageController =
      SettingsPageController();

  late final Map<BottomNavItemId, Widget> _indexedPages;
  VoidCallback? _jumpListener;
  bool _timelineJumpRouteOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _indexedPages = <BottomNavItemId, Widget>{
      BottomNavItemId.home: HomePage(themeService: widget.themeService),
      BottomNavItemId.favorites: const FavoritesPage(),
      BottomNavItemId.timeline: const TimelinePage(),
      BottomNavItemId.settings: SettingsPage(
        themeService: widget.themeService,
        controller: _settingsPageController,
      ),
      BottomNavItemId.dynamic: const SegmentStatusPage(),
      BottomNavItemId.storage: const StorageAnalysisPage(),
    };

    unawaited(_loadNavigationItems());

    _jumpListener = () {
      final req = TimelineJumpService.instance.requestNotifier.value;
      if (req == null || !mounted) return;
      _showTimelineForJump();
    };
    TimelineJumpService.instance.requestNotifier.addListener(_jumpListener!);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        UpdatePromptCoordinator.instance.checkAndPrompt(
          context,
          reason: 'startup',
        ),
      );
    });
  }

  Future<void> _loadNavigationItems() async {
    final List<BottomNavItemId> items =
        await BottomNavigationConfig.loadItems();
    if (!mounted) return;
    setState(() {
      _navItems = items;
      if (!_isSelectableIndexedItem(_currentItem) ||
          !_navItems.contains(_currentItem)) {
        _currentItem = BottomNavItemId.home;
      }
    });
  }

  bool _isSelectableIndexedItem(BottomNavItemId id) =>
      _indexedPages.containsKey(id);

  List<Widget> get _visibleIndexedPages {
    return _navItems
        .map((BottomNavItemId id) => _indexedPages[id])
        .whereType<Widget>()
        .toList();
  }

  int get _visibleIndexedPageIndex {
    final List<BottomNavItemId> visibleItems = _navItems
        .where(_isSelectableIndexedItem)
        .toList();
    final int index = visibleItems.indexOf(_currentItem);
    return index >= 0 ? index : 0;
  }

  Widget _pageForTransientItem(BottomNavItemId id) {
    switch (id) {
      case BottomNavItemId.ai:
        return const EventHomePage();
      case BottomNavItemId.home:
      case BottomNavItemId.favorites:
      case BottomNavItemId.timeline:
      case BottomNavItemId.settings:
      case BottomNavItemId.dynamic:
      case BottomNavItemId.storage:
        return _indexedPages[id] ?? const SizedBox.shrink();
    }
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    final theme = Theme.of(context);
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
            height: 58,
            child: Row(
              children: List<Widget>.generate(_navItems.length, (index) {
                final BottomNavItemId id = _navItems[index];
                final BottomNavItemPresentation item =
                    bottomNavItemPresentation(context, id);
                final bool selected = _currentItem == id;

                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: item.label,
                    child: InkWell(
                      onTap: () => _onTabTapped(id),
                      onLongPress: _openCustomizeBottomNavigation,
                      child: SizedBox.expand(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconTheme.merge(
                              data: IconThemeData(
                                color: selected
                                    ? selectedColor
                                    : unselectedColor,
                                size: selected ? selectedSize : unselectedSize,
                              ),
                              child: Icon(
                                selected ? item.activeIcon : item.icon,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: selected
                                      ? selectedColor
                                      : unselectedColor,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  letterSpacing: 0,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ],
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

  void _onTabTapped(BottomNavItemId id) {
    FocusManager.instance.primaryFocus?.unfocus();
    switch (id) {
      case BottomNavItemId.ai:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => _pageForTransientItem(id)));
        return;
      case BottomNavItemId.timeline:
        _selectIndexedItem(id);
        _emitTimelineShown();
        return;
      case BottomNavItemId.home:
      case BottomNavItemId.favorites:
      case BottomNavItemId.settings:
      case BottomNavItemId.dynamic:
      case BottomNavItemId.storage:
        _selectIndexedItem(id);
        return;
    }
  }

  void _selectIndexedItem(BottomNavItemId id) {
    if (!_isSelectableIndexedItem(id)) return;
    setState(() => _currentItem = id);
  }

  void _showTimelineForJump() {
    if (_navItems.contains(BottomNavItemId.timeline)) {
      if (_currentItem != BottomNavItemId.timeline) {
        setState(() => _currentItem = BottomNavItemId.timeline);
        _emitTimelineShown();
      }
      return;
    }
    if (_timelineJumpRouteOpen) return;
    _timelineJumpRouteOpen = true;
    unawaited(
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const TimelinePage()))
          .whenComplete(() {
            _timelineJumpRouteOpen = false;
          }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitTimelineShown());
  }

  void _emitTimelineShown() {
    try {
      FlutterLogger.nativeInfo('MainNav', '切换到时间线Tab，发出timelineShown');
    } catch (_) {}
    AppLifecycleService.instance.emitTimelineShown();
  }

  Future<void> _openCustomizeBottomNavigation() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final List<BottomNavItemId>? result = await Navigator.of(context)
        .push<List<BottomNavItemId>>(
          MaterialPageRoute(
            builder: (_) =>
                CustomizeBottomNavigationPage(initialItems: _navItems),
          ),
        );
    if (result == null || !mounted) return;
    final List<BottomNavItemId> normalized =
        BottomNavigationConfig.normalizeItems(result);
    await BottomNavigationConfig.saveItems(normalized);
    if (!mounted) return;
    setState(() {
      _navItems = normalized;
      if (!_navItems.contains(_currentItem) ||
          !_isSelectableIndexedItem(_currentItem)) {
        _currentItem = BottomNavItemId.home;
      }
    });
  }

  Future<bool> _onWillPop() async {
    if (_currentItem == BottomNavItemId.settings) {
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
    final List<Widget> visiblePages = _visibleIndexedPages;
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
        body: IndexedStack(
          index: _visibleIndexedPageIndex,
          children: visiblePages.isEmpty
              ? const <Widget>[SizedBox.shrink()]
              : visiblePages,
        ),
        bottomNavigationBar: ValueListenableBuilder<bool>(
          valueListenable: _settingsPageController.isInSubPage,
          builder: (context, isInSubPage, _) {
            if (_currentItem == BottomNavItemId.settings && isInSubPage) {
              return const SizedBox.shrink();
            }
            return _buildBottomNavigationBar(context);
          },
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        unawaited(
          UpdatePromptCoordinator.instance.checkAndPrompt(
            context,
            reason: 'resumed',
          ),
        );
      });
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _settingsPageController.dispose();
    super.dispose();
  }
}
