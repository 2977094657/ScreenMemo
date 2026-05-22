part of 'chat_context_sheet.dart';

extension _ChatContextPanelActionsPart on _ChatContextPanelState {
  Future<void> _loadModelInfo() async {
    try {
      final String model = await AISettingsService.instance.getModel();
      final int ctx = (await AIContextBudgets.forModelWithOverrides(
        model,
      )).promptCapTokens.clamp(256, 1 << 30).toInt();
      if (!mounted) return;
      _panelSetState(() {
        _activeModel = model;
        _activeModelContextTokens = ctx;
      });
    } catch (_) {}
  }

  Future<void> _showEditModelContextWindowDialog({
    required String model,
    required int currentCapTokens,
  }) async {
    final String modelName = model.trim();
    if (modelName.isEmpty) return;

    final TextEditingController controller = TextEditingController(
      text: currentCapTokens > 0 ? currentCapTokens.toString() : '',
    );
    try {
      final int? next = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              ChatContextSheet._loc(
                dialogContext,
                '编辑模型上下文大小',
                'Edit model context size',
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  modelName,
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing2),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: ChatContextSheet._loc(
                      dialogContext,
                      '上下文 token 上限',
                      'Context token limit',
                    ),
                    hintText: '128000',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(AppLocalizations.of(dialogContext).dialogCancel),
              ),
              FilledButton(
                onPressed: () {
                  final int? parsed = int.tryParse(controller.text.trim());
                  if (parsed == null || parsed < 256) {
                    UINotifier.error(
                      dialogContext,
                      ChatContextSheet._loc(
                        dialogContext,
                        '请输入不小于 256 的整数',
                        'Enter an integer greater than or equal to 256.',
                      ),
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(parsed);
                },
                child: Text(ChatContextSheet._loc(dialogContext, '保存', 'Save')),
              ),
            ],
          );
        },
      );
      if (next == null) return;
      await AIModelPromptCapsService.instance.setOverride(modelName, next);
      if (!mounted) return;
      _panelSetState(() {
        _activeModelContextTokens = next.clamp(256, 1 << 30).toInt();
        _lastPromptModelForCapOverride = '';
      });
      _reload();
      AISettingsService.instance.notifyContextChanged('chat:prompt_tokens');
      UINotifier.success(
        context,
        ChatContextSheet._loc(
          context,
          '模型上下文大小已更新',
          'Model context size updated.',
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  String _trimEventTitle(ChatContextEvent event) {
    final NumberFormat nf = NumberFormat.decimalPattern();
    return ChatContextSheet._loc(
      context,
      '裁剪 ${nf.format(event.droppedTokens)} token',
      'Trimmed ${nf.format(event.droppedTokens)} tokens',
    );
  }

  String _trimEventSubtitle(ChatContextEvent event) {
    final NumberFormat nf = NumberFormat.decimalPattern();
    final String tokens =
        '${nf.format(event.beforeTokens)} → ${nf.format(event.afterTokens)}';
    final String dropped = nf.format(event.droppedTokens);
    final String reason = event.reason.isEmpty ? '-' : event.reason;
    return ChatContextSheet._loc(
      context,
      'tokens: $tokens，丢弃: $dropped，原因: $reason',
      'tokens: $tokens, dropped: $dropped, reason: $reason',
    );
  }

  Widget _trimEventsCard(BuildContext context, List<ChatContextEvent> events) {
    final ThemeData theme = Theme.of(context);
    final List<ChatContextEvent> shown =
        events.length > _ChatContextPanelState._trimEventsMaxLimit
        ? events.sublist(0, _ChatContextPanelState._trimEventsMaxLimit)
        : events;
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
          Text(
            ChatContextSheet._loc(context, 'Token 裁剪事件', 'Token trim events'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            ChatContextSheet._loc(
              context,
              '最近 ${shown.length} 条',
              'Latest ${shown.length} events',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          if (shown.isEmpty)
            Text(
              ChatContextSheet._loc(
                context,
                '暂无 token 丢弃事件',
                'No token trim events yet.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...shown.map(
              (e) => Container(
                margin: const EdgeInsets.only(bottom: AppTheme.spacing2),
                padding: const EdgeInsets.all(AppTheme.spacing2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _trimEventTitle(e),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing1),
                    Text(
                      _trimEventSubtitle(e),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ChatContextSheet._loc(
                        context,
                        '时间：${ChatContextSheet._fmtTs(e.createdAtMs)}',
                        'Time: ${ChatContextSheet._fmtTs(e.createdAtMs)}',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
}
