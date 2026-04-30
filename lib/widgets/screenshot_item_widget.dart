import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/screenshot_record.dart';
import '../models/app_info.dart';
import '../l10n/app_localizations.dart';
import '../services/screenshot_database.dart';
import '../theme/app_theme.dart';
import 'ai_meta_sheet.dart';
import 'nsfw_guard.dart';
import '../services/nsfw_preference_service.dart';
import 'timeline_jump_overlay.dart';
import 'selection_checkbox.dart';

/// AI 元数据徽标（可点击打开 AiMetaSheet）的显示位置。
enum AiMetaBadgePlacement {
  /// 显示在底部信息遮罩内（默认）。
  bottomOverlay,

  /// 显示在右上角（更适合窄缩略图/三列网格）。
  topRight,
}

/// 截图项组件 - 统一的截图显示样式
///
/// 功能包括：
/// - 显示应用logo
/// - 图片大小
/// - 时间
/// - 点击显示
/// - 隐私模式（NSFW遮罩）
/// - 深色模式支持
/// - 深度链接显示
class ScreenshotItemWidget extends StatelessWidget {
  static final Map<String, int> _lazyFileSizeCache = <String, int>{};
  static final Map<String, Future<int>> _lazyFileSizeFutures =
      <String, Future<int>>{};

  /// 截图记录
  final ScreenshotRecord screenshot;

  /// 基础目录（用于解析相对路径）
  final Directory? baseDir;

  /// 应用信息映射（用于获取应用图标）
  final Map<String, AppInfo>? appInfoMap;

  /// 是否启用隐私模式
  final bool privacyMode;

  /// 点击回调
  final VoidCallback? onTap;

  /// 长按回调
  final VoidCallback? onLongPress;

  /// 链接点击回调
  final void Function(String url)? onLinkTap;

  /// 是否显示选择框
  final bool showCheckbox;

  /// 是否选中
  final bool isSelected;

  /// 是否显示收藏按钮
  final bool showFavoriteButton;

  /// 是否已收藏
  final bool isFavorited;

  /// 收藏按钮点击回调
  final VoidCallback? onFavoriteToggle;

  /// 是否显示 NSFW 按钮（与收藏并列）
  final bool showNsfwButton;

  /// 是否已手动标记为 NSFW（用于按钮图标状态）
  final bool isNsfwFlagged;

  /// NSFW 按钮点击回调（切换标记）
  final VoidCallback? onNsfwToggle;

  /// 自定义叠加层（如 OCR 标注）
  final Widget? customOverlay;

  /// 是否显示“时间线跳转”按钮（默认关闭）
  final bool showTimelineJumpButton;

  /// AI 元数据徽标显示位置（默认在底部遮罩内）。
  final AiMetaBadgePlacement aiMetaBadgePlacement;

  const ScreenshotItemWidget({
    super.key,
    required this.screenshot,
    this.baseDir,
    this.appInfoMap,
    this.privacyMode = true,
    this.onTap,
    this.onLongPress,
    this.onLinkTap,
    this.showCheckbox = false,
    this.isSelected = false,
    this.showFavoriteButton = false,
    this.isFavorited = false,
    this.onFavoriteToggle,
    this.showNsfwButton = false,
    this.isNsfwFlagged = false,
    this.onNsfwToggle,
    this.customOverlay,
    this.showTimelineJumpButton = false,
    this.aiMetaBadgePlacement = AiMetaBadgePlacement.bottomOverlay,
  });

