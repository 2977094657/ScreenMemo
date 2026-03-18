import 'package:flutter/material.dart';
import '../services/timeline_jump_service.dart';
import '../theme/app_theme.dart';

/// 时间线跳转覆盖按钮（插件式，可附加到任意图片上）
///
/// - 默认左上角显示一个时间线图标按钮
/// - 点击后通过 TimelineJumpService 触发时间线定位
class TimelineJumpOverlay extends StatelessWidget {
  /// 目标截图的绝对路径
  final String filePath;

  /// 对齐方式（默认左上）
  final Alignment alignment;

  /// 外边距（默认左上各 6）
  final EdgeInsets margin;

  /// 背景色（默认半透明黑）
  final Color backgroundColor;

  /// 图标颜色（默认白色）
  final Color iconColor;

  /// 图标大小（默认 16）
  final double iconSize;

  const TimelineJumpOverlay({
    super.key,
    required this.filePath,
    this.alignment = Alignment.topLeft,
    this.margin = const EdgeInsets.only(left: 6, top: 6),
    this.backgroundColor = const Color(0x8C000000), // 0.55 透明黑
    this.iconColor = Colors.white,
    this.iconSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: margin,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            try {
              await TimelineJumpService.instance.jumpToFilePath(filePath);
            } catch (_) {}
          },
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.timeline, size: iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
