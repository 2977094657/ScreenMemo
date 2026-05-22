part of 'chat_context_sheet.dart';

extension _ChatContextPanelWidgetsPart on _ChatContextPanelState {
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
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
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
    CodexStyleTokenUsageInfo? usageInfo,
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
    final CodexStyleTokenUsage lastUsage =
        usageInfo?.lastTokenUsage ??
        latestUsage?.codexStyleUsage ??
        CodexStyleTokenUsage.fromValues(
          inputTokens: promptUsed,
          cachedInputTokens: 0,
          outputTokens: 0,
          reasoningOutputTokens: 0,
          totalTokens: promptUsed,
          source: 'estimate',
        );
    final CodexStyleTokenUsage totalUsage =
        usageInfo?.totalTokenUsage ?? lastUsage;

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
    final double usedRatio = capTokens > 0
        ? lastUsage.contextUsedRatio(capTokens)
        : 0.0;
    final String effectivePctText = capTokens > 0
        ? '${(usedRatio * 100).toStringAsFixed(1)}%'
        : '-';
    final String usageSummary = ChatContextSheet._loc(
      context,
      capTokens > 0
          ? '模型：$modelText · 上下文：${nf.format(lastUsage.tokensInContextWindow)} / ${nf.format(capTokens)} · 有效占用 $effectivePctText'
          : '模型：$modelText · 上下文：${nf.format(lastUsage.tokensInContextWindow)}',
      capTokens > 0
          ? 'Model: $modelText · Context: ${nf.format(lastUsage.tokensInContextWindow)} / ${nf.format(capTokens)} · effective used $effectivePctText'
          : 'Model: $modelText · Context: ${nf.format(lastUsage.tokensInContextWindow)}',
    );

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
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
                tooltip: ChatContextSheet._loc(
                  context,
                  '编辑模型上下文大小',
                  'Edit model context size',
                ),
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: model.trim().isEmpty
                    ? null
                    : () => _showEditModelContextWindowDialog(
                        model: model,
                        currentCapTokens: capTokens,
                      ),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            nf.format(lastUsage.tokensInContextWindow),
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
            Wrap(
              spacing: AppTheme.spacing2,
              runSpacing: AppTheme.spacing2,
              children: [
                _metricChip(
                  context,
                  ChatContextSheet._loc(context, '非缓存输入', 'Non-cached in'),
                  nf.format(lastUsage.nonCachedInputTokens),
                ),
                _metricChip(
                  context,
                  ChatContextSheet._loc(context, '缓存输入', 'Cached in'),
                  nf.format(lastUsage.cachedInputTokens),
                ),
                _metricChip(
                  context,
                  ChatContextSheet._loc(context, '输出', 'Output'),
                  nf.format(lastUsage.outputTokens),
                ),
                if (lastUsage.reasoningOutputTokens > 0)
                  _metricChip(
                    context,
                    ChatContextSheet._loc(context, '推理输出', 'Reasoning'),
                    nf.format(lastUsage.reasoningOutputTokens),
                  ),
                _metricChip(
                  context,
                  ChatContextSheet._loc(context, '计费显示', 'Display total'),
                  nf.format(lastUsage.blendedTotalTokens),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing2),
            SegmentedTokenBar(
              totalTokens: capTokens > 0
                  ? capTokens
                  : (promptUsed > 0 ? promptUsed : 1),
              segments: segments,
              height: 12,
            ),
            const SizedBox(height: AppTheme.spacing2),
            Text(
              ChatContextSheet._loc(
                context,
                '本会话累计：${nf.format(totalUsage.blendedTotalTokens)} display tokens（输入 ${nf.format(totalUsage.inputTokens)} / 缓存 ${nf.format(totalUsage.cachedInputTokens)} / 输出 ${nf.format(totalUsage.outputTokens)}）',
                'Conversation total: ${nf.format(totalUsage.blendedTotalTokens)} display tokens (input ${nf.format(totalUsage.inputTokens)} / cached ${nf.format(totalUsage.cachedInputTokens)} / output ${nf.format(totalUsage.outputTokens)})',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        '${AppLocalizations.of(context).labelWithColon(label)}$value',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