  @override
  Widget build(BuildContext context) {
    final file = _resolveFile();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool nsfwMasked =
        privacyMode &&
        NsfwPreferenceService.instance.shouldMaskCached(screenshot);

    final List<Widget> layers = <Widget>[_buildImage(context, file, isDark)];

    final bool hasAiMeta = NsfwPreferenceService.instance.hasAiMetaCached(
      filePath: screenshot.filePath,
    );

    if (customOverlay != null) layers.add(customOverlay!);

    if (nsfwMasked) {
      layers.add(
        Positioned.fill(
          child: NsfwBackdropOverlay(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            onReveal: onTap,
            showButton: true,
          ),
        ),
      );
    }

    if (!nsfwMasked &&
        screenshot.pageUrl != null &&
        screenshot.pageUrl!.isNotEmpty) {
      layers.add(_buildLinkOverlay(context));
    }

    layers.add(
      _buildBottomOverlay(
        context,
        showAiMetaBadge:
            hasAiMeta &&
            aiMetaBadgePlacement == AiMetaBadgePlacement.bottomOverlay,
      ),
    );

    if (hasAiMeta && aiMetaBadgePlacement == AiMetaBadgePlacement.topRight) {
      layers.add(_buildTopRightAiMetaBadge(context));
    }

    if (showCheckbox) layers.add(_buildCheckbox(context));
    if (showFavoriteButton) layers.add(_buildFavoriteButton(context));
    if (showNsfwButton) layers.add(_buildNsfwButton(context));

    if (showTimelineJumpButton) {
      layers.add(TimelineJumpOverlay(filePath: _resolveFile().path));
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(children: layers),
    );
  }

  /// 解析文件路径
  File _resolveFile() {
    if (path.isAbsolute(screenshot.filePath)) {
      return File(screenshot.filePath);
    }
    if (baseDir != null) {
      return File(path.join(baseDir!.path, screenshot.filePath));
    }
    return File(screenshot.filePath);
  }

  /// 构建图片
  Widget _buildImage(BuildContext context, File file, bool isDark) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double logicalTileWidth = (screenWidth - AppTheme.spacing1 * 3) / 2;
    final int targetWidth =
        (logicalTileWidth * MediaQuery.of(context).devicePixelRatio).round();

    final imageProvider = ResizeImage(FileImage(file), width: targetWidth);

    final baseImage = Image(
      image: imageProvider,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => _buildErrorItem(context),
    );

