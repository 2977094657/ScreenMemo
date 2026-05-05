import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/models/app_info.dart';
import 'package:screen_memo/features/apps/application/app_selection_service.dart';
import 'package:screen_memo/features/capture/application/screenshot_service.dart';
import 'package:screen_memo/features/permissions/application/permission_service.dart';
import 'package:screen_memo/core/theme/theme_service.dart';
import 'package:screen_memo/core/localization/locale_service.dart';
import 'package:screen_memo/core/performance/startup_profiler.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/core/widgets/ui_dialog.dart';
import 'package:screen_memo/core/widgets/selection_checkbox.dart';
import 'package:screen_memo/core/widgets/search_styles.dart';
import 'package:screen_memo/features/capture/application/ime_exclusion_service.dart';
import 'package:screen_memo/features/apps/presentation/widgets/app_selection_widget.dart';
import 'package:screen_memo/features/capture/data/per_app_screenshot_settings_service.dart';
import 'package:screen_memo/features/daily_summary/application/daily_summary_service.dart';
import 'package:screen_memo/features/daily_summary/presentation/pages/daily_summary_page.dart';
import 'package:screen_memo/features/capture/presentation/pages/exclusion_help_page.dart';
import 'package:screen_memo/features/settings/presentation/pages/settings_page.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'dart:async';
import 'dart:math';

part 'home_page_data_part.dart';
part 'home_page_diagnostics_part.dart';
part 'home_page_morning_part.dart';
part 'home_page_permission_ui_part.dart';
part 'home_page_content_part.dart';
part 'home_page_language_part.dart';

class _HomeRuntimeDiagnostic {
  final String id;
  final String title;
  final String summary;
  final List<String> details;
  final String copyText;
  final String? filePath;
  final String? nativeIssueId;
  final bool showSettingsAction;

  const _HomeRuntimeDiagnostic({
    required this.id,
    required this.title,
    required this.summary,
    required this.details,
    required this.copyText,
    this.filePath,
    this.nativeIssueId,
    this.showSettingsAction = false,
  });
}

/// 主应用界面
class HomePage extends StatefulWidget {
  final ThemeService themeService;

  const HomePage({super.key, required this.themeService});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final AppSelectionService _appService = AppSelectionService.instance;

  List<AppInfo> _selectedApps = AppSelectionService.instance.selectedApps;
  List<AppInfo> _savedSelectedApps = AppSelectionService.instance.selectedApps;
  Set<String> _installedPackages = <String>{};
  Map<String, AppInfo> _installedAppsByPackage = <String, AppInfo>{};
  Map<String, AppInfo> _cachedAppsByPackage = <String, AppInfo>{};
  bool _installedAppsLoaded = false;
  String _sortMode = 'timeDesc';
  bool _sortOrderAsc = false; // 新增：排序顺序，false为降序，true为升序
  bool _screenshotEnabled = false;
  int _screenshotInterval = 5;
  bool _isLoading = false; // 不显示全屏加载动画
  bool _initialized = true; // 直接认为已初始化，避免首屏Loading
  bool _hasPermissionIssues = false; // 权限问题状态
  _HomeRuntimeDiagnostic? _runtimeDiagnostic;
  bool _runtimeDiagnosticExpanded = false;
  String? _lastAutoOpenedDiagnosticId;
  final Set<String> _dismissedDiagnosticIds = <String>{};
  Map<String, dynamic> _screenshotStats = {}; // 截图统计数据
  Map<String, dynamic> _totals = {}; // 新增：汇总统计数据
  bool _selectionMode = false;
  final Set<String> _selectedPackages = <String>{};
  // 记录已开启“每应用自定义设置”的应用包名集合
  final Set<String> _customEnabledPackages = <String>{};
  final DailySummaryService _dailySummaryService = DailySummaryService.instance;
  late final EasyRefreshController _refreshController;
  static const double _morningRevealMaxHeight = 72;
  MorningInsights? _morningInsights;
  int _morningTipIndex = -1;
  MorningInsightEntry? _currentMorningTip;
  final Random _random = Random();
  List<int> _morningTipDeck = <int>[];
  String? _morningTipDeckSignature;
  int? _lastMorningTipIndex;
  final List<DateTime> _morningRefreshHistory = <DateTime>[];
  DateTime? _morningCooldownUntil;
  String? _morningCooldownMessage;
  static const int _morningMaxRefreshInWindow = 10;
  static const Duration _morningRefreshWindow = Duration(minutes: 1);
  static const Duration _morningCooldownDuration = Duration(minutes: 3);
  static const int _morningAvailableHour = 8;
  bool _morningGenerationRunning = false;

