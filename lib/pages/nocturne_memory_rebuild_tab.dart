import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/nocturne_memory_rebuild_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_dialog.dart';

class NocturneMemoryRebuildTab extends StatefulWidget {
  const NocturneMemoryRebuildTab({super.key});

  @override
  State<NocturneMemoryRebuildTab> createState() =>
      _NocturneMemoryRebuildTabState();
}

class _NocturneMemoryRebuildTabState extends State<NocturneMemoryRebuildTab> {
  final NocturneMemoryRebuildService _controller =
      NocturneMemoryRebuildService.instance;
  final ScrollController _logScroll = ScrollController();
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    _lastLogCount = _controller.logs.length;
    _controller.addListener(_handleControllerChanged);
    unawaited(_controller.ensureInitialized(autoResume: true));
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _logScroll.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    final int nextLogCount = _controller.logs.length;
    final bool shouldScroll = nextLogCount != _lastLogCount;
    _lastLogCount = nextLogCount;
    if (!mounted) return;
    setState(() {});
    if (!shouldScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScroll.hasClients) return;
      try {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } catch (_) {}
    });
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _start() async {
    if (_controller.running) return;
    final bool ok = await UIDialogs.showConfirm(
      context,
      title: '一键重建记忆',
      message: '将清空当前 Nocturne 记忆库，并仅用“动态”里的截图图片重新构建。\n\n继续？',
      confirmText: '开始重建',
    );
    if (!ok) return;
    await _controller.startFresh();
    if (!mounted) return;
    if (_controller.running) {
      _toast('已开始后台重建，可在通知栏查看进度');
    }
  }

  Widget _buildStatsRow(BuildContext context) {
    final int total = _controller.totalSegments;
    final int cur = _controller.cursor.clamp(0, total);
    final String pos = total <= 0 ? '-' : '$cur/$total';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '进度：$pos  已处理=${_controller.processed}  跳过(无图)=${_controller.skippedNoImages}  跳过(文件缺失)=${_controller.skippedMissingFiles}  失败=${_controller.failed}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_controller.lastSegmentId != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '当前段落：#${_controller.lastSegmentId}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (_controller.segmentSampleCursorSegmentId != null &&
            _controller.segmentSampleTotal > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '段内图片：${_controller.segmentSampleCursor}/${_controller.segmentSampleTotal}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _controller.running
                ? '任务已切到页面外继续执行；退出此页不会暂停，可在通知栏查看进度。'
                : '重建任务已改为应用级任务：退出此页后不会因页面销毁而中断。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPausePanel(BuildContext context) {
    if (!_controller.paused) return const SizedBox.shrink();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String reason = (_controller.pauseReason ?? '').trim();
    final String header = reason == 'parse_failed'
        ? '解析失败，已暂停'
        : reason == 'apply_failed'
        ? '写入失败，已暂停'
        : reason == 'stopped'
        ? '已停止'
        : '已暂停';
    final String detail = (_controller.lastError ?? '').trim();
    final String raw = (_controller.lastRawResponse ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: cs.error.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onErrorContainer,
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onErrorContainer),
            ),
          ],
          if (raw.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '原始响应：',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onErrorContainer.withValues(alpha: 0.95),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(
                  color: cs.outline.withValues(alpha: 0.18),
                  width: 1,
                ),
              ),
              child: SelectableText(
                raw,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(
                onPressed: _controller.continueAfterPause,
                child: const Text('继续'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: (detail.isEmpty && raw.isEmpty)
                    ? null
                    : () async {
                        try {
                          final StringBuffer sb = StringBuffer();
                          if (_controller.lastSegmentId != null) {
                            sb.writeln(
                              'segment: #${_controller.lastSegmentId}',
                            );
                          }
                          if (reason.isNotEmpty) sb.writeln('reason: $reason');
                          if (detail.isNotEmpty) sb.writeln(detail);
                          if (raw.isNotEmpty) {
                            sb.writeln();
                            sb.writeln('raw:');
                            sb.writeln(raw);
                          }
                          await Clipboard.setData(
                            ClipboardData(text: sb.toString().trimRight()),
                          );
                          if (mounted) _toast('已复制');
                        } catch (_) {
                          if (mounted) _toast('复制失败');
                        }
                      },
                icon: const Icon(Icons.content_copy, size: 18),
                label: const Text('复制错误'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () async {
                  await UIDialogs.showInfo(
                    context,
                    title: '提示',
                    message:
                        '“继续”会跳过当前失败批次（本批最多10张图），继续处理本段剩余图片；若该段落已无剩余则进入下一段。\n\n若属于段落级异常，则会直接跳过该段落。',
                  );
                },
                child: const Text('说明'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(BuildContext context) {
    final List<String> logs = _controller.logs;
    if (logs.isEmpty) {
      return Center(
        child: Text(
          '日志会显示在这里',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _logScroll,
      itemCount: logs.length,
      itemBuilder: (ctx, i) {
        final s = logs[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(s, style: Theme.of(context).textTheme.bodySmall),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _controller.running ? null : _start,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('一键重建'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _controller.running ? _controller.requestStop : null,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('停止'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: _buildStatsRow(context),
          ),
          const SizedBox(height: 10),
          _buildPausePanel(context),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.0),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.18),
                  width: 1,
                ),
              ),
              child: _buildLogList(context),
            ),
          ),
        ],
      ),
    );
  }
}