    final image = ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: isDark
          ? ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.5),
                BlendMode.darken,
              ),
              child: baseImage,
            )
          : baseImage,
    );

    return image;
  }

  /// 构建顶部链接遮罩
  Widget _buildLinkOverlay(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onLinkTap != null ? () => onLinkTap!(screenshot.pageUrl!) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing2,
            vertical: AppTheme.spacing1,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [const Color(0xD9141413), Colors.transparent],
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusSm),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.link, size: 14, color: const Color(0xFFF6F1E8)),
              const SizedBox(width: AppTheme.spacing1),
              Expanded(
                child: Text(
                  screenshot.pageUrl!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: const Color(0xFFF6F1E8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建底部信息遮罩
  Widget _buildBottomOverlay(
    BuildContext context, {
    required bool showAiMetaBadge,
  }) {
    return _buildBottomOverlayImpl(
      context,
      _resolveFile(),
      showAiMetaBadge: showAiMetaBadge,
    );
  }

  Widget _buildBottomOverlayImpl(
    BuildContext context,
    File file, {
    required bool showAiMetaBadge,
  }) {
    final Color textColor = const Color(0xFFF6F1E8);
    final TextStyle infoStyle = TextStyle(
      fontSize: 11,
      color: textColor,
      fontWeight: FontWeight.w600,
    );

    return Positioned(
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
            colors: [Colors.transparent, const Color(0xD9141413)],
          ),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppTheme.radiusSm),
          ),
        ),
        child: Row(
          children: [
            // 应用图标
            _buildAppIcon(context),
            _buildFileSizeInfo(file, infoStyle),
            if (showAiMetaBadge) ...[
              const SizedBox(width: 6),
              _buildAiMetaBadge(context),
            ],
            const Spacer(),
            // 时间
            Text(_formatTime(screenshot.captureTime), style: infoStyle),
          ],
        ),
      ),
    );
  }

  Widget _buildTopRightAiMetaBadge(BuildContext context) {
    return Positioned(top: 6, right: 6, child: _buildAiMetaBadge(context));
  }

  Widget _buildFileSizeInfo(File file, TextStyle style) {
    final int bytes = screenshot.fileSize;
    if (bytes > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 6),
          Text(_formatFileSize(bytes), style: style),
        ],
      );
    }

    final String key = file.path;
    final int? cached = _lazyFileSizeCache[key];
    if (cached != null && cached > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 6),
          Text(_formatFileSize(cached), style: style),
        ],
      );
    }

    final Future<int> fut = _lazyFileSizeFutures.putIfAbsent(key, () async {
      try {
        if (!await file.exists()) return 0;
        final int v = await file.length();
        if (v > 0) {
          _lazyFileSizeCache[key] = v;
          final int? gid = screenshot.id;
          if (gid != null) {
            unawaited(
              ScreenshotDatabase.instance.updateFileSizeByGid(
                packageName: screenshot.appPackageName,
                gid: gid,
                newSize: v,
              ),
            );
          }
        }
        return v;
      } catch (_) {
        return 0;
      } finally {
        _lazyFileSizeFutures.remove(key);
      }
    });

    return FutureBuilder<int>(
      future: fut,
      builder: (context, snap) {
        final int v = (snap.data ?? 0);
        if (v <= 0) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 6),
            Text(_formatFileSize(v), style: style),
          ],
        );
      },
    );
  }

  Widget _buildAiMetaBadge(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => AiMetaSheet.show(
        context,
        filePath: screenshot.filePath,
        fallbackOcrText: screenshot.ocrText,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xB8141413),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.28),
            width: 1,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 12, color: Color(0xFFF6F1E8)),
            SizedBox(width: 4),
            Text(
              'AI',
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFFF6F1E8),
                height: 1.0,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建应用图标
  Widget _buildAppIcon(BuildContext context) {
    final app = appInfoMap?[screenshot.appPackageName];
    if (app != null && app.icon != null && app.icon!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          app.icon!,
          width: 18,
          height: 18,
          fit: BoxFit.cover,
        ),
      );
    }

    // 占位符
    final parts = screenshot.appPackageName.split('.');
    final head = parts.isNotEmpty ? parts.last : screenshot.appPackageName;
    final leading = head.isNotEmpty ? head[0].toUpperCase() : '?';
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: const Color(0xFFF0EDE6),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        leading,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF141413),
        ),
      ),
    );
  }

  /// 构建选择框
  Widget _buildCheckbox(BuildContext context) {
    return Positioned(
      top: 6,
      right: 6,
      child: SelectionCheckbox(selected: isSelected, size: 24, iconSize: 16),
    );
  }

  /// 构建收藏按钮
  Widget _buildFavoriteButton(BuildContext context) {
    return Positioned(
      top: 6,
      left: 6,
      child: GestureDetector(
        onTap: onFavoriteToggle,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xA8141413),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: AppTheme.border.withValues(alpha: 0.28),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            isFavorited ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: isFavorited ? AppTheme.destructive : const Color(0xFFF6F1E8),
          ),
        ),
      ),
    );
  }

  /// 构建 NSFW 按钮（与收藏并列，位于其右侧）
  Widget _buildNsfwButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 6,
      left: 44, // 6(边距) + 32(收藏按钮宽度) + 6(间距)
      child: GestureDetector(
        onTap: onNsfwToggle,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xA8141413),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: AppTheme.border.withValues(alpha: 0.28),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            isNsfwFlagged ? Icons.visibility_off : Icons.visibility,
            size: 18,
            color: isNsfwFlagged ? colorScheme.error : const Color(0xFFF6F1E8),
          ),
        ),
      ),
    );
  }

  /// 构建错误占位
  Widget _buildErrorItem(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.broken_image,
            size: 32,
            color: AppTheme.mutedForeground,
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).imageError,
            style: const TextStyle(
              color: AppTheme.mutedForeground,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// 格式化时间
  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }
}
