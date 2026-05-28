import 'package:flutter/material.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/widgets/ui_dialog.dart';
import 'package:screen_memo/models/app_info.dart';
import 'package:screen_memo/models/screenshot_record.dart';
import 'package:screen_memo/features/capture/application/screenshot_service.dart';
import 'package:screen_memo/features/gallery/presentation/widgets/screenshot_item_widget.dart';
import 'package:screen_memo/core/widgets/search_styles.dart';
import 'package:screen_memo/core/widgets/screenshot_style_tab_bar.dart';
import 'package:screen_memo/features/apps/application/app_selection_service.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/features/favorites/application/favorite_service.dart';
import 'package:screen_memo/data/platform/path_service.dart';
import 'package:screen_memo/core/widgets/date_jump_calendar_sheet.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/features/nsfw/application/nsfw_preference_service.dart';

part 'screenshot_gallery_page_tabs_part.dart';
part 'screenshot_gallery_page_data_part.dart';
part 'screenshot_gallery_page_actions_part.dart';
part 'screenshot_gallery_page_grid_part.dart';
part 'screenshot_gallery_page_item_part.dart';
part 'screenshot_gallery_page_selection_part.dart';

/// 内部：日期Tab信息（一天为单位）
class _DayTabInfo {
  final DateTime day;
  final int startMillis;
  final int endMillis;
  int count;

  _DayTabInfo({
    required this.day,
    required this.startMillis,
    required this.endMillis,
    this.count = 0,
  });

  static bool _isSameYMD(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static bool _isToday(DateTime d) => _isSameYMD(d, DateTime.now());
  static bool _isYesterday(DateTime d) =>
      _isSameYMD(d, DateTime.now().subtract(const Duration(days: 1)));

  String buildLabel() {
    if (_isToday(day)) return '今天 $count';
    if (_isYesterday(day)) return '昨天 $count';
    return '${day.month}月${day.day}日 $count';
  }
}

class ScreenshotGalleryPage extends StatefulWidget {
  const ScreenshotGalleryPage({super.key});

  @override
  State<ScreenshotGalleryPage> createState() => _ScreenshotGalleryPageState();
}

class _ScreenshotGalleryPageState extends State<ScreenshotGalleryPage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  AppInfo _appInfo = _unknownAppInfo();
  String _packageName = '';
  List<ScreenshotRecord> _screenshots = [];
  bool _isLoading = false; // 默认不显示加载，直接显示内容
  String? _error;
  Directory? _baseDir;
  final ScrollController _scrollController = ScrollController();
  // 搜索
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<ScreenshotRecord> _searchResults = <ScreenshotRecord>[];
  Timer? _searchDebounce;
  final Map<String, Future<Map<String, dynamic>?>> _boxesFutureCache =
      <String, Future<Map<String, dynamic>?>>{};

  // 多选状态
  bool _selectionMode = false;
  final Set<int> _selectedIds = <int>{};
  final Map<int, GlobalKey> _itemKeys = <int, GlobalKey>{};
  bool _isFullySelected = false; // 标记是否已经全选所有数据
  // 收藏状态缓存
  final Map<int, bool> _favoriteStatus = <int, bool>{};
  // 取消滑动选择
  bool _initialized = false; // 避免返回时重复触发初始化加载
  bool _privacyMode = true; // 默认开启

  void _gallerySetState(VoidCallback fn) => setState(fn);

  // 缓存相关
  static const String _screenshotsCacheKeyPrefix = 'screenshots_cache_';
  static const String _screenshotsCacheTsKeyPrefix = 'screenshots_cache_ts_';
  static const int _screenshotsCacheTtlSeconds = 300; // 仅影响截图列表，不影响首页统计

