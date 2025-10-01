import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/favorite_record.dart';
import '../models/screenshot_record.dart';
import '../models/app_info.dart';
import '../services/favorite_service.dart';
import '../services/screenshot_database.dart';
import '../services/path_service.dart';
import '../services/app_selection_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_dialog.dart';
import '../widgets/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../widgets/screenshot_item_widget.dart';
import '../widgets/screenshot_image_widget.dart';

/// 收藏页面
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> with AutomaticKeepAliveClientMixin {
  final List<_FavoriteItem> _favorites = [];
  bool _isLoading = true;
  String? _error;
  Directory? _baseDir;
  final Map<String, AppInfo?> _appInfoCache = {}; // 缓存应用信息
  bool _privacyMode = true; // 隐私模式
  StreamSubscription<FavoriteChangeEvent>? _favoriteChangeSub;
  
  @override
  bool get wantKeepAlive => true;
  
  @override
  void initState() {
    super.initState();
    _loadData();
    _loadPrivacyMode();
    // 监听隐私模式变更
    AppSelectionService.instance.onPrivacyModeChanged.listen((enabled) {
      if (!mounted) return;
      setState(() { _privacyMode = enabled; });
    });
    // 监听收藏变更事件
    _favoriteChangeSub = FavoriteService.instance.onFavoriteChanged.listen((event) {
      if (!mounted) return;
      // 收藏变更时刷新列表
      _loadData();
    });
  }
  
  @override
  void dispose() {
    _favoriteChangeSub?.cancel();
    super.dispose();
  }
  
  Future<void> _loadPrivacyMode() async {
    try {
      final enabled = await AppSelectionService.instance.getPrivacyModeEnabled();
      if (mounted) setState(() { _privacyMode = enabled; });
    } catch (_) {}
  }
  
  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      
      // 获取基础目录
      final dir = await PathService.getExternalFilesDir(null);
      if (dir == null) {
        throw Exception(AppLocalizations.of(context).cannotGetAppDir);
      }
      
      _baseDir = dir;
      
      // 获取所有收藏
      final favList = await ScreenshotDatabase.instance.getAllFavorites();
      final List<_FavoriteItem> items = [];
      
      // 获取所有应用信息
      final allApps = await AppSelectionService.instance.getAllInstalledApps();
      for (final app in allApps) {
        _appInfoCache[app.packageName] = app;
      }
      
      for (final favMap in favList) {
        final screenshotId = favMap['screenshot_id'] as int;
        final appPackageName = favMap['app_package_name'] as String;
        
        try {
          // 获取截图记录（需要解码全局ID并从对应分库获取）
          final screenshot = await _getScreenshotById(screenshotId, appPackageName);
          if (screenshot != null) {
            items.add(_FavoriteItem(
              favorite: FavoriteRecord.fromMap(favMap),
              screenshot: screenshot,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(
                (favMap['updated_at'] as int?) ?? (favMap['created_at'] as int?) ?? favMap['favorite_time'] as int
              ),
              appInfo: _appInfoCache[appPackageName],
            ));
          }
        } catch (e) {
          print('获取截图失败 id=$screenshotId: $e');
        }
      }
      
      setState(() {
        _favorites
          ..clear()
          ..addAll(items);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = '${AppLocalizations.of(context).loadMoreFailedWithError(e.toString())}';
        _isLoading = false;
      });
    }
  }
  
  /// 根据全局ID和包名获取截图记录
  Future<ScreenshotRecord?> _getScreenshotById(int gid, String packageName) async {
    try {
      // 使用现有的getScreenshotsByApp方法，然后过滤出匹配的ID
      final screenshots = await ScreenshotDatabase.instance.getScreenshotsByApp(
        packageName,
        limit: 500, // 获取足够多的记录以找到目标截图
        offset: 0,
      );
      
      for (final s in screenshots) {
        if (s.id == gid) {
          return s;
        }
      }
      
      return null;
    } catch (e) {
      print('通过ID获取截图失败: $e');
      return null;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 36,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Text('${AppLocalizations.of(context).favoritePageTitle} (${_favorites.length})'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: AppLocalizations.of(context).actionRefresh,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
  
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.destructive),
            const SizedBox(height: AppTheme.spacing4),
            Text(_error!, style: const TextStyle(color: AppTheme.destructive)),
            const SizedBox(height: AppTheme.spacing4),
            UIButton(
              text: AppLocalizations.of(context).actionRetry,
              onPressed: _loadData,
              variant: UIButtonVariant.outline,
            ),
          ],
        ),
      );
    }
    
    if (_favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.favorite_outline,
                size: 64,
                color: AppTheme.mutedForeground.withOpacity(0.5),
              ),
              const SizedBox(height: AppTheme.spacing4),
              Text(
                AppLocalizations.of(context).noFavoritesTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.mutedForeground,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacing2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  AppLocalizations.of(context).noFavoritesSubtitle,
                  style: const TextStyle(color: AppTheme.mutedForeground),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return ListView.builder(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.only(
          left: AppTheme.spacing2,
          right: AppTheme.spacing2,
          top: AppTheme.spacing2,
          bottom: MediaQuery.of(context).padding.bottom + AppTheme.spacing6,
        ),
        itemCount: _favorites.length,
        itemBuilder: (context, index) => _FavoriteItemWidget(
          key: ValueKey(_favorites[index].favorite.id ?? index),
          item: _favorites[index],
          index: index,
          baseDir: _baseDir!,
          privacyMode: _privacyMode,
          onRemove: (item) {
            setState(() {
              _favorites.remove(item);
            });
          },
          onUpdate: (item, newNote) {
            setState(() {
              final idx = _favorites.indexOf(item);
              if (idx >= 0) {
                _favorites[idx] = _FavoriteItem(
                  favorite: item.favorite.copyWith(note: newNote),
                  screenshot: item.screenshot,
                  updatedAt: DateTime.now(),
                  appInfo: item.appInfo,
                );
              }
            });
          },
        ),
      );
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
            Text(message, style: const TextStyle(color: AppTheme.destructive, fontSize: 12)),
          ],
        ),
      ),
    );
  }
  
  /// 紧凑格式时间显示
  String _formatCompactTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    
    if (diff.inMinutes < 1) {
      return AppLocalizations.of(context).justNow;
    } else if (diff.inHours < 1) {
      return AppLocalizations.of(context).minutesAgo(diff.inMinutes.toString());
    } else if (diff.inHours < 24) {
      return AppLocalizations.of(context).hoursAgo(diff.inHours.toString());
    } else if (diff.inDays < 7) {
      return AppLocalizations.of(context).daysAgo(diff.inDays.toString());
    } else {
      final hh = dateTime.hour.toString().padLeft(2, '0');
      final mm = dateTime.minute.toString().padLeft(2, '0');
      return '${dateTime.month}/${dateTime.day} $hh:$mm';
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
}

