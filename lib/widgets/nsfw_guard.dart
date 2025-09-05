import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../theme/app_theme.dart';

/// NSFW 链接检测工具
class NsfwDetector {
  NsfwDetector._();

  // 主要成人站点关键字（匹配 host 或完整链接中的片段）
  static final List<RegExp> _hostPatterns = <RegExp>[
    RegExp(
      r'(pornhub|xvideos|xhamster|xnxx|redtube|youporn|spankbang|rule34|e-?hentai|nhentai|javbus|javdb|tnaflix|tube8|youjizz|erome|hentais?|onlyfans|chaturbate)',
      caseSensitive: false,
    ),
  ];

  /// 判断链接是否可能为成人内容站点
  static bool isNsfwUrl(String? url) {
    if (url == null) return false;
    final String trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    try {
      final uri = Uri.parse(trimmed);
      final host = uri.host.toLowerCase();
      for (final re in _hostPatterns) {
        if (re.hasMatch(host)) return true;
      }
    } catch (_) {
      // 忽略解析失败，继续用原字符串匹配
    }

    final lower = trimmed.toLowerCase();
    for (final re in _hostPatterns) {
      if (re.hasMatch(lower)) return true;
    }
    return false;
  }
}

/// 可复用的 NSFW 模糊遮罩组件
class NsfwBlurGuard extends StatelessWidget {
  final Widget child;
  final bool masked;
  final BorderRadius? borderRadius;
  final VoidCallback? onReveal;
  final bool showButton;
  final EdgeInsetsGeometry? padding;

  const NsfwBlurGuard({
    super.key,
    required this.child,
    required this.masked,
    this.borderRadius,
    this.onReveal,
    this.showButton = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    if (!masked) return child;

    final overlay = Stack(
      children: [
        // 背景模糊
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: child,
          ),
        ),
        // 半透明蒙层
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.35)),
        ),
        // 中心提示
        Positioned.fill(
          child: Padding(
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.visibility_off_rounded, color: Colors.white70, size: 28),
                const SizedBox(height: 8),
                const Text(
                  '内容警告：成人内容',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  '该内容已被标记为成人内容',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                if (showButton) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 86,
                    height: 34,
                    child: ElevatedButton(
                      onPressed: onReveal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.9),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        ),
                        padding: EdgeInsets.zero,
                        elevation: 0,
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      child: const Text('显示'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: overlay,
    );
  }
}

/// 仅作为覆盖层使用的 NSFW 模糊蒙层（使用 BackdropFilter，不包裹 child）
class NsfwBackdropOverlay extends StatelessWidget {
  final BorderRadius? borderRadius;
  final VoidCallback? onReveal;
  final bool showButton;
  final EdgeInsetsGeometry? padding;

  const NsfwBackdropOverlay({
    super.key,
    this.borderRadius,
    this.onReveal,
    this.showButton = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: padding ?? const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.visibility_off_rounded, color: Colors.white70, size: 28),
                  const SizedBox(height: 8),
                  const Text(
                    '内容警告：成人内容',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '该内容已被标记为成人内容',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  if (showButton) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 86,
                      height: 34,
                      child: ElevatedButton(
                        onPressed: onReveal,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.9),
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          ),
                          padding: EdgeInsets.zero,
                          elevation: 0,
                          textStyle: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        child: const Text('显示'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


