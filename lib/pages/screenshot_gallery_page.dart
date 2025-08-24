import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_dialog.dart';
import '../models/app_info.dart';
import '../models/screenshot_record.dart';
import '../services/screenshot_service.dart';
import '../services/path_service.dart';
import '../widgets/ui_components.dart';

class ScreenshotGalleryPage extends StatefulWidget {
  const ScreenshotGalleryPage({super.key});

  @override
  State<ScreenshotGalleryPage> createState() => _ScreenshotGalleryPageState();
}

class _ScreenshotGalleryPageState extends State<ScreenshotGalleryPage> with AutomaticKeepAliveClientMixin {
  late AppInfo _appInfo;
  late String _packageName;
  List<ScreenshotRecord> _screenshots = [];
  bool _isLoading = false;  // 默认不显示加载，直接显示内容
  String? _error;
  Directory? _baseDir;
  final ScrollController _scrollController = ScrollController();
  // 多选状态
  bool _selectionMode = false;
  final Set<int> _selectedIds = <int>{};
  final Map<int, GlobalKey> _itemKeys = <int, GlobalKey>{};
  // 取消滑动选择
  bool _initialized = false; // 避免返回时重复触发初始化加载
  
  // 缓存相关
  static const String _screenshotsCacheKeyPrefix = 'screenshots_cache_';
  static const String _screenshotsCacheTsKeyPrefix = 'screenshots_cache_ts_';
  static const int _screenshotsCacheTtlSeconds = 300; // 仅影响截图列表，不影响首页统计

  // 时间线滚动条交互状态
  bool _timelineActive = false; // 是否正在与时间线交互（长按或拖拽）
  double _timelineFraction = 0.0; // 拖动时的归一化位置 0..1
  final GlobalKey _gridKey = GlobalKey(); // 获取网格可见区域以计算首个可见项

  // 分页与懒加载
  static const int _initialPageSize = 8; // 首屏项数（用户一屏可见4个，初始加载8个确保体验）
  static const int _pageSize = 16; // 后续每次追加项数
  bool _isLoadingMore = false; // 是否正在加载更多
  bool _hasMore = true; // 是否还有更多数据
  List<ScreenshotRecord> _allScreenshots = []; // 所有截图数据（从缓存或数据库加载）
  int _currentDisplayCount = 0; // 当前已显示的数量

