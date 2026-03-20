import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/favorite_record.dart';
import '../models/screenshot_record.dart';
import '../models/app_info.dart';
import '../services/favorite_service.dart';
import '../services/screenshot_database.dart';
import '../services/screenshot_service.dart';
import '../services/path_service.dart';
import '../services/app_selection_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../widgets/screenshot_image_widget.dart';

/// 收藏页面
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with AutomaticKeepAliveClientMixin {
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
      setState(() {
        _privacyMode = enabled;
      });
    });
    // 监听收藏变更事件
    _favoriteChangeSub = FavoriteService.instance.onFavoriteChanged.listen((
      event,
    ) {
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
      final enabled = await AppSelectionService.instance
          .getPrivacyModeEnabled();
      if (mounted) {
        setState(() {
          _privacyMode = enabled;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    try {
      final cannotGetAppDir = AppLocalizations.of(context).cannotGetAppDir;
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // 获取基础目录
      final dir = await PathService.getInternalAppDir(null);
      if (dir == null) {
        throw Exception(cannotGetAppDir);
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
          // 优先：通过全局ID(gid)精确获取
          final screenshot = await ScreenshotService.instance.getScreenshotById(
            screenshotId,
            appPackageName,
          );
          if (screenshot != null) {
            items.add(
              _FavoriteItem(
                favorite: FavoriteRecord.fromMap(favMap),
                screenshot: screenshot,
                updatedAt: DateTime.fromMillisecondsSinceEpoch(
                  (favMap['updated_at'] as int?) ??
                      (favMap['created_at'] as int?) ??
                      favMap['favorite_time'] as int,
                ),
                appInfo: _appInfoCache[appPackageName],
              ),
            );
            continue;
          }
          // 兜底：旧逻辑按应用分页查找（防止少量边缘数据）
          final screenshots = await ScreenshotService.instance
              .getScreenshotsByApp(appPackageName, limit: 800, offset: 0);
          for (final s in screenshots) {
            if (s.id == screenshotId) {
              items.add(
                _FavoriteItem(
                  favorite: FavoriteRecord.fromMap(favMap),
                  screenshot: s,
                  updatedAt: DateTime.fromMillisecondsSinceEpoch(
                    (favMap['updated_at'] as int?) ??
                        (favMap['created_at'] as int?) ??
                        favMap['favorite_time'] as int,
                  ),
                  appInfo: _appInfoCache[appPackageName],
                ),
              );
              break;
            }
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
        _error = AppLocalizations.of(
          context,
        ).loadMoreFailedWithError(e.toString());
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
        toolbarHeight: 48,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          '${AppLocalizations.of(context).favoritePageTitle} (${_favorites.length})',
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
      return const UILoadingState(compact: true);
    }

    if (_error != null) {
      return UIErrorState(
        title: AppLocalizations.of(context).operationFailed,
        message: _error!,
        actionLabel: AppLocalizations.of(context).actionRetry,
        onAction: _loadData,
      );
    }

    if (_favorites.isEmpty) {
      return UIEmptyState(
        icon: Icons.favorite_outline,
        title: AppLocalizations.of(context).noFavoritesTitle,
        message: AppLocalizations.of(context).noFavoritesSubtitle,
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
    _noteController = TextEditingController(
      text: widget.item.favorite.note ?? '',
    );
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
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(''),
        );
      }
    } catch (e) {
      print('保存备注失败: $e');
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
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
        UINotifier.success(
          context,
          AppLocalizations.of(context).favoritesRemoved,
        );
      }
    } else {
      // 二次校验：若库中已无该收藏，也按成功处理，避免误报
      bool stillFavorite = true;
      try {
        stillFavorite = await FavoriteService.instance.isFavorite(
          screenshotId: widget.item.screenshot.id!,
          appPackageName: widget.item.screenshot.appPackageName,
        );
      } catch (_) {}

      if (!stillFavorite) {
        widget.onRemove(widget.item);
        if (mounted) {
          UINotifier.success(
            context,
            AppLocalizations.of(context).favoritesRemoved,
          );
        }
      } else if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      }
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
        'appName':
            widget.item.appInfo?.appName ?? widget.item.screenshot.appName,
        'appInfo': widget.item.appInfo,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final file = path.isAbsolute(widget.item.screenshot.filePath)
        ? File(widget.item.screenshot.filePath)
        : File(path.join(widget.baseDir.path, widget.item.screenshot.filePath));
    final bool compactLayout = MediaQuery.of(context).size.width < 720;
    final Color overlayForeground = const Color(0xFFF6EEDF);
    final Color overlaySurface = theme.brightness == Brightness.dark
        ? const Color(0xA8141413)
        : const Color(0xB8191816);
    final Color overlayBorder = AppTheme.border.withValues(alpha: 0.28);

    final screenWidth = MediaQuery.of(context).size.width;
    final gridPadding = AppTheme.spacing1 * 2;
    final crossAxisSpacing = AppTheme.spacing1;
    final columnWidth = (screenWidth - gridPadding - crossAxisSpacing) / 2;
    final columnHeight = columnWidth / 0.45;
    final imageWidth = compactLayout ? screenWidth : columnWidth;
    final imageHeight = compactLayout ? screenWidth * 0.62 : columnHeight;

    Widget buildImageSection(BorderRadius borderRadius) {
      return SizedBox(
        width: compactLayout ? double.infinity : imageWidth,
        height: imageHeight,
        child: Stack(
          children: [
            ScreenshotImageWidget(
              file: file,
              privacyMode: widget.privacyMode,
              screenshot: widget.item.screenshot,
              width: compactLayout ? screenWidth : imageWidth,
              height: imageHeight,
              fit: BoxFit.cover,
              borderRadius: borderRadius,
              onTap: _viewScreenshot,
              errorText: 'Image Error',
              showTimelineJumpButton: true,
            ),
            Positioned(
              top: 8,
              left: 8,
              child: GestureDetector(
                onTap: _removeFavoriteDirectly,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: overlaySurface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: overlayBorder, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.favorite_rounded,
                    color: overlayForeground,
                    size: 18,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing2,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: overlaySurface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(color: overlayBorder, width: 1),
                ),
                child: Text(
                  _formatCompactTime(widget.item.favorite.favoriteTime),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: overlayForeground,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildAppMeta() {
      return Wrap(
        spacing: AppTheme.spacing2,
        runSpacing: AppTheme.spacing1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (widget.item.appInfo?.icon != null)
            Image.memory(
              widget.item.appInfo!.icon!,
              width: 16,
              height: 16,
              fit: BoxFit.contain,
            )
          else
            const Icon(
              Icons.android,
              size: 16,
              color: AppTheme.mutedForeground,
            ),
          Text(
            _formatFileSize(widget.item.screenshot.fileSize),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: cs.onSurfaceVariant.withValues(alpha: 0.78),
            ),
          ),
          Text(
            _formatCompactTime(widget.item.screenshot.captureTime),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: cs.onSurfaceVariant.withValues(alpha: 0.78),
            ),
          ),
        ],
      );
    }

    Widget buildNoteSection() {
      final Widget noteField = Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing3,
          vertical: AppTheme.spacing3,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: cs.outlineVariant, width: 1),
        ),
        child: TextField(
          controller: _noteController,
          focusNode: _noteFocusNode,
          minLines: compactLayout ? 6 : null,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context).clickToAddNote,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 14,
              height: 1.55,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            color: cs.onSurface,
            height: 1.6,
          ),
        ),
      );

      return Container(
        padding: const EdgeInsets.all(AppTheme.spacing4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  AppLocalizations.of(context).noteLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppTheme.spacing2),
                Expanded(
                  child: Text(
                    widget.item.favorite.note != null &&
                            widget.item.favorite.note!.isNotEmpty
                        ? '${AppLocalizations.of(context).updatedAt}${_formatCompactTime(widget.item.updatedAt)}'
                        : '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.82),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Material(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  child: InkWell(
                    onTap: _saveNote,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.save_outlined,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing3),
            if (compactLayout) noteField else Expanded(child: noteField),
            const SizedBox(height: AppTheme.spacing3),
            buildAppMeta(),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      child: compactLayout
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildImageSection(
                  const BorderRadius.only(
                    topLeft: Radius.circular(AppTheme.radiusLg),
                    topRight: Radius.circular(AppTheme.radiusLg),
                  ),
                ),
                buildNoteSection(),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildImageSection(
                  const BorderRadius.only(
                    topLeft: Radius.circular(AppTheme.radiusLg),
                    bottomLeft: Radius.circular(AppTheme.radiusLg),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: imageHeight,
                    child: buildNoteSection(),
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
  int get hashCode =>
      favorite.hashCode ^
      screenshot.hashCode ^
      updatedAt.hashCode ^
      (appInfo?.hashCode ?? 0);
}