  // 时间线滚动条交互状态
  bool _timelineActive = false; // 是否正在与时间线交互（长按或拖拽）
  double _timelineFraction = 0.0; // 拖动时的归一化位置 0..1
  final GlobalKey _gridKey = GlobalKey(); // 获取网格可见区域以计算首个可见项
  // 时间线拖动时的逐帧节流标记，避免频繁 jumpTo 造成抖动
  bool _scrubJumpScheduled = false;

  bool get _hasValidRouteArgs => _packageName.trim().isNotEmpty;

  static AppInfo _unknownAppInfo({
    String packageName = 'unknown',
    String appName = 'Unknown',
  }) {
    return AppInfo(
      packageName: packageName,
      appName: appName,
      icon: null,
      version: '',
      isSystemApp: false,
    );
  }

  Map<String, dynamic>? _coerceRouteArgs(Object? rawArgs) {
    if (rawArgs is! Map) return null;
    final args = <String, dynamic>{};
    for (final entry in rawArgs.entries) {
      final key = entry.key;
      if (key is String) {
        args[key] = entry.value;
      }
    }
    return args;
  }

  // 分页与懒加载
  static const int _initialPageSize = 8; // 首屏项数（用户一屏可见4个，初始加载8个确保体验）
  static const int _pageSize = 16; // 后续每次追加项数
  bool _isLoadingMore = false; // 是否正在加载更多
  bool _hasMore = true; // 是否还有更多数据
  // 旧：全量列表 _allScreenshots 已弃用（真分页改为仅维护已加载页的列表）
  int _currentDisplayCount = 0; // 当前已显示的数量
  int _pageOffset = 0; // 真分页：已加载偏移量

  // 头部统计（使用全量数据计算，避免分页导致统计不准确）
  int _totalCount = 0;
  int _totalSize = 0;
  DateTime? _latestTime;

  // 日期Tab/过滤
  TabController? _tabController;
  // 完整日期列表与当前可见窗口（默认最近14天，向前增量加载）
  final List<_DayTabInfo> _allDayTabs = <_DayTabInfo>[];
  final List<_DayTabInfo> _dayTabs = <_DayTabInfo>[];
  int _currentTabIndex = 0;
  int? _dateFilterStartMillis;
  int? _dateFilterEndMillis;
  // 简单的每Tab数据缓存，避免切换瞬时显示上一个Tab内容
  final Map<int, List<ScreenshotRecord>> _tabCache =
      <int, List<ScreenshotRecord>>{};
  final Map<int, int> _tabOffset = <int, int>{};
  final Map<int, bool> _tabHasMore = <int, bool>{};
  final Map<int, double> _tabScrollOffset = <int, double>{};
  final Map<int, ScrollController> _tabControllers = <int, ScrollController>{};

  // OCR 标注绘制器（复用全局搜索样式）

  // 日期窗口控制：默认最近14天，每次向前追加14天
  static const int _initialVisibleDayTabs = 14;
  static const int _appendVisibleDayTabs = 14;
  static const int _dayTabsLookbackDays = 120;
  bool _isExpandingDayTabs = false;
  bool _hasMoreDayTabs = false;

