import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:screen_memo/models/app_info.dart';
import 'package:screen_memo/models/screenshot_record.dart';
import 'package:screen_memo/features/apps/application/app_selection_service.dart';
import 'package:screen_memo/data/platform/path_service.dart';
import 'package:screen_memo/features/capture/application/screenshot_service.dart';
import 'package:screen_memo/features/search/application/ocr_search_service.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/utils/merged_event_summary.dart';
import 'package:screen_memo/features/gallery/presentation/widgets/screenshot_item_widget.dart';
import 'package:screen_memo/core/widgets/search_styles.dart';
import 'package:screen_memo/core/widgets/screenshot_style_tab_bar.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/core/widgets/ui_dialog.dart';
import 'package:screen_memo/features/nsfw/application/nsfw_preference_service.dart';
import 'package:screen_memo/features/daily_summary/presentation/pages/daily_summary_page.dart';

part 'search_page_helpers_part.dart';
part 'search_page_search_part.dart';
part 'search_page_filter_part.dart';
part 'search_page_views_part.dart';
part 'search_page_docs_part.dart';
part 'search_page_sheets_part.dart';
part 'search_page_segments_part.dart';
part 'search_page_widgets_part.dart';

/// 搜索类型枚举
enum SearchTab { all, screenshots, moments }

/// 自定义 <mark> 语法解析
class MarkSyntax extends md.InlineSyntax {
  MarkSyntax() : super(r'<mark>(.+?)</mark>');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match[1] ?? '';
    parser.addNode(md.Element.text('mark', text));
    return true;
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final Map<String, Future<Map<String, dynamic>?>> _boxesFutureCache =
      <String, Future<Map<String, dynamic>?>>{};
  final Map<String, AppInfo> _appInfoByPackage = <String, AppInfo>{};

  List<ScreenshotRecord> _results = <ScreenshotRecord>[];
  List<ScreenshotRecord> _filteredResults = <ScreenshotRecord>[]; // 筛选后的结果
  bool _isLoading = false;
  String? _error;
  Timer? _debounce;
  Directory? _baseDir;
  bool _privacyMode = true;

  static const int _firstBatchSize = 6; // 首批快速返回数量
  static const int _pageSize = 24; // 后续分页大小
  static const Set<String> _docTabTypes = <String>{
    kSearchDocTypeDailySummary,
    kSearchDocTypeMorningInsights,
    kSearchDocTypeFavoriteNote,
  };
  static const Set<String> _docIndexSources = <String>{
    kSearchIndexSourceFavorites,
    kSearchIndexSourceDailySummaries,
    kSearchIndexSourceMorningInsights,
  };
  int _offset = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  String _lastQuery = '';
  bool _usingAiImageMeta = false; // OCR 无结果时回退 AI 图片元数据检索
  bool _usingFavoriteNotes = false; // OCR/AI 都无结果时回退收藏备注检索

  // Tab 切换相关
  late TabController _tabController;

  // 动态搜索相关状态
  List<Map<String, dynamic>> _segmentResults = <Map<String, dynamic>>[];
  int _segmentOffset = 0;
  bool _segmentHasMore = false;
  bool _segmentLoadingMore = false;
  int _segmentTotalCount = 0;
  bool _segmentCountingTotal = false;
  bool _segmentSearchFinished = false;
  bool _segmentSearching = false;

  // “更多”搜索相关状态（SearchIndex：daily/morning/persona/favorite_note 等）
  List<Map<String, dynamic>> _docResults = <Map<String, dynamic>>[];
  int _docOffset = 0;
  bool _docHasMore = false;
  bool _docLoadingMore = false;
  int _docTotalCount = 0;
  bool _docCountingTotal = false;
  bool _docSearchFinished = false;
  bool _docSearching = false;
  // 空集合表示“全部类型”（与其它筛选一致：未选即不过滤）
  Set<String> _docSelectedTypes = <String>{};

  // “语义”搜索相关状态（ai_image_meta：图片标签/描述）
  List<ScreenshotRecord> _semanticResults = <ScreenshotRecord>[];
  List<ScreenshotRecord> _filteredSemanticResults = <ScreenshotRecord>[];
  final Map<String, Set<String>> _semanticTagsByPath = <String, Set<String>>{};
  Set<String> _semanticAvailableTags = <String>{};
  Set<String> _semanticSelectedTags = <String>{};
  int _semanticOffset = 0;
  bool _semanticHasMore = false;
  bool _semanticLoadingMore = false;
  int _semanticTotalCount = 0;
  bool _semanticCountingTotal = false;
  bool _semanticSearchFinished = false;
  bool _semanticSearching = false;
  final ScrollController _semanticScrollController = ScrollController();

