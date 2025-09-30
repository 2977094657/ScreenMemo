import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  
  @override
  bool get wantKeepAlive => true;
  
  @override
  void initState() {
    super.initState();
    _loadData();
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
        throw Exception('无法获取应用目录');
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
        _error = '加载失败: $e';
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
        title: Center(
          child: Text(
            '收藏 (${_favorites.length})',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: '刷新',
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
              text: '重试',
              onPressed: _loadData,
              variant: UIButtonVariant.outline,
            ),
          ],
        ),
      );
    }
    
    if (_favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_outline,
              size: 64,
              color: AppTheme.mutedForeground.withOpacity(0.5),
            ),
            const SizedBox(height: AppTheme.spacing4),
            const Text(
              '暂无收藏',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppTheme.mutedForeground,
              ),
            ),
            const SizedBox(height: AppTheme.spacing2),
            const Text(
              '在截图列表长按图片进入多选模式后收藏',
              style: TextStyle(color: AppTheme.mutedForeground),
            ),
          ],
        ),
      );
    }
    
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // 点击空白区域时取消焦点，触发自动保存
        FocusScope.of(context).unfocus();
      },
      child: ListView.builder(
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
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
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
  final Function(_FavoriteItem) onRemove;
  final Function(_FavoriteItem, String?) onUpdate;
  
  const _FavoriteItemWidget({
    super.key,
    required this.item,
    required this.index,
    required this.baseDir,
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
    
    // 监听焦点失去事件，自动保存备注
    _noteFocusNode.addListener(() {
      if (!_noteFocusNode.hasFocus) {
        _saveNoteIfChanged();
      }
    });
  }
  
  @override
  void dispose() {
    _noteController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }
  
  /// 保存备注（如果有变化）
  Future<void> _saveNoteIfChanged() async {
    final oldNote = widget.item.favorite.note ?? '';
    final newNote = _noteController.text.trim();
    
    // 如果内容没有变化，不进行保存
    if (oldNote == newNote) return;
    
    if (widget.item.screenshot.id == null) return;
    
    try {
      final success = await FavoriteService.instance.updateNote(
        screenshotId: widget.item.screenshot.id!,
        appPackageName: widget.item.screenshot.appPackageName,
        note: newNote.isEmpty ? null : newNote,
      );
      
      if (success && mounted) {
        widget.onUpdate(widget.item, newNote.isEmpty ? null : newNote);
      }
    } catch (e) {
      print('保存备注失败: $e');
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
        UINotifier.success(context, '已取消收藏');
      }
    } else if (mounted) {
      UINotifier.error(context, '操作失败');
    }
  }
  
  void _viewScreenshot() {
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
          // 左侧：图片
          GestureDetector(
            onTap: _viewScreenshot,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppTheme.radiusMd),
                    bottomLeft: Radius.circular(AppTheme.radiusMd),
                  ),
                  child: Image.file(
                    file,
                    width: imageWidth,
                    height: imageHeight,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: imageWidth,
                        height: imageHeight,
                        color: AppTheme.muted,
                        child: const Center(
                          child: Icon(Icons.error_outline, color: AppTheme.destructive),
                        ),
                      );
                    },
                  ),
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
                  // 备注标题和更新时间
                  Row(
                    children: [
                      Text(
                        '备注',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.mutedForeground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacing2),
                      Expanded(
                        child: Text(
                          widget.item.favorite.note != null && widget.item.favorite.note!.isNotEmpty
                              ? '更新于 ${_formatCompactTime(widget.item.updatedAt)}'
                              : '',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: AppTheme.mutedForeground.withOpacity(0.7),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacing1),
                  // 备注输入框（无边框，点击即可编辑，不限制文字数量）
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // 点击时请求焦点，确保光标显示
                        if (!_noteFocusNode.hasFocus) {
                          _noteFocusNode.requestFocus();
                        }
                      },
                      child: TextField(
                        controller: _noteController,
                        focusNode: _noteFocusNode,
                        decoration: InputDecoration(
                          hintText: '点击添加备注...',
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
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
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
