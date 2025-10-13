import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

/// 深度思考卡片的展开状态
enum ReasoningCardState {
  collapsed(false), // 折叠状态
  preview(true),    // 预览状态（加载时自动滚动到底部）
  expanded(true);   // 完全展开状态

  final bool isExpanded;
  const ReasoningCardState(this.isExpanded);
}

/// 深度思考卡片组件，复刻自 rikkahub 的设计
class ReasoningCard extends StatefulWidget {
  final String reasoning;
  final bool isLoading;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? accentColor;
  final bool autoCloseOnFinish;
  final String dots; // 动态省略号状态（由父组件驱动）

  const ReasoningCard({
    super.key,
    required this.reasoning,
    required this.isLoading,
    required this.createdAt,
    this.finishedAt,
    this.backgroundColor,
    this.textColor,
    this.accentColor,
    this.autoCloseOnFinish = false,
    this.dots = '',
  });

  @override
  State<ReasoningCard> createState() => _ReasoningCardState();
}

class _ReasoningCardState extends State<ReasoningCard> {
  ReasoningCardState _expandState = ReasoningCardState.collapsed;
  final ScrollController _scrollController = ScrollController();
  Duration _duration = Duration.zero;
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    _updateDuration();
  }

  @override
  void didUpdateWidget(ReasoningCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 加载状态变化时处理展开状态
    if (widget.isLoading != oldWidget.isLoading ||
        widget.reasoning != oldWidget.reasoning) {
      if (widget.isLoading) {
        if (!_expandState.isExpanded) {
          setState(() {
            _expandState = ReasoningCardState.preview;
          });
        }
        // 自动滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        // 加载完成
        if (_expandState.isExpanded) {
          setState(() {
            _expandState = widget.autoCloseOnFinish
                ? ReasoningCardState.collapsed
                : ReasoningCardState.expanded;
          });
        }
      }
    }
    
    _updateDuration();
  }

  void _updateDuration() {
    _durationTimer?.cancel();
    if (widget.isLoading) {
      _durationTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (mounted) {
          setState(() {
            _duration = DateTime.now().difference(widget.createdAt);
          });
        }
      });
    } else if (widget.finishedAt != null) {
      _duration = widget.finishedAt!.difference(widget.createdAt);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _durationTimer?.cancel();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      if (widget.isLoading) {
        _expandState = _expandState == ReasoningCardState.expanded
            ? ReasoningCardState.preview
            : ReasoningCardState.expanded;
      } else {
        _expandState = _expandState == ReasoningCardState.expanded
            ? ReasoningCardState.collapsed
            : ReasoningCardState.expanded;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ??
        Theme.of(context).colorScheme.surface.withOpacity(0.0);
    final textColor = widget.textColor ??
        Theme.of(context).colorScheme.onSurface;
    final accentColor = widget.accentColor ??
        Theme.of(context).colorScheme.secondary;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 头部：图标 + 标题 + 时长 + 展开/折叠按钮
              InkWell(
                onTap: _toggleExpand,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Row(
                    mainAxisSize: _expandState.isExpanded
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                     children: [
                      // 本地化“深度思考”文本
                      Text(
                        (AppLocalizations.of(context).deepThinkingLabel) + (widget.isLoading ? widget.dots : ''),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                              color: widget.isLoading
                                  ? Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7)
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      // 时长显示
                      if (_duration.inMilliseconds > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(${(_duration.inMilliseconds / 1000.0).toStringAsFixed(1)} s)',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                color: widget.isLoading
                                    ? Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7)
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                      if (_expandState.isExpanded) const Spacer(),
                      if (_expandState.isExpanded) const SizedBox(width: 4),
                      // 展开/折叠图标
                      Icon(
                        _expandState == ReasoningCardState.collapsed
                            ? Icons.keyboard_arrow_down
                            : _expandState == ReasoningCardState.expanded
                                ? Icons.keyboard_arrow_up
                                : Icons.open_in_full,
                        size: 14,
                        color: widget.isLoading
                            ? Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              // 思考内容区域
              if (_expandState.isExpanded && widget.reasoning.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildReasoningContent(context, textColor),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReasoningContent(BuildContext context, Color textColor) {
    final content = SelectableText(
      widget.reasoning,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: textColor,
            fontFamily: 'monospace',
            height: 1.25,
          ),
    );

    if (_expandState == ReasoningCardState.preview) {
      // 预览模式：限制高度，添加渐变蒙版，自动滚动
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 100),
        child: ShaderMask(
          shaderCallback: (Rect bounds) {
            const fadeHeight = 32.0;
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.transparent,
                Theme.of(context).colorScheme.onSurface,
                Theme.of(context).colorScheme.onSurface,
                Colors.transparent,
              ],
              stops: [
                0.0,
                fadeHeight / bounds.height,
                1 - fadeHeight / bounds.height,
                1.0,
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const ClampingScrollPhysics(),
            child: content,
          ),
        ),
      );
    } else {
      // 完全展开模式：无高度限制
      return content;
    }
  }
}