  // 标签筛选相关
  Set<String> _availableTags = <String>{}; // 从搜索结果中提取的可用标签
  Set<String> _selectedTags = <String>{}; // 当前选中的标签筛选（支持多选）

  /// 根据标签筛选后的动态数量

  // 筛选相关状态
  String _timeFilter =
      'last30days'; // all, today, yesterday, last7days, last30days, customDays
  int _customDays = 30; // 自定义天数，默认30天
  String _sizeFilter = 'all'; // all, small, medium, large
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  int _totalResultsCount = 0; // 总结果数(未筛选前)
  bool _countingTotal = false;
  int _searchToken = 0;

  // 可见范围索引（用于限制仅可见区域附近才进行OCR标注计算）
  int _visibleStartIndex = 0;
  int _visibleEndIndex = -1;
  final GlobalKey _gridKey = GlobalKey();
  final Map<int, GlobalKey> _itemKeys = <int, GlobalKey>{};
  bool _scrollActive = false;
  Timer? _scrollIdleTimer;

  // part 文件需要触发 UI 刷新时统一通过该方法，避免直接访问 State.setState。
  void _searchSetState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _initBaseDir();
    _scrollController.addListener(_onScroll);
    _loadAppInfos();
    _loadPrivacyMode();
    // 预加载 NSFW 规则（异步，不阻塞UI）
    // ignore: unawaited_futures
    NsfwPreferenceService.instance.ensureRulesLoaded();
    AppSelectionService.instance.onPrivacyModeChanged.listen((enabled) {
      if (!mounted) return;
      setState(() => _privacyMode = enabled);
    });
  }

  void _onTabChanged() {
    // TabBarView 会自动同步，此处用于更新 Tab 计数显示
    if (_tabController.indexIsChanging || !mounted) return;
    setState(() {});
  }

  Future<void> _initBaseDir() async {
    try {
      final dir = await PathService.getInternalAppDir(null);
      if (mounted) setState(() => _baseDir = dir);
    } catch (_) {}
  }

  Future<void> _loadAppInfos() async {
    try {
      final cachedApps = await AppSelectionService.instance
          .getCachedAppInfoByPackage();
      final apps = await AppSelectionService.instance.getAllInstalledApps();
      if (!mounted) return;
      setState(() {
        _appInfoByPackage
          ..clear()
          ..addAll(cachedApps)
          ..addEntries(apps.map((a) => MapEntry(a.packageName, a)));
      });
    } catch (_) {}
  }

  Future<void> _loadPrivacyMode() async {
    try {
      final enabled = await AppSelectionService.instance
          .getPrivacyModeEnabled();
      if (mounted) setState(() => _privacyMode = enabled);
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _semanticScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final pos = _scrollController.position.pixels;
    if (pos >= max * 0.85) {
      try {
        print('[搜索] 滚动触发加载更多：当前位置=' + pos.toString() + ' 最大=' + max.toString());
      } catch (_) {}
      _loadMore();
    }
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search(text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        toolbarHeight: 48,
        title: Row(
          children: [
            Expanded(
              child: Theme(
                data: SearchStyles.inputTheme(context),
                child: Container(
                  height: SearchStyles.fieldHeight,
                  decoration: SearchStyles.fieldDecoration(context),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      Icon(
                        Icons.search,
                        color: SearchStyles.placeholderColor(context),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: true,
                          decoration: SearchStyles.inputDecoration(
                            context: context,
                            isCollapsed: true,
                            hintText: AppLocalizations.of(
                              context,
                            ).searchPlaceholder,
                          ),
                          style: SearchStyles.inputTextStyle(context),
                          textInputAction: TextInputAction.search,
                          onChanged: _onQueryChanged,
                          onSubmitted: (v) => _search(v.trim()),
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, _) {
                          final bool showClear = value.text.trim().isNotEmpty;
                          if (!showClear) return const SizedBox.shrink();
                          return IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: AppLocalizations.of(context).actionClear,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            onPressed: () {
                              _debounce?.cancel();
                              _controller.clear();
                              _search('');
                              _focusNode.requestFocus();
                            },
                          );
                        },
                      ),
                      // 时间范围选择按钮（嵌入搜索框内）
                      _buildTimeRangeDropdown(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }
}