  // 头部统计（使用全量数据计算，避免分页导致统计不准确）
  int _totalCount = 0;
  int _totalSize = 0;
  DateTime? _latestTime;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollChanged);
  }

  void _onScrollChanged() {
    // 非交互状态下，同步刷新以更新时间线拇指位置
    if (!_timelineActive && mounted) {
      setState(() {});
    }
    
    // 检查是否需要加载更多
    if (_hasMore && !_isLoadingMore && _scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      final threshold = maxScroll * 0.8; // 滚动到80%时触发加载
      
      if (currentScroll >= threshold && _currentDisplayCount < _allScreenshots.length) {
        _loadMoreScreenshots();
      }
    }
  }
  
  /// 加载更多截图到显示列表
  void _loadMoreScreenshots() {
    if (_isLoadingMore || _currentDisplayCount >= _allScreenshots.length) return;
    
    // 设置加载状态，防止重复加载
    _isLoadingMore = true;
    
    // 直接加载，无需延迟
    if (!mounted) return;
    
    final nextBatch = _currentDisplayCount + _pageSize;
    final endIndex = nextBatch > _allScreenshots.length ? _allScreenshots.length : nextBatch;
    
    setState(() {
      // 添加下一批数据到显示列表
      _screenshots = _allScreenshots.sublist(0, endIndex);
      _currentDisplayCount = endIndex;
      
      // 检查是否还有更多
      _hasMore = _currentDisplayCount < _allScreenshots.length;
      _isLoadingMore = false;
      
      // 清理不在显示范围内的键
      _itemKeys.removeWhere((index, _) => index >= _screenshots.length);
    });
  }

  /// 构建标题栏右侧统计文本：X张 · Y.YYMB/GB/TB · 时间
  String _buildHeaderStatsText() {
    // 使用全量数据的统计信息，而不是当前显示的部分数据
    String timeStr = '暂无';
    if (_latestTime != null) {
      timeStr = _formatDateTime(_latestTime!);
    }
    return '$_totalCount张 · ${_formatTotalSizeMBGBTB(_totalSize)} · $timeStr';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _appInfo = args['appInfo'] as AppInfo;
      _packageName = args['packageName'] as String;
      _loadInitialData();
    } else {
      setState(() {
        _error = '参数错误';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadInitialData() async {
    try {
      // 使用PathService获取正确的外部文件目录
      final dir = await PathService.getExternalFilesDir(null);

      if (dir == null) {
        throw Exception("无法获取应用目录");
      }

      print('PathService返回的目录: ${dir.path}');

      setState(() {
        _baseDir = dir;
      });
      await _loadScreenshots();
    } catch (e) {
      setState(() {
       _error = '初始化失败: $e';
     });
   }
  }

  Future<void> _loadScreenshots() async {
    try {
      print('=== 开始加载截图 ===');
      print('应用包名: $_packageName');
      print('基础目录: ${_baseDir?.path}');
      print('当前截图数量: ${_screenshots.length}');

      // 先设置加载状态，防止显示空状态
      if (_screenshots.isEmpty) {
        setState(() {
          _isLoading = true;
        });
      }

      // 尝试从缓存加载（仅用于提升进入速度，不影响首页统计）
      final cachedScreenshots = await _loadScreenshotsFromCache();
      if (cachedScreenshots != null && cachedScreenshots.isNotEmpty) {
        print('从缓存加载到 ${cachedScreenshots.length} 张截图');
        _processLoadedScreenshots(cachedScreenshots);
        // 后台刷新缓存
        _refreshScreenshotsCache();
        return;
      }

      // 缓存不存在或为空，从数据库加载
      print('缓存为空，从数据库加载');
      await _loadScreenshotsFromDatabase();
    } catch (e) {
      print('加载截图失败: $e');
      setState(() {
        _error = '加载截图失败: $e';
        _isLoading = false;
      });
    }
  }
  
  /// 处理加载的截图数据，实现分页显示
  void _processLoadedScreenshots(List<ScreenshotRecord> allScreenshots) {
    // 保存全量数据
    _allScreenshots = allScreenshots;
    
    // 计算统计信息
    _totalCount = allScreenshots.length;
    _totalSize = allScreenshots.fold<int>(0, (sum, r) => sum + r.fileSize);
    if (allScreenshots.isNotEmpty) {
      final latest = allScreenshots.reduce((a, b) =>
        a.captureTime.isAfter(b.captureTime) ? a : b);
      _latestTime = latest.captureTime;
    }
    
    // 初始只显示前面一部分
    final initialCount = _initialPageSize > allScreenshots.length
        ? allScreenshots.length
        : _initialPageSize;
    
    setState(() {
      _screenshots = allScreenshots.sublist(0, initialCount);
      _currentDisplayCount = initialCount;
      // 修复：确保 _hasMore 逻辑正确
      _hasMore = initialCount < allScreenshots.length;
      _isLoading = false;  // 数据加载完成，取消加载状态
      _itemKeys.clear();
    });
    
    print('初始加载 $_currentDisplayCount/${_totalCount} 张截图，hasMore: $_hasMore');
  }

  /// 从数据库加载截图数据
  Future<void> _loadScreenshotsFromDatabase() async {
    try {
      // 直接从数据库查询，后台同步已在ScreenshotService中处理
      final screenshots = await ScreenshotService.instance.getScreenshotsByApp(_packageName);
      print('从数据库获取到 ${screenshots.length} 张截图');

      _processLoadedScreenshots(screenshots);

      // 保存到缓存
      await _saveScreenshotsToCache(screenshots);
    } catch (e) {
      print('从数据库加载截图失败: $e');
      setState(() {
        _error = '数据库查询失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 从缓存加载截图数据
  Future<List<ScreenshotRecord>?> _loadScreenshotsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_screenshotsCacheKeyPrefix$_packageName';
      final tsKey = '$_screenshotsCacheTsKeyPrefix$_packageName';
      
      final cachedJson = prefs.getString(cacheKey);
      final ts = prefs.getInt(tsKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      if (cachedJson != null && ts > 0 && (now - ts) <= _screenshotsCacheTtlSeconds * 1000) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        return decoded.map((item) => ScreenshotRecord.fromMap(item)).toList();
      }
      return null;
    } catch (e) {
      print('从缓存加载截图失败: $e');
      return null;
    }
  }

  /// 保存截图数据到缓存
  Future<void> _saveScreenshotsToCache(List<ScreenshotRecord> screenshots) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_screenshotsCacheKeyPrefix$_packageName';
      final tsKey = '$_screenshotsCacheTsKeyPrefix$_packageName';
      
      final jsonList = screenshots.map((s) => s.toMap()).toList();
      await prefs.setString(cacheKey, jsonEncode(jsonList));
      await prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('保存截图到缓存失败: $e');
    }
  }

  /// 后台刷新截图缓存
  Future<void> _refreshScreenshotsCache() async {
    try {
      // 直接查询数据库，后台同步已在ScreenshotService中处理
      final screenshots = await ScreenshotService.instance.getScreenshotsByApp(_packageName);
      await _saveScreenshotsToCache(screenshots);
      
      // 如果有新数据，更新UI
      if (screenshots.length != _allScreenshots.length) {
        _processLoadedScreenshots(screenshots);
      }
    } catch (e) {
      print('后台刷新截图缓存失败: $e');
    }
  }

  /// 使截图缓存失效
  Future<void> _invalidateScreenshotsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_screenshotsCacheKeyPrefix$_packageName';
      final tsKey = '$_screenshotsCacheTsKeyPrefix$_packageName';
      
      await prefs.remove(cacheKey);
      await prefs.remove(tsKey);
      print('已使截图缓存失效: $cacheKey');
    } catch (e) {
      print('使截图缓存失效失败: $e');
    }
  }

  void _viewScreenshot(ScreenshotRecord screenshot, int index) {
    // 查看时使用全量数据，确保可以滑动查看所有图片
    Navigator.pushNamed(
      context,
      '/screenshot_viewer',
      arguments: {
        'screenshots': _allScreenshots.isEmpty ? _screenshots : _allScreenshots,
        'initialIndex': _allScreenshots.isEmpty ? index : _allScreenshots.indexOf(screenshot),
        'appName': _appInfo.appName,
        'appInfo': _appInfo, // 传递完整的appInfo对象，包含图标
      },
    );
  }

  Future<void> _deleteScreenshot(ScreenshotRecord screenshot) async {
    final confirmed = await showUIDialog<bool>(
      context: context,
      title: '确认删除',
      message: '确定要删除这张截图吗？此操作无法撤销。',
      actions: const [
        UIDialogAction<bool>(text: '取消', result: false),
        UIDialogAction<bool>(text: '删除', style: UIDialogActionStyle.destructive, result: true),
      ],
      barrierDismissible: false,
    );

    if (confirmed == true && screenshot.id != null) {
      try {
        final success = await ScreenshotService.instance.deleteScreenshot(screenshot.id!);
        if (success) {
          setState(() {
            _screenshots.removeWhere((s) => s.id == screenshot.id);
          });
          // 删除后失效首页统计缓存
          await ScreenshotService.instance.invalidateStatsCache();
          // 删除后失效截图列表缓存
          await _invalidateScreenshotsCache();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('截图已删除'),
                backgroundColor: AppTheme.success,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('删除失败'),
                backgroundColor: AppTheme.destructive,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('删除失败: $e'),
              backgroundColor: AppTheme.destructive,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
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
            if (_appInfo.icon != null)
              Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: 8),
                child: Image.memory(_appInfo.icon!, fit: BoxFit.contain),
              )
            else
              const Icon(Icons.android, size: 20, color: AppTheme.foreground),
            const SizedBox(width: 6),
            Expanded(
              child: _selectionMode
                  ? Text(
                      '已选择 ${_selectedIds.length} 项',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    )
                  : Text(
                      _appInfo.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          if (!_selectionMode) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  _buildHeaderStatsText(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadScreenshots,
              tooltip: '刷新',
            ),
          ] else ...[
            TextButton(
              onPressed: () {
                setState(() {
                  _selectionMode = false;
                  _selectedIds.clear();
                });
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selectedIds.length == _screenshots.length) {
                    _selectedIds.clear();
                  } else {
                    _selectedIds
                      ..clear()
                      ..addAll(_screenshots.where((s) => s.id != null).map((s) => s.id!));
                  }
                });
              },
              child: const Text('全选'),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除所选',
              onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // 优先显示错误状态
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppTheme.destructive,
            ),
            const SizedBox(height: AppTheme.spacing4),
            Text(
              _error!,
              style: const TextStyle(color: AppTheme.destructive),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacing4),
            UIButton(
              text: '重试',
              onPressed: _loadInitialData,
              variant: UIButtonVariant.outline,
            ),
          ],
        ),
      );
    }

    // 如果有数据就直接显示网格，即使数据正在加载
    if (_screenshots.isNotEmpty || _isLoading) {
      return _buildGalleryGrid();
    }

    // 只有在确实没有数据且不在加载时才显示空状态
    if (_screenshots.isEmpty && !_isLoading) {
      // 延迟显示空状态，给缓存加载一点时间
      return FutureBuilder(
        future: Future.delayed(const Duration(milliseconds: 300)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && _screenshots.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 64,
                    color: AppTheme.mutedForeground,
                  ),
                  SizedBox(height: AppTheme.spacing4),
                  Text(
                    '暂无截图',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                  SizedBox(height: AppTheme.spacing2),
                  Text(
                    '开启截图监控后，截图将显示在这里',
                    style: TextStyle(color: AppTheme.mutedForeground),
                  ),
                ],
              ),
            );
          }
          // 加载中时显示空白，避免闪烁
          return const SizedBox.shrink();
        },
      );
    }

    return _buildGalleryGrid();
  }

  Widget _buildGalleryGrid() {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTheme.spacing1), // 减少外边距
          child: Container(
            key: _gridKey,
            child: GridView.builder(
              key: PageStorageKey<String>('screenshot_gallery_grid_$_packageName'),
              controller: _scrollController,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + AppTheme.spacing6,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppTheme.spacing1, // 减少间距
                mainAxisSpacing: AppTheme.spacing1, // 减少间距
                childAspectRatio: 0.45, // 显著增加图片高度，确保图片显示完整
              ),
              itemCount: _screenshots.length,
              itemBuilder: (context, index) {
                final screenshot = _screenshots[index];
                return _buildScreenshotItem(screenshot, index);
              },
            ),
          ),
        ),
        _buildTimelineOverlay(),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildScreenshotItem(ScreenshotRecord screenshot, int index) {
    if (_baseDir == null) {
      return _buildErrorItem("应用目录未初始化");
    }

    final absolutePath = path.join(_baseDir!.path, screenshot.filePath);
    final file = File(absolutePath);

    final isSelected = _selectionMode && screenshot.id != null && _selectedIds.contains(screenshot.id);
    final GlobalKey itemKey = _itemKeys.putIfAbsent(index, () => GlobalKey());
    final item = GestureDetector(
      onTap: () {
        if (_selectionMode) {
          _toggleSelect(index);
        } else {
          _viewScreenshot(screenshot, index);
        }
      },
      onLongPress: () {
        if (!_selectionMode) {
          setState(() => _selectionMode = true);
        }
        _toggleSelect(index);
      },
      child: Stack(
        children: [
          // 图片直接显示，无容器包装
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: Builder(
              builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                // 使用按视口尺寸下采样的缩略图以提升快速拖动时的首帧显示速度
                final screenWidth = MediaQuery.of(context).size.width;
                // 计算两列网格每项的近似逻辑宽度（外边距+列间距近似处理）
                final double logicalTileWidth = (screenWidth - AppTheme.spacing1 * 3) / 2;
                final int targetWidth = (logicalTileWidth * MediaQuery.of(context).devicePixelRatio).round();
                final imageProvider = ResizeImage(FileImage(file), width: targetWidth);
                final imageWidget = Image(
                  image: imageProvider,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) {
                    print("图片加载失败: $error, path: ${file.path}");
                    return _buildErrorItem('图片丢失或损坏');
                  },
                );
                if (!isDark) return imageWidget;
                return ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.5),
                    BlendMode.darken,
                  ),
                  child: imageWidget,
                );
              },
            ),
          ),
          // 选择矩形“复选框”叠加（仅多选模式显示，右上角白色边框，浅灰底，选中打勾）
          if (_selectionMode)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isSelected ? Colors.black : Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
          // 去除之前的全图遮罩，仅保留底部信息遮罩
          // 底部信息遮罩
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing2,
                vertical: AppTheme.spacing1,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(AppTheme.radiusMd),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatFileSize(screenshot.fileSize),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.85)
                          : Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    _formatDateTime(screenshot.captureTime),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.85)
                          : Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return KeyedSubtree(key: itemKey, child: item);
  }

  // 构建右侧时间线滚动条与时间提示
  Widget _buildTimelineOverlay() {
    // 修复显示条件：只有在有数据且所有数据都加载完毕时才显示时间线
    if (_screenshots.isEmpty || _hasMore || _screenshots.length < 2) {
      return const SizedBox.shrink();
    }
    
    const double gestureWidth = 44; // 右侧可交互区域宽度
    const double trackWidth = 3; // 可见轨道宽度
    const double thumbHeight = 32; // 拇指高度
    const double labelHeight = 28; // 时间标签高度（用于定位）

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double viewHeight = constraints.maxHeight;
          // 与网格保持一致的底部边距：外层 Padding + GridView 的 bottom padding
          final double bottomMargin = MediaQuery.of(context).padding.bottom + AppTheme.spacing6 + AppTheme.spacing1;
          final double trackHeight = (viewHeight - bottomMargin).clamp(0, viewHeight);
          
          // 增加安全检查，避免异常计算
          if (trackHeight <= 0 || !_scrollController.hasClients) {
            return const SizedBox.shrink();
          }
          
          final double currentFraction = _timelineActive ? _timelineFraction : _currentScrollFraction();
          final double clampedFraction = currentFraction.clamp(0.0, 1.0);
          final double thumbTop = clampedFraction * (trackHeight - thumbHeight).clamp(0, trackHeight);

          // 安全获取第一个可见索引
          final int firstVisibleIndex = _getFirstVisibleIndex();
          final String timeLabel = (firstVisibleIndex >= 0 && firstVisibleIndex < _screenshots.length)
              ? _formatTimelineTime(_screenshots[firstVisibleIndex].captureTime)
              : '';

          return Stack(
            children: [
              // 交互区域 - 只占右侧44像素，避免影响主要内容区域
              Positioned(
                right: 0,
                top: 0,
                bottom: bottomMargin,
                width: gestureWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  // 防止手势冲突，增加边界检查
                  onVerticalDragStart: (details) {
                    if (trackHeight > thumbHeight) {
                      _activateTimelineWithLocalY(details.localPosition.dy, trackHeight);
                    }
                  },
                  onVerticalDragUpdate: (details) {
                    if (trackHeight > thumbHeight && _timelineActive) {
                      _activateTimelineWithLocalY(details.localPosition.dy, trackHeight);
                    }
                  },
                  onVerticalDragEnd: (_) {
                    if (mounted) {
                      setState(() {
                        _timelineActive = false;
                      });
                    }
                  },
                  onLongPressStart: (details) {
                    if (trackHeight > thumbHeight) {
                      _activateTimelineWithLocalY(details.localPosition.dy, trackHeight);
                    }
                  },
                  onLongPressMoveUpdate: (details) {
                    if (trackHeight > thumbHeight && _timelineActive) {
                      _activateTimelineWithLocalY(details.localPosition.dy, trackHeight);
                    }
                  },
                  onLongPressEnd: (_) {
                    if (mounted) {
                      setState(() {
                        _timelineActive = false;
                      });
                    }
                  },
                  child: Stack(
                    children: [
                      // 轨道
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: trackWidth,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // 拇指（与轨道右对齐）
                      Positioned(
                        right: 0,
                        top: thumbTop,
                        child: Container(
                          width: trackWidth,
                          height: thumbHeight,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade600,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_timelineActive)
                Positioned(
                  right: gestureWidth + 8,
                  top: (clampedFraction * (trackHeight - labelHeight)).clamp(0, trackHeight - labelHeight),
                  child: Container(
                    height: labelHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6), // 小圆角，无阴影
                      border: Border.all(color: Theme.of(context).dividerColor, width: 1),
                    ),
                    child: Text(
                      timeLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // 激活时间线并根据手指位置滚动
  void _activateTimelineWithLocalY(double localY, double viewHeight) {
    // 增加安全检查
    if (viewHeight <= 0 || !_scrollController.hasClients || !mounted) return;
    
    final double raw = localY / viewHeight;
    final double fraction = raw.clamp(0.0, 1.0);
    
    setState(() {
      _timelineActive = true;
      _timelineFraction = fraction;
    });
    _scrollToFraction(fraction);
  }

  // 当前滚动位置归一化 [0,1]
  double _currentScrollFraction() {
    if (!_scrollController.hasClients) return 0.0;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) return 0.0;
    final pixels = _scrollController.position.pixels;
    final double f = pixels / maxExtent;
    return f.clamp(0.0, 1.0);
  }

  // 滚动到对应归一化位置
  void _scrollToFraction(double fraction) {
    if (!_scrollController.hasClients || !mounted) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    final target = fraction.clamp(0.0, 1.0) * maxExtent;
    _scrollController.jumpTo(target);
  }

  // 获取网格视口矩形（全局坐标）
  Rect? _getGridViewportRect() {
    if (!mounted) return null;
    final ctx = _gridKey.currentContext;
    if (ctx == null) return null;
    final render = ctx.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    final topLeft = render.localToGlobal(Offset.zero);
    return topLeft & render.size;
  }

  // 计算当前视口内第一张可见截图的索引
  int _getFirstVisibleIndex() {
    if (!mounted || _screenshots.isEmpty || _itemKeys.isEmpty) return 0;
    
    final viewport = _getGridViewportRect();
    if (viewport == null) return 0;
    
    int? firstIdx;
    double? minTop;
    
    _itemKeys.forEach((index, key) {
      // 增加边界检查
      if (index >= _screenshots.length) return;
      
      final context = key.currentContext;
      if (context == null) return;
      
      final render = context.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      
      try {
        final rect = render.localToGlobal(Offset.zero) & render.size;
        final bool visible = rect.bottom > viewport.top && rect.top < viewport.bottom;
        if (!visible) return;
        
        if (minTop == null || rect.top < minTop!) {
          minTop = rect.top;
          firstIdx = index;
        }
      } catch (e) {
        // 忽略布局异常，继续处理其他项
        return;
      }
    });
    
    return (firstIdx != null && firstIdx! < _screenshots.length) ? firstIdx! : 0;
  }

  // 时间线标签格式化（当天/本年/跨年）
  String _formatTimelineTime(DateTime dateTime) {
    final now = DateTime.now();
    final bool sameDay = now.year == dateTime.year && now.month == dateTime.month && now.day == dateTime.day;
    final bool sameYear = now.year == dateTime.year;
    String hh = dateTime.hour.toString().padLeft(2, '0');
    String mm = dateTime.minute.toString().padLeft(2, '0');
    if (sameDay) {
      return '$hh:$mm';
    } else if (sameYear) {
      return '${dateTime.month}月${dateTime.day}日 $hh:$mm';
    } else {
      return '${dateTime.year}年${dateTime.month}月${dateTime.day}日 $hh:$mm';
    }
  }

  void _toggleSelect(int index) {
    if (index < 0 || index >= _screenshots.length) return;
    final id = _screenshots[index].id;
    if (id == null) return;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _hitSelectAtPosition(Offset globalPosition) {
    // 命中检测：遍历可见项，若指针在其区域内则选中
    _itemKeys.forEach((index, key) {
      final context = key.currentContext;
      if (context == null) return;
      final render = context.findRenderObject();
      if (render is! RenderBox) return;
      final topLeft = render.localToGlobal(Offset.zero);
      final rect = topLeft & render.size;
      if (rect.contains(globalPosition)) {
        _toggleSelect(index);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await showUIDialog<bool>(
      context: context,
      title: '确认删除',
      message: '将删除选中的 ${_selectedIds.length} 张截图，且不可恢复。是否继续？',
      actions: const [
        UIDialogAction<bool>(text: '取消', result: false),
        UIDialogAction<bool>(text: '删除', style: UIDialogActionStyle.destructive, result: true),
      ],
      barrierDismissible: false,
    );

    if (confirmed != true) return;

    int successCount = 0;
    final ids = List<int>.from(_selectedIds);
    for (final id in ids) {
      final ok = await ScreenshotService.instance.deleteScreenshot(id);
      if (ok) successCount++;
    }

    // 本地移除（从全量数据和显示数据中删除）
    setState(() {
      _allScreenshots.removeWhere((s) => s.id != null && _selectedIds.contains(s.id));
      _screenshots.removeWhere((s) => s.id != null && _selectedIds.contains(s.id));
      // 更新统计信息
      _totalCount = _allScreenshots.length;
      _totalSize = _allScreenshots.fold<int>(0, (sum, r) => sum + r.fileSize);
      if (_allScreenshots.isNotEmpty) {
        final latest = _allScreenshots.reduce((a, b) =>
          a.captureTime.isAfter(b.captureTime) ? a : b);
        _latestTime = latest.captureTime;
      } else {
        _latestTime = null;
      }
      _currentDisplayCount = _screenshots.length;
      _hasMore = _currentDisplayCount < _allScreenshots.length;
      _selectedIds.clear();
      _selectionMode = false;
    });

    // 失效统计缓存并提示
    await ScreenshotService.instance.invalidateStatsCache();
    // 失效截图列表缓存
    await _invalidateScreenshotsCache();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除 $successCount 张截图'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildErrorItem(String message) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.muted,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.destructive, size: 32),
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(color: AppTheme.destructive, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    
    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }

  /// 将字节格式化为最小MB，然后GB/TB
  String _formatTotalSizeMBGBTB(int bytes) {
    const double kb = 1024;
    const double mb = kb * 1024;
    const double gb = mb * 1024;
    const double tb = gb * 1024;

    if (bytes >= tb) {
      return (bytes / tb).toStringAsFixed(2) + 'TB';
    } else if (bytes >= gb) {
      return (bytes / gb).toStringAsFixed(2) + 'GB';
    } else {
      // 最小单位MB（包含 <1MB 的情况）
      return (bytes / mb).toStringAsFixed(2) + 'MB';
    }
  }
}
