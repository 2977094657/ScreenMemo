part of 'chat_context_sheet.dart';

extension _ChatContextPanelWidgetsPart on _ChatContextPanelState {
  Widget _lastPromptUsageCard(BuildContext context, ChatContextSnapshot s) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat nf = NumberFormat.decimalPattern();

    String model = _activeModel;
    int? maxTokens = _activeModelContextTokens;
    int? outTokens = _activeModelOutputTokens;

    final Map<String, int> parts = <String, int>{};
    int totalTokens = s.lastPromptTokens ?? 0;

    final String raw = s.lastPromptBreakdownJson.trim();
    if (raw.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map) {
          final String m = (decoded['model'] ?? '').toString().trim();
          if (m.isNotEmpty) {
            model = m;
            final int fallbackCap = AIContextBudgets.forModel(
              m,
            ).promptCapTokens;
            final int? override = AIModelPromptCapsService.instance
                .peekOverride(m);
            maxTokens = override ?? fallbackCap;
            outTokens = ModelsDevModelLimits.outputTokens(m);
          }
          final dynamic total = decoded['total_tokens'];
          if (total is num) totalTokens = total.toInt();
          final dynamic p = decoded['parts'];
          if (p is Map) {
            for (final entry in p.entries) {
              final String k = entry.key.toString();
              final dynamic v = entry.value;
              if (v is num) {
                final int t = v.toInt();
                if (t > 0) parts[k] = t;
              }
            }
          }
        }
      } catch (_) {}
    }

    final int used = parts.isNotEmpty
        ? parts.values.fold(0, (a, b) => a + b)
        : totalTokens;
    final int cap = (maxTokens ?? 0).clamp(0, 1 << 30);
    final double ratio = cap > 0 ? (used / cap).clamp(0.0, 999.0) : 0.0;

    final List<PromptTokenPart> order = <PromptTokenPart>[
      PromptTokenPart.systemPrompt,
      PromptTokenPart.toolSchema,
      PromptTokenPart.toolInstruction,
      PromptTokenPart.conversationContext,
      PromptTokenPart.extraSystem,
      PromptTokenPart.historyUser,
      PromptTokenPart.historyAssistant,
      PromptTokenPart.historyTool,
      PromptTokenPart.userMessage,
    ];

    final List<SegmentedTokenBarSegment> segments = <SegmentedTokenBarSegment>[
      for (final part in order)
        if ((parts[part.key] ?? 0) > 0)
          SegmentedTokenBarSegment(
            tokens: parts[part.key]!,
            color: part.color(theme),
          ),
      if (parts.isEmpty && used > 0)
        SegmentedTokenBarSegment(
          tokens: used,
          color: theme.colorScheme.primary,
        ),
    ];

    final String capText = cap > 0 ? nf.format(cap) : '-';
    final String usedText = used > 0 ? nf.format(used) : '-';
    final String pctText = cap > 0
        ? '${(ratio * 100).toStringAsFixed(1)}%'
        : '-';
    final String outText = outTokens == null
        ? ''
        : ' · out≈${nf.format(outTokens)}';

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
              '最近一次模型调用占用（≈）',
              'Last model call usage (≈)',
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            ChatContextSheet._loc(
              context,
              '时间：${ChatContextSheet._fmtTs(s.lastPromptAtMs)}',
              'Time: ${ChatContextSheet._fmtTs(s.lastPromptAtMs)}',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Row(
            children: [
              Expanded(
                child: Text(
                  ChatContextSheet._loc(context, '模型：$model', 'Model: $model'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: ChatContextSheet._loc(context, '设置上限', 'Set cap'),
                onPressed: model.trim().isEmpty
                    ? null
                    : () => _editModelPromptCapDialog(
                        context,
                        model: model,
                        fallbackPromptCapTokens: AIContextBudgets.forModel(
                          model,
                        ).promptCapTokens,
                      ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            ChatContextSheet._loc(
              context,
              '已用 $usedText / $capText（$pctText）$outText',
              'Used $usedText / $capText ($pctText)$outText',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          SegmentedTokenBar(
            totalTokens: cap > 0 ? cap : (used > 0 ? used : 1),
            segments: segments,
            height: 12,
          ),
          if (raw.isEmpty) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              ChatContextSheet._loc(
                context,
                '暂无记录（发送一次消息后会写入）',
                'No record yet (written after you send a message).',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else if (parts.isEmpty) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              ChatContextSheet._loc(
                context,
                '暂无细分数据',
                'No breakdown available.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            const SizedBox(height: AppTheme.spacing2),
            Wrap(
              spacing: AppTheme.spacing2,
              runSpacing: AppTheme.spacing1,
              children: [
                for (final part in order)
                  if ((parts[part.key] ?? 0) > 0)
                    _legendItem(
                      context,
                      color: part.color(theme),
                      label: ChatContextSheet._isZh(context)
                          ? part.labelZh()
                          : part.labelEn(),
                      tokens: parts[part.key]!,
                      total: cap > 0 ? cap : used,
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendItem(
    BuildContext context, {
    required Color color,
    required String label,
    required int tokens,
    required int total,
  }) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat nf = NumberFormat.decimalPattern();
    final double pct = total > 0 ? (tokens / total) : 0;
    final String pctText = '${(pct * 100).toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: AppTheme.spacing1,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: AppTheme.spacing1),
          Text(
            '$label · ${nf.format(tokens)} ($pctText)',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _conversationTokenUsageCard(
    BuildContext context,
    ChatContextSnapshot s, {
    PromptUsageEvent? latestUsage,
  }) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat nf = NumberFormat.decimalPattern();

    String model = (latestUsage?.model ?? '').trim();
    int fallbackCapTokens = (_activeModelContextTokens ?? 0)
        .clamp(0, 1 << 30)
        .toInt();

    final List<PromptTokenPart> order = <PromptTokenPart>[
      PromptTokenPart.systemPrompt,
      PromptTokenPart.toolSchema,
      PromptTokenPart.toolInstruction,
      PromptTokenPart.conversationContext,
      PromptTokenPart.extraSystem,
      PromptTokenPart.historyUser,
      PromptTokenPart.historyAssistant,
      PromptTokenPart.historyTool,
      PromptTokenPart.userMessage,
    ];

    final Map<String, int> parts = <String, int>{};
    final int promptUsed =
        (latestUsage?.resolvedPromptTokens ?? (s.lastPromptTokens ?? 0))
            .clamp(0, 1 << 62)
            .toInt();

    void applyPartsFromMap(Object? p) {
      if (p is! Map) return;
      for (final entry in p.entries) {
        final String k = entry.key.toString();
        final dynamic v = entry.value;
        if (v is! num) continue;
        final int t = v.toInt();
        if (t <= 0) continue;
        parts[k] = t;
      }
    }

    try {
      applyPartsFromMap((latestUsage?.breakdown)?['parts']);
    } catch (_) {}

    final String raw = s.lastPromptBreakdownJson.trim();
    if (raw.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map) {
          final String m = (decoded['model'] ?? '').toString().trim();
          if (model.trim().isEmpty && m.isNotEmpty) {
            model = m;
            fallbackCapTokens = AIContextBudgets.forModel(m).promptCapTokens;
          }
          if (parts.isEmpty) applyPartsFromMap(decoded['parts']);
        }
      } catch (_) {}
    }

    if (model.trim().isEmpty) {
      model = _activeModel.trim();
    }

    final int capTokens =
        (AIModelPromptCapsService.instance.peekOverride(model) ??
                fallbackCapTokens)
            .clamp(0, 1 << 30)
            .toInt();

    // No breakdown recorded (older rows / failures): keep totals consistent.
    if (parts.isEmpty && promptUsed > 0) {
      parts[PromptTokenPart.extraSystem.key] = promptUsed;
    }

    final int partsAll = parts.values.fold<int>(0, (a, b) => a + b);
    final int partsSumKnown = order.fold<int>(
      0,
      (a, part) => a + (parts[part.key] ?? 0),
    );
    final int remainder = (partsAll - partsSumKnown).clamp(0, 1 << 62).toInt();
    final int gap = (promptUsed - partsAll).clamp(0, 1 << 62).toInt();
    final int legendTotal = (partsAll > promptUsed ? partsAll : promptUsed)
        .clamp(1, 1 << 62)
        .toInt();

    final List<({int tokens, Color color, String label, int tie})> legendItems =
        <({int tokens, Color color, String label, int tie})>[];
    int legendTie = 0;
    for (final part in order) {
      final int t = (parts[part.key] ?? 0).clamp(0, 1 << 62).toInt();
      if (t <= 0) continue;
      legendItems.add((
        tokens: t,
        color: part.color(theme),
        label: ChatContextSheet._isZh(context)
            ? part.labelZh()
            : part.labelEn(),
        tie: legendTie++,
      ));
    }
    if (remainder > 0) {
      legendItems.add((
        tokens: remainder,
        color: theme.colorScheme.primary,
        label: ChatContextSheet._loc(context, '其他', 'Other'),
        tie: legendTie++,
      ));
    }
    if (gap > 0) {
      legendItems.add((
        tokens: gap,
        color: theme.colorScheme.secondary,
        label: ChatContextSheet._loc(context, '估算差异', 'Estimation gap'),
        tie: legendTie++,
      ));
    }
    legendItems.sort((a, b) {
      final int byTokens = b.tokens.compareTo(a.tokens);
      if (byTokens != 0) return byTokens;
      return a.tie.compareTo(b.tie);
    });

    final List<SegmentedTokenBarSegment> segments = <SegmentedTokenBarSegment>[
      for (final part in order)
        if ((parts[part.key] ?? 0) > 0)
          SegmentedTokenBarSegment(
            tokens: parts[part.key]!,
            color: part.color(theme),
          ),
      if (remainder > 0)
        SegmentedTokenBarSegment(
          tokens: remainder,
          color: theme.colorScheme.primary,
        ),
    ];
    if (segments.isEmpty) {
      if (promptUsed > 0) {
        segments.add(
          SegmentedTokenBarSegment(
            tokens: promptUsed,
            color: theme.colorScheme.primary,
          ),
        );
      }
    }
    if (gap > 0) {
      segments.add(
        SegmentedTokenBarSegment(
          tokens: gap,
          color: theme.colorScheme.secondary,
        ),
      );
    }

    final String modelText = model.trim().isEmpty ? '-' : model.trim();
    final String usageSummary = ChatContextSheet._loc(
      context,
      capTokens > 0
          ? '模型：$modelText · 当前 token：${nf.format(promptUsed)}（${((promptUsed / capTokens) * 100).toStringAsFixed(1)}%）/ ${nf.format(capTokens)}'
          : '模型：$modelText · 当前 token：${nf.format(promptUsed)}',
      capTokens > 0
          ? 'Model: $modelText · Current tokens: ${nf.format(promptUsed)} (${((promptUsed / capTokens) * 100).toStringAsFixed(1)}%) / ${nf.format(capTokens)}'
          : 'Model: $modelText · Current tokens: ${nf.format(promptUsed)}',
    );

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
          Row(
            children: [
              Expanded(
                child: Text(
                  ChatContextSheet._loc(context, 'token用量', 'Token usage'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: ChatContextSheet._loc(context, '设置上限', 'Set cap'),
                onPressed: model.trim().isEmpty
                    ? null
                    : () => _editModelPromptCapDialog(
                        context,
                        model: model,
                        fallbackPromptCapTokens: AIContextBudgets.forModel(
                          model,
                        ).promptCapTokens,
                      ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            nf.format(promptUsed),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (promptUsed <= 0) ...[
            const SizedBox(height: AppTheme.spacing1),
            Text(
              ChatContextSheet._loc(
                context,
                '暂无记录（发送一次消息后会写入）',
                'No record yet (written after you send a message).',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            const SizedBox(height: AppTheme.spacing1),
            Text(
              usageSummary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTheme.spacing2),
            SegmentedTokenBar(
              totalTokens: capTokens > 0
                  ? capTokens
                  : (promptUsed > 0 ? promptUsed : 1),
              segments: segments,
              height: 12,
            ),
            if (parts.isNotEmpty || remainder > 0 || gap > 0) ...[
              const SizedBox(height: AppTheme.spacing2),
              Wrap(
                spacing: AppTheme.spacing2,
                runSpacing: AppTheme.spacing1,
                children: [
                  for (final it in legendItems)
                    _legendItem(
                      context,
                      color: it.color,
                      label: it.label,
                      tokens: it.tokens,
                      total: legendTotal,
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _conversationUsageTotalsCard(
    BuildContext context,
    PromptUsageTotals totals,
  ) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat nf = NumberFormat.decimalPattern();
    final String coverageText =
        '${(totals.usageCoverage * 100).toStringAsFixed(1)}%';
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
            ChatContextSheet._loc(context, '本会话累计', 'Conversation totals'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Wrap(
            spacing: AppTheme.spacing2,
            runSpacing: AppTheme.spacing2,
            children: [
              _metricChip(
                context,
                ChatContextSheet._loc(context, '输入', 'Prompt'),
                nf.format(totals.promptTokens),
              ),
              _metricChip(
                context,
                ChatContextSheet._loc(context, '输出', 'Completion'),
                nf.format(totals.completionTokens),
              ),
              _metricChip(
                context,
                ChatContextSheet._loc(context, '总计', 'Total'),
                nf.format(totals.totalTokens),
              ),
              _metricChip(
                context,
                ChatContextSheet._loc(context, '调用数', 'Calls'),
                nf.format(totals.eventsCount),
              ),
              _metricChip(
                context,
                ChatContextSheet._loc(context, 'usage 覆盖', 'Usage coverage'),
                coverageText,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _promptUsageEventsCard(
    BuildContext context,
    List<PromptUsageEvent> events,
  ) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat nf = NumberFormat.decimalPattern();
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
            ChatContextSheet._loc(context, '每次请求明细', 'Per-request details'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          if (events.isEmpty)
            Text(
              ChatContextSheet._loc(
                context,
                '暂无请求明细。',
                'No request events yet.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...events.take(20).map((PromptUsageEvent event) {
              final String source = event.hasUsage ? 'usage' : 'estimate';
              final String flags = <String>[
                if (event.strictFullAttempted)
                  ChatContextSheet._loc(context, 'strict', 'strict'),
                if (event.fallbackTriggered)
                  ChatContextSheet._loc(context, 'fallback', 'fallback'),
                if (event.isToolLoop)
                  ChatContextSheet._loc(context, 'tool', 'tool'),
              ].join(' · ');
              final String model = event.model.trim().isEmpty
                  ? '-'
                  : event.model.trim();
              final String line =
                  '${ChatContextSheet._fmtTs(event.createdAtMs)} · $model · '
                  'prompt=${nf.format(event.resolvedPromptTokens)} · '
                  '$source · '
                  'tools=${event.toolsCount}';
              return Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                child: Container(
                  padding: const EdgeInsets.all(AppTheme.spacing2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(
                      color: theme.colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line, style: theme.textTheme.bodySmall),
                      if (flags.isNotEmpty)
                        Text(
                          flags,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _metricChip(BuildContext context, String label, String value) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: AppTheme.spacing1,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
      ),
      child: Text(
        '${AppLocalizations.of(context).labelWithColon(label)}$value',
        style: theme.textTheme.bodySmall,
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
        Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
        IconButton(
          tooltip: ChatContextSheet._loc(context, '减少', 'Decrease'),
          onPressed: onMinus,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 64,
          child: Center(
            child: Text(valueText, style: theme.textTheme.bodySmall),
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