  void _homeSetState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _refreshController = EasyRefreshController(controlFinishRefresh: true);
    WidgetsBinding.instance.addObserver(this);
    StartupProfiler.begin('HomePage.initState+loadData');
    // 将数据加载与权限检查延后到首帧之后，避免阻塞首帧
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadData();
      // 首次进入时加载每应用自定义开关
      // ignore: unawaited_futures
      _loadPerAppCustomFlags();
      // 首帧后后台刷新应用列表（如缓存过期）
      // ignore: unawaited_futures
      AppSelectionService.instance.refreshAppsInBackgroundIfStale();
      // 权限相关检查稍后执行，避免与首帧竞争
      Future.delayed(const Duration(milliseconds: 600), () {
        PermissionService.instance.startMonitoring();
        _checkPermissionIssues(autoOpenDiagnostic: true);
        _checkScreenshotToggleState();
      });
      // 预加载晨间建议，首次展示时可快速切换
      // ignore: unawaited_futures
      _preloadMorningInsights();
    });
    ScreenshotService.instance.onScreenshotSaved.listen((_) {
      // 收到新增/删除事件，直接拉取最新统计（不走缓存）
      _loadStatsFresh();
      _loadTotals(); // 同时刷新汇总统计
    });

    // 订阅排序模式变更，自动刷新排序
    AppSelectionService.instance.onSortModeChanged.listen((mode) {
      if (!mounted) return;
      setState(() {
        _sortMode = mode;
      });
      _sortApps();
    });

    // 设置权限状态监听
    final permissionService = PermissionService.instance;
    permissionService.onPermissionsUpdated = () async {
      if (mounted) {
        // 立即检查权限问题并更新UI
        await _checkPermissionIssues(autoOpenDiagnostic: true);

        // 检查截屏开关状态是否需要自动关闭
        await _checkScreenshotToggleState();
      }
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 应用从后台返回前台：强制同步文件到数据库并刷新统计，避免节流导致读到旧数据
      Future.delayed(const Duration(milliseconds: 300), () async {
        await _loadStatsFresh();
        // 回到前台后同步刷新自定义标记
        // ignore: unawaited_futures
        _loadPerAppCustomFlags();
        await _checkPermissionIssues(autoOpenDiagnostic: true);
        await _checkScreenshotToggleState();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshController.dispose();
    super.dispose();
  }

  /// 检查是否有权限缺失

  /// 刷新权限状态
  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 构建 AppBar 的 actions（选择模式时显示批量操作）
    final List<String> selectablePackages = _selectedApps
        .where(_isAppSelectable)
        .map((app) => app.packageName)
        .toList();
    final List<Widget>? appBarActions = _selectionMode
        ? <Widget>[
            TextButton(
              onPressed: () {
                setState(() {
                  _selectionMode = false;
                  _selectedPackages.clear();
                });
              },
              child: Text(AppLocalizations.of(context).dialogCancel),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  if (selectablePackages.isNotEmpty &&
                      _selectedPackages.length == selectablePackages.length) {
                    _selectedPackages.clear();
                  } else {
                    _selectedPackages
                      ..clear()
                      ..addAll(selectablePackages);
                  }
                });
              },
              child: Text(AppLocalizations.of(context).selectAll),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: AppLocalizations.of(context).removeMonitoring,
              onPressed: _selectedPackages.isEmpty ? null : _removeSelectedApps,
            ),
          ]
        : null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        // Keep the same background when content scrolls under the AppBar (Material 3).
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 48,
        automaticallyImplyLeading: false,
        leadingWidth: 0,
        titleSpacing: 0,
        actions: appBarActions,
        title: _selectionMode
            ? Padding(
                padding: const EdgeInsets.only(left: AppTheme.spacing4),
                child: Text(
                  AppLocalizations.of(
                    context,
                  ).selectedItemsCount(_selectedPackages.length),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing4,
                ),
                child: Row(
                  children: [
                    // 左侧:语言切换图标
                    _buildToolbarActionButton(
                      icon: _buildHomeToolbarIcon(Icons.language),
                      tooltip: AppLocalizations.of(
                        context,
                      ).languageSettingTitle,
                      onPressed: _showLanguageBottomSheet,
                    ),

                    // 加号按钮
                    const SizedBox(width: AppTheme.spacing2),
                    _buildToolbarActionButton(
                      icon: _buildHomeToolbarIcon(Icons.add),
                      tooltip: AppLocalizations.of(context).navSelectApps,
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              appBar: AppBar(
                                title: Text(
                                  AppLocalizations.of(context).navSelectApps,
                                ),
                                actions: [
                                  IconButton(
                                    tooltip: AppLocalizations.of(
                                      context,
                                    ).whySomeAppsHidden,
                                    icon: const Icon(Icons.help_outline),
                                    onPressed: () async {
                                      // 收集已启用输入法及默认输入法
                                      final imeList =
                                          await ImeExclusionService.getEnabledImeList();
                                      final defaultIme =
                                          await ImeExclusionService.getDefaultImeInfo();

                                      final lines = <Widget>[];
                                      lines.add(
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          ).excludedAppsIntro,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                      );
                                      lines.add(const SizedBox(height: 8));
                                      // 本应用
                                      lines.add(
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          ).excludedThisApp,
                                        ),
                                      );
                                      lines.add(
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          ).excludedAutomationApps,
                                        ),
                                      );
                                      // 输入法应用
                                      if (imeList.isNotEmpty) {
                                        lines.add(const SizedBox(height: 8));
                                        lines.add(
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            ).excludedImeApps,
                                          ),
                                        );
                                        for (final m in imeList) {
                                          final name = m['appName'] ?? '';
                                          lines.add(
                                            Text(
                                              '  - ${name.isNotEmpty ? name : AppLocalizations.of(context).unknownIme}',
                                            ),
                                          );
                                        }
                                      } else {
                                        lines.add(const SizedBox(height: 8));
                                        lines.add(
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            ).excludedImeAppsFiltered,
                                          ),
                                        );
                                      }
                                      if (defaultIme != null &&
                                          (defaultIme['packageName']
                                                  ?.isNotEmpty ??
                                              false)) {
                                        lines.add(const SizedBox(height: 8));
                                        lines.add(
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            ).currentDefaultIme(
                                              defaultIme['appName'] ?? '',
                                              defaultIme['packageName'] ?? '',
                                            ),
                                          ),
                                        );
                                      }
                                      await showUIDialog<void>(
                                        context: context,
                                        title: AppLocalizations.of(
                                          context,
                                        ).excludedAppsTitle,
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: lines,
                                        ),
                                        actions: [
                                          UIDialogAction(
                                            text: AppLocalizations.of(
                                              context,
                                            ).gotIt,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      await _appService.saveSelectedApps(
                                        _savedSelectedApps,
                                      );
                                      if (mounted) Navigator.of(context).pop();
                                      await _loadData(soft: true);
                                    },
                                    child: Text(
                                      AppLocalizations.of(context).dialogDone,
                                    ),
                                  ),
                                ],
                              ),
                              body: AppSelectionWidget(
                                displayAsList: true,
                                onSelectionChanged: (apps) {
                                  _savedSelectedApps = apps;
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // 首页不再显示排序图标，排序在设置页调整
                    const SizedBox(width: AppTheme.spacing2),

                    // 搜索框 - 大幅增加flex权重
                    Expanded(flex: 7, child: _buildSearchBar(context)),

                    const SizedBox(width: AppTheme.spacing2),

                    // 搜索框右侧：权限提示 或 开关
                    _hasPermissionIssues
                        ? _buildToolbarActionButton(
                            icon: _buildHomeToolbarIcon(
                              Icons.warning,
                              color: AppTheme.destructive,
                            ),
                            tooltip: AppLocalizations.of(
                              context,
                            ).permissionMissing,
                            onPressed: _showPermissionStatus,
                          )
                        : _buildToolbarActionButton(
                            tooltip: _screenshotEnabled
                                ? AppLocalizations.of(context).stopScreenshot
                                : AppLocalizations.of(context).startScreenshot,
                            onPressed: _toggleScreenshotEnabled,
                            icon: _screenshotEnabled
                                ? _buildHomeToolbarIcon(
                                    Icons.camera_alt_outlined,
                                  )
                                : _buildHomeToolbarIcon(
                                    Icons.no_photography_outlined,
                                    color: AppTheme.destructive,
                                  ),
                          ),

                    // 右侧:主题切换图标
                    const SizedBox(width: AppTheme.spacing2),
                    _buildToolbarActionButton(
                      icon: _buildHomeToolbarIcon(
                        widget.themeService.themeModeIcon,
                      ),
                      tooltip: _themeModeTooltip(context),
                      onPressed: () async {
                        await widget.themeService.toggleTheme();
                      },
                    ),
                  ],
                ),
              ),
      ),
      body: Column(
        children: [
          // 新增：副导航栏
          _buildSubNavigation(),
          if (_runtimeDiagnostic != null) _buildRuntimeDiagnosticDrawer(),
          Expanded(
            child: EasyRefresh.builder(
              controller: _refreshController,
              header: _buildMorningHeader(context),
              onRefresh: _handleHomeRefresh,
              childBuilder: (context, physics) => _buildAppsList(physics),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