/// 单个收藏项 Widget（独立状态管理）
class _FavoriteItemWidget extends StatefulWidget {
  final _FavoriteItem item;
  final int index;
  final Directory baseDir;
  final bool privacyMode;
  final Function(_FavoriteItem) onRemove;
  final Function(_FavoriteItem, String?) onUpdate;
  
  const _FavoriteItemWidget({
    super.key,
    required this.item,
    required this.index,
    required this.baseDir,
    required this.privacyMode,
    required this.onRemove,
    required this.onUpdate,
  });
  
  @override
  State<_FavoriteItemWidget> createState() => _FavoriteItemWidgetState();
}

class _FavoriteItemWidgetState extends State<_FavoriteItemWidget> {
  late TextEditingController _noteController;
  late FocusNode _noteFocusNode;
  
  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.item.favorite.note ?? '');
    _noteFocusNode = FocusNode();
  }
  
  @override
  void dispose() {
    _noteController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }
  
  /// 主动保存备注
  Future<void> _saveNote() async {
    final oldNote = widget.item.favorite.note ?? '';
    final newNote = _noteController.text.trim();
    
    // 如果内容没有变化，提示无需保存
    if (oldNote == newNote) {
      if (mounted) {
        UINotifier.info(context, AppLocalizations.of(context).noteUnchanged);
      }
      return;
    }
    
    if (widget.item.screenshot.id == null) return;
    
    // 取消焦点，收起键盘
    FocusScope.of(context).unfocus();
    
    try {
      final success = await FavoriteService.instance.updateNote(
        screenshotId: widget.item.screenshot.id!,
        appPackageName: widget.item.screenshot.appPackageName,
        note: newNote.isEmpty ? null : newNote,
      );
      
      if (success && mounted) {
        widget.onUpdate(widget.item, newNote.isEmpty ? null : newNote);
        UINotifier.success(context, AppLocalizations.of(context).noteSaved);
      } else if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).saveFailedError(''));
      }
    } catch (e) {
      print('保存备注失败: $e');
      if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
      }
    }
  }
  
  /// 直接取消收藏
  Future<void> _removeFavoriteDirectly() async {
    if (widget.item.screenshot.id == null) return;
    
    final success = await FavoriteService.instance.removeFavorite(
      screenshotId: widget.item.screenshot.id!,
      appPackageName: widget.item.screenshot.appPackageName,
    );
    
    if (success) {
      widget.onRemove(widget.item);
      if (mounted) {
        UINotifier.success(context, AppLocalizations.of(context).favoritesRemoved);
      }
    } else if (mounted) {
      UINotifier.error(context, AppLocalizations.of(context).operationFailed);
    }
  }
  
  void _viewScreenshot() {
    // 打开查看器前收起键盘，避免返回时键盘误弹
    FocusScope.of(context).unfocus();
    Navigator.pushNamed(
      context,
      '/screenshot_viewer',
      arguments: {
        'screenshots': [widget.item.screenshot],
        'initialIndex': 0,
        'appName': widget.item.appInfo?.appName ?? widget.item.screenshot.appName,
        'appInfo': widget.item.appInfo,
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final file = path.isAbsolute(widget.item.screenshot.filePath)
        ? File(widget.item.screenshot.filePath)
        : File(path.join(widget.baseDir.path, widget.item.screenshot.filePath));
    
    // 计算图片尺寸（与截图列表保持一致）
    final screenWidth = MediaQuery.of(context).size.width;
    final gridPadding = AppTheme.spacing1 * 2;
    final crossAxisSpacing = AppTheme.spacing1;
    final columnWidth = (screenWidth - gridPadding - crossAxisSpacing) / 2;
    final columnHeight = columnWidth / 0.45;
    final imageWidth = columnWidth;
    final imageHeight = columnHeight;
    
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：图片（使用统一的图片组件）
          SizedBox(
            width: imageWidth,
            height: imageHeight,
            child: Stack(
              children: [
                ScreenshotImageWidget(
                  file: file,
                  privacyMode: widget.privacyMode,
                  pageUrl: widget.item.screenshot.pageUrl,
                  width: imageWidth,
                  height: imageHeight,
                  fit: BoxFit.cover,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppTheme.radiusMd),
                    bottomLeft: Radius.circular(AppTheme.radiusMd),
                  ),
                  onTap: _viewScreenshot,
                  errorText: 'Image Error',
                ),
                // 收藏图标（左上角，点击直接取消收藏）
                Positioned(
                  top: 6,
                  left: 6,
                  child: GestureDetector(
                    onTap: _removeFavoriteDirectly,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.red,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                // 收藏时间（右上角）
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Text(
                      _formatCompactTime(widget.item.favorite.favoriteTime),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 右侧：备注区域（高度跟随图片）
          Expanded(
            child: Container(
              height: imageHeight,
              padding: const EdgeInsets.all(AppTheme.spacing3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 备注标题、更新时间和保存按钮
                  Row(
                    children: [
                      Text(
                        AppLocalizations.of(context).noteLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.mutedForeground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacing2),
                      Expanded(
                        child: Text(
                          widget.item.favorite.note != null && widget.item.favorite.note!.isNotEmpty
                              ? '${AppLocalizations.of(context).updatedAt}${_formatCompactTime(widget.item.updatedAt)}'
                              : '',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: AppTheme.mutedForeground.withOpacity(0.7),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 保存按钮
                      InkWell(
                        onTap: _saveNote,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.save_outlined,
                            size: 18,
                            color: AppTheme.mutedForeground.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacing1),
                  // 备注输入框（无边框，点击即可编辑，不限制文字数量）
                  Expanded(
                    child: TextField(
                      controller: _noteController,
                      focusNode: _noteFocusNode,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).clickToAddNote,
                        hintStyle: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5),
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing1),
                  // 底部信息：应用图标、文件大小、截图时间
                  Row(
                    children: [
                      // 应用图标
                      if (widget.item.appInfo?.icon != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Image.memory(
                            widget.item.appInfo!.icon!,
                            width: 16,
                            height: 16,
                            fit: BoxFit.contain,
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.android, size: 16, color: AppTheme.mutedForeground),
                        ),
                      // 文件大小
                      Text(
                        _formatFileSize(widget.item.screenshot.fileSize),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: AppTheme.mutedForeground.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 截图时间
                      Text(
                        _formatCompactTime(widget.item.screenshot.captureTime),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: AppTheme.mutedForeground.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 紧凑格式时间显示
  String _formatCompactTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    
    if (diff.inMinutes < 1) {
      return AppLocalizations.of(context).justNow;
    } else if (diff.inHours < 1) {
      return AppLocalizations.of(context).minutesAgo(diff.inMinutes.toString());
    } else if (diff.inHours < 24) {
      return AppLocalizations.of(context).hoursAgo(diff.inHours.toString());
    } else if (diff.inDays < 7) {
      return AppLocalizations.of(context).daysAgo(diff.inDays.toString());
    } else {
      final hh = dateTime.hour.toString().padLeft(2, '0');
      final mm = dateTime.minute.toString().padLeft(2, '0');
      return '${dateTime.month}/${dateTime.day} $hh:$mm';
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
}

/// 收藏项数据结构
class _FavoriteItem {
  final FavoriteRecord favorite;
  final ScreenshotRecord screenshot;
  final DateTime updatedAt;
  final AppInfo? appInfo;
  
  const _FavoriteItem({
    required this.favorite,
    required this.screenshot,
    required this.updatedAt,
    this.appInfo,
  });
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _FavoriteItem &&
        other.favorite == favorite &&
        other.screenshot == screenshot &&
        other.updatedAt == updatedAt &&
        other.appInfo == appInfo;
  }
  
  @override
  int get hashCode => favorite.hashCode ^ screenshot.hashCode ^ updatedAt.hashCode ^ (appInfo?.hashCode ?? 0);
}
