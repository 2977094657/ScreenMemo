import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/ai_settings_service.dart';
import '../services/chat_context_service.dart';
import '../theme/app_theme.dart';
import 'ui_components.dart';

class ChatContextSheet {
  static bool _isZh(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase().startsWith('zh');

  static String _loc(BuildContext context, String zh, String en) =>
      _isZh(context) ? zh : en;

  static String _fmtTs(int? ms) {
    if (ms == null || ms <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  }

  static String _prettyJson(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return '';
    try {
      final dynamic v = jsonDecode(t);
      return const JsonEncoder.withIndent('  ').convert(v);
    } catch (_) {
      return t;
    }
  }

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _ChatContextSheetBody(),
    );
  }
}

class _ChatContextSheetBody extends StatefulWidget {
  const _ChatContextSheetBody();

  @override
  State<_ChatContextSheetBody> createState() => _ChatContextSheetBodyState();
}

class _ChatContextSheetBodyState extends State<_ChatContextSheetBody> {
  Future<ChatContextSnapshot>? _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = ChatContextService.instance.getSnapshot();
    });
  }

  Future<void> _copy(String text) async {
    final String t = text.trim();
    if (t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    UINotifier.success(
      context,
      ChatContextSheet._loc(context, '已复制', 'Copied'),
    );
  }

  Future<void> _run({
    required Future<void> Function() action,
    required String okTextZh,
    required String okTextEn,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      UINotifier.success(
        context,
        ChatContextSheet._loc(context, okTextZh, okTextEn),
      );
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        ChatContextSheet._loc(context, '失败：$e', 'Failed: $e'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (sheetCtx, ctrl) {
        return UISheetSurface(
          child: Column(
            children: [
              const SizedBox(height: AppTheme.spacing3),
              const UISheetHandle(),
              const SizedBox(height: AppTheme.spacing2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ChatContextSheet._loc(
                          context,
                          '对话上下文（压缩/记忆）',
                          'Conversation Context (Memory)',
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: ChatContextSheet._loc(context, '刷新', 'Refresh'),
                      onPressed: _busy ? null : _reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacing2),
              Expanded(
                child: FutureBuilder<ChatContextSnapshot>(
                  future: _future,
                  builder: (c, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final ChatContextSnapshot? s = snap.data;
                    if (s == null) {
                      return Center(
                        child: Text(
                          ChatContextSheet._loc(
                            context,
                            '未获取到上下文信息',
                            'No context snapshot',
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                      );
                    }

                    final String summary = s.summary.trim();
                    final String toolMemPretty = ChatContextSheet._prettyJson(
                      s.toolMemoryJson,
                    );

                    return ListView(
                      controller: ctrl,
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacing4,
                        0,
                        AppTheme.spacing4,
                        AppTheme.spacing4,
                      ),
                      children: [
                        _kvCard(
                          context,
                          title: ChatContextSheet._loc(
                            context,
                            '状态',
                            'Status',
                          ),
                          rows: <MapEntry<String, String>>[
                            MapEntry('cid', s.cid),
                            MapEntry(
                              ChatContextSheet._loc(context, '全量消息数', 'Full messages'),
                              s.fullMessageCount.toString(),
                            ),
                            MapEntry(
                              ChatContextSheet._loc(context, '摘要 tokens≈', 'Summary tokens≈'),
                              s.summaryTokens.toString(),
                            ),
                            MapEntry(
                              ChatContextSheet._loc(context, '摘要更新时间', 'Summary updated'),
                              ChatContextSheet._fmtTs(s.summaryUpdatedAtMs),
                            ),
                            MapEntry(
                              ChatContextSheet._loc(context, '压缩次数', 'Compactions'),
                              s.compactionCount.toString(),
                            ),
                            MapEntry(
                              ChatContextSheet._loc(context, '上次压缩原因', 'Last reason'),
                              (s.lastCompactionReason ?? '').trim().isEmpty
                                  ? '-'
                                  : s.lastCompactionReason!.trim(),
                            ),
                            MapEntry(
                              ChatContextSheet._loc(
                                context,
                                '工具记忆更新时间',
                                'Tool memory updated',
                              ),
                              ChatContextSheet._fmtTs(s.toolMemoryUpdatedAtMs),
                            ),
                            MapEntry(
                              ChatContextSheet._loc(
                                context,
                                '上次 prompt tokens≈',
                                'Last prompt tokens≈',
                              ),
                              (s.lastPromptTokens ?? 0).toString(),
                            ),
                            MapEntry(
                              ChatContextSheet._loc(
                                context,
                                '上次 prompt 时间',
                                'Last prompt time',
                              ),
                              ChatContextSheet._fmtTs(s.lastPromptAtMs),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spacing3),
                        _actionRow(
                          context,
                          busy: _busy,
                          onCompact: () => _run(
                            action: () => ChatContextService.instance.compactNow(
                              reason: 'manual_ui',
                            ),
                            okTextZh: '压缩完成',
                            okTextEn: 'Compaction done',
                          ),
                          onClearMemory: () => _run(
                            action: () => ChatContextService.instance.clearContext(),
                            okTextZh: '已清空记忆',
                            okTextEn: 'Memory cleared',
                          ),
                          onClearChat: () => _run(
                            action: () => AISettingsService.instance.clearChatHistory(),
                            okTextZh: '已清空对话',
                            okTextEn: 'Conversation cleared',
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacing2),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            ChatContextSheet._loc(
                              context,
                              '摘要（用于注入模型）',
                              'Summary (Injected to model)',
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            summary.isEmpty
                                ? ChatContextSheet._loc(
                                    context,
                                    '暂无摘要（达到阈值后会自动生成，或手动点击“立即压缩”）',
                                    'No summary yet (auto after threshold, or tap “Compact now”).',
                                  )
                                : (summary.length > 80
                                      ? (summary.substring(0, 80) + '…')
                                      : summary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppTheme.spacing3),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                              ),
                              child: SelectableText(
                                summary.isEmpty ? '-' : summary,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                            Align(
                              alignment: Alignment.centerRight,
                              child: UIButton(
                                text: ChatContextSheet._loc(context, '复制摘要', 'Copy'),
                                onPressed: summary.isEmpty ? null : () => _copy(summary),
                                variant: UIButtonVariant.outline,
                                size: UIButtonSize.small,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spacing2),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            ChatContextSheet._loc(
                              context,
                              '工具记忆（摘要）',
                              'Tool memory (Digest)',
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            toolMemPretty.isEmpty
                                ? ChatContextSheet._loc(
                                    context,
                                    '暂无工具记忆（模型调用检索工具后会自动写入）',
                                    'No tool memory yet (written after tool calls).',
                                  )
                                : (toolMemPretty.length > 80
                                      ? (toolMemPretty.substring(0, 80) + '…')
                                      : toolMemPretty),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppTheme.spacing3),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                              ),
                              child: SelectableText(
                                toolMemPretty.isEmpty ? '-' : toolMemPretty,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                            Align(
                              alignment: Alignment.centerRight,
                              child: UIButton(
                                text: ChatContextSheet._loc(context, '复制', 'Copy'),
                                onPressed: toolMemPretty.isEmpty
                                    ? null
                                    : () => _copy(toolMemPretty),
                                variant: UIButtonVariant.outline,
                                size: UIButtonSize.small,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spacing2),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kvCard(
    BuildContext context, {
    required String title,
    required List<MapEntry<String, String>> rows,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          ...rows.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacing1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      e.key,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      e.value,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(
    BuildContext context, {
    required bool busy,
    required VoidCallback onCompact,
    required VoidCallback onClearMemory,
    required VoidCallback onClearChat,
  }) {
    return Row(
      children: [
        Expanded(
          child: UIButton(
            text: ChatContextSheet._loc(context, '立即压缩', 'Compact now'),
            onPressed: busy ? null : onCompact,
            variant: UIButtonVariant.primary,
            size: UIButtonSize.small,
            fullWidth: true,
          ),
        ),
        const SizedBox(width: AppTheme.spacing2),
        Expanded(
          child: UIButton(
            text: ChatContextSheet._loc(context, '清空记忆', 'Clear memory'),
            onPressed: busy ? null : onClearMemory,
            variant: UIButtonVariant.outline,
            size: UIButtonSize.small,
            fullWidth: true,
          ),
        ),
        const SizedBox(width: AppTheme.spacing2),
        Expanded(
          child: UIButton(
            text: ChatContextSheet._loc(context, '清空对话', 'Clear chat'),
            onPressed: busy ? null : onClearChat,
            variant: UIButtonVariant.destructive,
            size: UIButtonSize.small,
            fullWidth: true,
          ),
        ),
      ],
    );
  }
}

