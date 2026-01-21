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
  bool _wmEnabled = true;
  int _wmMaxTokens = 1400;
  int _wmEdgeLimit = 60;
  bool _amEnabled = true;
  bool _amAutoExtract = false;
  int _amMaxTokens = 700;
  int _amMaxItems = 24;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = ChatContextService.instance.getSnapshot();
    });
    _loadWorkingMemorySettings();
    _loadAtomicMemorySettings();
  }

  Future<void> _loadWorkingMemorySettings() async {
    try {
      final s = AISettingsService.instance;
      final bool enabled = await s.getWorkingMemoryInjectionEnabled();
      final int maxTokens = await s.getWorkingMemoryPromptTokens();
      final int edgeLimit = await s.getWorkingMemoryEdgeLimit();
      if (!mounted) return;
      setState(() {
        _wmEnabled = enabled;
        _wmMaxTokens = maxTokens;
        _wmEdgeLimit = edgeLimit;
      });
    } catch (_) {}
  }

  Future<void> _setWmEnabled(bool v) async {
    setState(() => _wmEnabled = v);
    try {
      await AISettingsService.instance.setWorkingMemoryInjectionEnabled(v);
    } catch (_) {}
  }

  Future<void> _setWmMaxTokens(int v) async {
    final int next = v.clamp(200, 4000);
    setState(() => _wmMaxTokens = next);
    try {
      await AISettingsService.instance.setWorkingMemoryPromptTokens(next);
    } catch (_) {}
  }

  Future<void> _setWmEdgeLimit(int v) async {
    final int next = v.clamp(10, 200);
    setState(() => _wmEdgeLimit = next);
    try {
      await AISettingsService.instance.setWorkingMemoryEdgeLimit(next);
    } catch (_) {}
  }

  Future<void> _loadAtomicMemorySettings() async {
    try {
      final s = AISettingsService.instance;
      final bool enabled = await s.getAtomicMemoryInjectionEnabled();
      final bool autoExtract = await s.getAtomicMemoryAutoExtractEnabled();
      final int maxTokens = await s.getAtomicMemoryPromptTokens();
      final int maxItems = await s.getAtomicMemoryMaxItems();
      if (!mounted) return;
      setState(() {
        _amEnabled = enabled;
        _amAutoExtract = autoExtract;
        _amMaxTokens = maxTokens;
        _amMaxItems = maxItems;
      });
    } catch (_) {}
  }

  Future<void> _setAmEnabled(bool v) async {
    setState(() => _amEnabled = v);
    try {
      await AISettingsService.instance.setAtomicMemoryInjectionEnabled(v);
    } catch (_) {}
  }

  Future<void> _setAmAutoExtract(bool v) async {
    setState(() => _amAutoExtract = v);
    try {
      await AISettingsService.instance.setAtomicMemoryAutoExtractEnabled(v);
    } catch (_) {}
  }

  Future<void> _setAmMaxTokens(int v) async {
    final int next = v.clamp(100, 2000);
    setState(() => _amMaxTokens = next);
    try {
      await AISettingsService.instance.setAtomicMemoryPromptTokens(next);
    } catch (_) {}
  }

  Future<void> _setAmMaxItems(int v) async {
    final int next = v.clamp(5, 80);
    setState(() => _amMaxItems = next);
    try {
      await AISettingsService.instance.setAtomicMemoryMaxItems(next);
    } catch (_) {}
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
                        _workingMemoryCard(context),
                        const SizedBox(height: AppTheme.spacing3),
                        _atomicMemoryCard(context),
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

  Widget _workingMemoryCard(BuildContext context) {
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
            ChatContextSheet._loc(
              context,
              '工作记忆注入（MemOS）',
              'Working memory injection (MemOS)',
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Row(
            children: [
              Expanded(
                child: Text(
                  ChatContextSheet._loc(
                    context,
                    '启用 <working_memory> 系统消息',
                    'Enable <working_memory> system message',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Switch(
                value: _wmEnabled,
                onChanged: _busy ? null : (v) => _setWmEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          _stepperRow(
            context,
            label: ChatContextSheet._loc(
              context,
              'Token 预算（粗估）',
              'Token budget (approx)',
            ),
            valueText: _wmMaxTokens.toString(),
            onMinus: _busy || _wmMaxTokens <= 200
                ? null
                : () => _setWmMaxTokens(_wmMaxTokens - 200),
            onPlus: _busy || _wmMaxTokens >= 4000
                ? null
                : () => _setWmMaxTokens(_wmMaxTokens + 200),
          ),
          const SizedBox(height: AppTheme.spacing1),
          _stepperRow(
            context,
            label: ChatContextSheet._loc(
              context,
              '图谱边条数上限',
              'Edge limit',
            ),
            valueText: _wmEdgeLimit.toString(),
            onMinus: _busy || _wmEdgeLimit <= 10
                ? null
                : () => _setWmEdgeLimit(_wmEdgeLimit - 10),
            onPlus: _busy || _wmEdgeLimit >= 200
                ? null
                : () => _setWmEdgeLimit(_wmEdgeLimit + 10),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            ChatContextSheet._loc(
              context,
              '提示：这是每次对话请求前的“长期记忆装配”，用于稳定 persona/关系链；过大可能挤占历史上下文。',
              'Tip: this injects long-term memory before each request (persona/relations). Too large may crowd out chat history.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _atomicMemoryCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ChatContextSheet._loc(
              context,
              '原子记忆注入（SimpleMem）',
              'Atomic memory injection (SimpleMem)',
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Row(
            children: [
              Expanded(
                child: Text(
                  ChatContextSheet._loc(
                    context,
                    '启用 <atomic_memory> 系统消息（事实/规则）',
                    'Enable <atomic_memory> system message (facts/rules)',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Switch(
                value: _amEnabled,
                onChanged: _busy ? null : (v) => _setAmEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          Row(
            children: [
              Expanded(
                child: Text(
                  ChatContextSheet._loc(
                    context,
                    '自动抽取并写入（会触发 AI 调用）',
                    'Auto-extract & write (uses AI calls)',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Switch(
                value: _amAutoExtract,
                onChanged: _busy ? null : (v) => _setAmAutoExtract(v),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          _stepperRow(
            context,
            label: ChatContextSheet._loc(
              context,
              'Token 预算（粗估）',
              'Token budget (approx)',
            ),
            valueText: _amMaxTokens.toString(),
            onMinus: _busy || _amMaxTokens <= 100
                ? null
                : () => _setAmMaxTokens(_amMaxTokens - 100),
            onPlus: _busy || _amMaxTokens >= 2000
                ? null
                : () => _setAmMaxTokens(_amMaxTokens + 100),
          ),
          const SizedBox(height: AppTheme.spacing1),
          _stepperRow(
            context,
            label: ChatContextSheet._loc(
              context,
              '条目上限',
              'Max items',
            ),
            valueText: _amMaxItems.toString(),
            onMinus:
                _busy || _amMaxItems <= 5 ? null : () => _setAmMaxItems(_amMaxItems - 5),
            onPlus:
                _busy || _amMaxItems >= 80 ? null : () => _setAmMaxItems(_amMaxItems + 5),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            ChatContextSheet._loc(
              context,
              '提示：原子记忆用于稳定保存“可复用的个人事实/偏好规则”。开启自动抽取会增加一次小的后台请求（已做节流）。',
              'Tip: atomic memory stores durable user facts/preferences. Auto-extract adds a small background request (throttled).',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepperRow(
    BuildContext context, {
    required String label,
    required String valueText,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
        ),
        IconButton(
          tooltip: ChatContextSheet._loc(context, '减少', 'Decrease'),
          onPressed: onMinus,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 64,
          child: Center(
            child: Text(
              valueText,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        IconButton(
          tooltip: ChatContextSheet._loc(context, '增加', 'Increase'),
          onPressed: onPlus,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
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