  @override
  void initState() {
    super.initState();
    // 主控制器用于当前Tab，其他Tab使用各自controller
    _loadPrivacyMode();
    // 预加载 NSFW 规则（异步，不阻塞UI）
    // ignore: unawaited_futures
    NsfwPreferenceService.instance.ensureRulesLoaded();
    // 订阅隐私模式变更
    AppSelectionService.instance.onPrivacyModeChanged.listen((enabled) {
      if (!mounted) return;
      setState(() {
        _privacyMode = enabled;
      });
    });
    // 搜索框焦点变化用于切换内嵌统计显示
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args = _coerceRouteArgs(ModalRoute.of(context)?.settings.arguments);
    final appInfoArg = args?['appInfo'];
    final packageNameArg = args?['packageName'];
    final packageName = packageNameArg is String ? packageNameArg.trim() : '';
    if (appInfoArg is AppInfo && packageName.isNotEmpty) {
      _appInfo = appInfoArg;
      _packageName = packageName;
      // ignore: unawaited_futures
      _loadInitialData();
    } else {
      setState(() {
        _error = AppLocalizations.of(context).invalidArguments;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            // 左侧独立logo移除：搜索框已内嵌应用图标
            Expanded(
              child: _selectionMode
                  ? Text(
                      AppLocalizations.of(
                        context,
                      ).selectedItemsCount(_selectedIds.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Container(
                      height: SearchStyles.fieldHeight,
                      decoration: SearchStyles.fieldDecoration(context),
                      alignment: Alignment.center,
                      child: ClipRRect(
                        borderRadius: SearchStyles.fieldBorderRadius,
                        child: TextField(
                          focusNode: _searchFocusNode,
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          onSubmitted: _performSearch,
                          textInputAction: TextInputAction.search,
                          style: SearchStyles.inputTextStyle(context),
                          decoration: SearchStyles.inputDecoration(
                            context: context,
                            hintText: AppLocalizations.of(
                              context,
                            ).searchPlaceholder,
                            prefixIcon: (_appInfo.icon != null)
                                ? Padding(
                                    padding: const EdgeInsets.only(
                                      left: 8,
                                      right: 6,
                                    ),
                                    child: Image.memory(
                                      _appInfo.icon!,
                                      width: 18,
                                      height: 18,
                                      fit: BoxFit.contain,
                                    ),
                                  )
                                : const Padding(
                                    padding: EdgeInsets.only(left: 8, right: 6),
                                    child: Icon(Icons.android, size: 18),
                                  ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 0,
                              minHeight: 0,
                            ),
                            // 去掉右侧搜索图标，仅在有文本时显示清除
                            suffixIcon:
                                (_searchQuery.isNotEmpty ||
                                    _searchController.text.isNotEmpty)
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    tooltip: AppLocalizations.of(
                                      context,
                                    ).actionClear,
                                    onPressed: () {
                                      _searchController.clear();
                                      _performSearch('');
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          if (!_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: _hasValidRouteArgs ? _openAppScreenshotSettings : null,
              tooltip: AppLocalizations.of(context).screenshotSectionTitle,
            ),
          ] else ...[
            TextButton(
              onPressed: () {
                setState(() {
                  _selectionMode = false;
                  _selectedIds.clear();
                  _isFullySelected = false; // 重置全选状态
                });
              },
              child: Text(AppLocalizations.of(context).dialogCancel),
            ),
            TextButton(
              onPressed: () async {
                if (_isFullySelected) {
                  setState(() {
                    _selectedIds.clear();
                    _isFullySelected = false;
                  });
                  return;
                }
                // 依据当前筛选（天Tab）决定全选范围
                List<int> allIds = <int>[];
                try {
                  if (!_hasValidRouteArgs) return;
                  if (_dateFilterStartMillis != null &&
                      _dateFilterEndMillis != null &&
                      _currentTabIndex >= 0 &&
                      _currentTabIndex < _dayTabs.length) {
                    final day = _dayTabs[_currentTabIndex];
                    allIds = await ScreenshotService.instance
                        .getScreenshotIdsByAppBetween(
                          _packageName,
                          startMillis: day.startMillis,
                          endMillis: day.endMillis,
                        );
                  } else {
                    allIds = await ScreenshotService.instance
                        .getAllScreenshotIdsForApp(_packageName);
                  }
                } catch (_) {}
                if (!mounted) return;
                setState(() {
                  _selectedIds
                    ..clear()
                    ..addAll(allIds);
                  _isFullySelected = true;
                  _selectionMode = true;
                });
              },
              child: Text(_getSelectAllButtonText()),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: AppLocalizations.of(context).deleteSelectedTooltip,
              onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    _tabController?.removeListener(_onTabControllerChanged);
    _tabController?.dispose();
    super.dispose();
  }
}
