import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/screenshot_record.dart';
import '../services/nsfw_preference_service.dart';
import 'nsfw_guard.dart';
import 'timeline_jump_overlay.dart';

/// 统一的截图图片显示组件
///
/// 自动处理：
/// - 深色模式遮罩
/// - 隐私模式（NSFW）遮罩
/// - 图片加载和错误处理
///
/// 使用此组件可确保所有截图显示保持一致的样式和行为
class ScreenshotImageWidget extends StatelessWidget {
  /// 图片文件
  final File file;
  
  /// 是否启用隐私模式
  final bool privacyMode;
  
  /// 页面链接（用于判断是否为 NSFW）- 已废弃，使用 screenshot 参数
  final String? pageUrl;
  
  /// 截图记录（用于准确判断 NSFW）
  final ScreenshotRecord? screenshot;
  
  /// 图片宽度
  final double? width;
  
  /// 图片高度
  final double? height;
  
  /// 图片适配方式
  final BoxFit fit;
  
  /// 圆角
  final BorderRadius? borderRadius;
  
  /// 点击回调
  final VoidCallback? onTap;
  
  /// NSFW 显示回调（点击"显示"按钮时）
  final VoidCallback? onReveal;
  
  /// 是否显示 NSFW 的"显示"按钮
  final bool showNsfwButton;
  
  /// 目标缩略图宽度（用于性能优化）
  final int? targetWidth;
  
  /// 错误占位文本
  final String? errorText;

  /// 是否显示“时间线跳转”按钮（默认关闭）
  final bool showTimelineJumpButton;
  
  const ScreenshotImageWidget({
    super.key,
    required this.file,
    this.privacyMode = true,
    this.pageUrl,
    this.screenshot,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.onTap,
    this.onReveal,
    this.showNsfwButton = true,
    this.targetWidth,
    this.errorText,
    this.showTimelineJumpButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // 优先使用 screenshot 参数进行准确判断，否则回退到旧的 URL 判断方式
    final bool nsfwMasked = privacyMode &&
        (screenshot != null
            ? NsfwPreferenceService.instance.shouldMaskCached(screenshot!)
            : NsfwDetector.isNsfwUrl(pageUrl));
    
    Widget base = _buildImage(context, isDark);

    final List<Widget> layers = <Widget>[base];

    // NSFW 遮罩（位于图片之上）
    if (nsfwMasked) {
      layers.add(
        Positioned.fill(
          child: NsfwBackdropOverlay(
            borderRadius: borderRadius,
            onReveal: onReveal ?? onTap,
            showButton: showNsfwButton,
          ),
        ),
      );
    }

    // 时间线跳转按钮（位于最上层）
    if (showTimelineJumpButton) {
      layers.add(TimelineJumpOverlay(filePath: file.path));
    }

    Widget result = layers.length == 1 ? base : Stack(children: layers);

    // 添加点击手势（在未遮罩时允许点击）
    if (onTap != null && !nsfwMasked) {
      result = GestureDetector(onTap: onTap, child: result);
    }

    // 添加圆角裁剪
    if (borderRadius != null) {
      result = ClipRRect(borderRadius: borderRadius!, child: result);
    }

    return result;
  }
  
  /// 构建图片
  Widget _buildImage(BuildContext context, bool isDark) {
    final ImageProvider imageProvider = targetWidth != null
        ? ResizeImage(FileImage(file), width: targetWidth!)
        : FileImage(file);
    
    final baseImage = Image(
      image: imageProvider,
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => _buildErrorWidget(context),
    );
    
    // 深色模式下添加黑色遮罩
    if (isDark) {
      return ColorFiltered(
        colorFilter: ColorFilter.mode(
          Colors.black.withValues(alpha: 0.5),
          BlendMode.darken,
        ),
        child: baseImage,
      );
    }
    
    return baseImage;
  }
  
  /// 构建错误占位
  Widget _buildErrorWidget(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: borderRadius,
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
          if (errorText != null) ...[
            const SizedBox(height: 4),
            Text(
              errorText!,
              style: const TextStyle(
                color: AppTheme.mutedForeground,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

