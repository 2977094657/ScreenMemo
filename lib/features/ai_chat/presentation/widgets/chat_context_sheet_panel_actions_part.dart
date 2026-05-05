part of 'chat_context_sheet.dart';

extension _ChatContextPanelActionsPart on _ChatContextPanelState {
  Future<void> _loadModelInfo() async {
    try {
      final String model = await AISettingsService.instance.getModel();
      final int ctx = (await AIContextBudgets.forModelWithOverrides(
        model,
      )).promptCapTokens.clamp(256, 1 << 30).toInt();
      final int? out = ModelsDevModelLimits.outputTokens(model);
      if (!mounted) return;
      _panelSetState(() {
        _activeModel = model;
        _activeModelContextTokens = ctx;
        _activeModelOutputTokens = out;
      });
    } catch (_) {}
  }

  Locale _effectivePromptLocale() {
    final Locale? configured = LocaleService.instance.locale;
    final Locale device = WidgetsBinding.instance.platformDispatcher.locale;
    final Locale base = configured ?? device;
    final String code = base.languageCode.toLowerCase();
    if (code.startsWith('zh')) return const Locale('zh');
    if (code.startsWith('ja')) return const Locale('ja');
    if (code.startsWith('ko')) return const Locale('ko');
    return const Locale('en');
  }

  String _systemPromptForLocale() {
    final Locale locale = _effectivePromptLocale();
    return lookupAppLocalizations(locale).aiSystemPromptLanguagePolicy;
  }

  int _promptCapTokensForUi() {
    final String model = _activeModel.trim();
    return _activeModelContextTokens ??
        AIContextBudgets.forModel(model).promptCapTokens;
  }

  int _approxToolSchemaTokens(List<Map<String, dynamic>> tools) {
    if (tools.isEmpty) return 0;
    try {
      return PromptBudget.approxTokensForText(jsonEncode(tools));
    } catch (_) {
      return PromptBudget.approxTokensForText('$tools');
    }
  }

  String _buildToolUsageInstructionForUi({
    required List<Map<String, dynamic>> tools,
  }) {
    if (tools.isEmpty) return '';

    final Locale locale = _effectivePromptLocale();
    final bool isZh = locale.languageCode.toLowerCase().startsWith('zh');
    String loc(String zh, String en) => isZh ? zh : en;

    final Set<String> names = <String>{};
    for (final Map<String, dynamic> t in tools) {
      final Object? fn0 = t['function'];
      if (fn0 is! Map) continue;
      final Map fn = fn0;
      final String name = (fn['name'] ?? '').toString().trim();
      if (name.isNotEmpty) names.add(name);
    }

    final StringBuffer sb = StringBuffer();
    sb.writeln(
      loc(
        '已启用工具调用。需要时可调用工具；不要编造工具结果。',
        'Tool calling is enabled. You MAY call tools when needed; do NOT fabricate tool results.',
      ),
    );
    sb.writeln(loc('可用工具：', 'Available tools:'));
    for (final Map<String, dynamic> t in tools) {
      final Object? fn0 = t['function'];
      if (fn0 is! Map) continue;
      final Map fn = fn0;
      final String name = (fn['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final String desc = (fn['description'] ?? '').toString().trim();
      sb.writeln(desc.isEmpty ? '- $name' : '- $name: $desc');
    }
    sb.writeln(loc('规则：', 'Rules:'));
    sb.writeln(loc('- 不要编造工具结果。', '- Do NOT fabricate tool results.'));
    sb.writeln(
      loc(
        '- 回答若涉及用户本地记录（聊天/转账/截图内容等），请在关键结论处附上证据引用 [evidence: X]（X 必须是工具返回或上下文提供的截图 filename）。',
        '- If your answer relies on the user’s local records, attach evidence references [evidence: X] for key claims (X must be a screenshot filename from tool outputs or provided context).',
      ),
    );

    final bool hasRetrievalTools =
        names.contains('search_segments') ||
        names.contains('search_screenshots_ocr') ||
        names.contains('search_ai_image_meta');
    if (hasRetrievalTools) {
      sb.writeln(
        loc(
          '- 对于“查找/定位用户历史记录”的问题，优先调用检索类工具，不要猜。',
          '- For lookup tasks, prefer calling retrieval tools first. Do not guess.',
        ),
      );
    }

    return sb.toString().trim();
  }

  Future<_PromptUsageEstimate> _estimateCurrentPromptUsage(
    ChatContextSnapshot s,
  ) async {
    final String model = _activeModel.trim().isNotEmpty
        ? _activeModel.trim()
        : (await AISettingsService.instance.getModel()).trim();
    final AIContextBudgets budgets =
        await AIContextBudgets.forModelWithOverrides(model);
    final int capTokens = budgets.promptCapTokens;
    final int? outTokens = ModelsDevModelLimits.outputTokens(model);

    int msgTokens(String role, String content) {
      return PromptBudget.approxTokensForMessageJson(
        AIMessage(role: role, content: content),
      );
    }

    final Map<String, int> parts = <String, int>{};

    // System prompt is always included.
    final String systemPrompt = _systemPromptForLocale().trim();
    final int systemTokens = systemPrompt.isEmpty
        ? 0
        : msgTokens('system', systemPrompt);
    if (systemTokens > 0)
      parts[PromptTokenPart.systemPrompt.key] = systemTokens;

    // Tool schema is sent out-of-band (not in messages) for tool-enabled calls.
    // We approximate using default chat tools for a stable "global usage" view.
    final List<Map<String, dynamic>> tools = AIChatService.defaultChatTools();
    final int toolSchemaTokens = _approxToolSchemaTokens(tools);
    if (toolSchemaTokens > 0)
      parts[PromptTokenPart.toolSchema.key] = toolSchemaTokens;

    // Tool-usage instruction is a system message when tools are enabled.
    final String toolInstruction = _buildToolUsageInstructionForUi(
      tools: tools,
    );
    final int toolInstructionTokens = toolInstruction.trim().isEmpty
        ? 0
        : msgTokens('system', toolInstruction.trim());
    if (toolInstructionTokens > 0) {
      parts[PromptTokenPart.toolInstruction.key] = toolInstructionTokens;
    }

    // Conversation context (summary + tool memory) is injected as a system message.
    String ctxMsg = '';
    try {
      ctxMsg = await ChatContextService.instance.buildSystemContextMessage(
        cid: s.cid,
      );
    } catch (_) {}
    final int ctxTokens = ctxMsg.trim().isEmpty
        ? 0
        : msgTokens('system', ctxMsg.trim());
    if (ctxTokens > 0)
      parts[PromptTokenPart.conversationContext.key] = ctxTokens;

    // Use append-only transcript as primary history source; fall back to UI tail.
    List<AIMessage> history = const <AIMessage>[];
    try {
      history = await ChatContextService.instance.loadRecentMessagesForPrompt(
        cid: s.cid,
        maxTokens: budgets.historyPromptTokens,
      );
    } catch (_) {}
    List<AIMessage> uiHistory = const <AIMessage>[];
    try {
      uiHistory = await AISettingsService.instance.getChatHistory();
    } catch (_) {}

    List<AIMessage> filterHistory(List<AIMessage> src) {
      return src
          .where(
            (m) =>
                (m.role == 'user' ||
                    m.role == 'assistant' ||
                    m.role == 'tool') &&
                m.content.trim().isNotEmpty,
          )
          .toList();
    }

    final List<AIMessage> merged = <AIMessage>[...filterHistory(history)];
    if (merged.isEmpty) {
      merged.addAll(filterHistory(uiHistory));
    } else {
      final List<AIMessage> tail = filterHistory(uiHistory);
      final int take = tail.length.clamp(0, 6);
      final List<AIMessage> lastFew = take == 0
          ? const <AIMessage>[]
          : tail.sublist(tail.length - take);

      String sig(AIMessage m) => '${m.role}\n${m.content}';
      final int recentWindow = merged.length.clamp(0, 12);
      final Set<String> recentSigs = <String>{
        for (final m in merged.sublist(merged.length - recentWindow)) sig(m),
      };
      for (final AIMessage m in lastFew) {
        final String s0 = sig(m);
        if (recentSigs.contains(s0)) continue;
        merged.add(AIMessage(role: m.role, content: m.content));
        recentSigs.add(s0);
      }
    }

    final List<AIMessage> trimmedHistory = merged.isEmpty
        ? const <AIMessage>[]
        : PromptBudget.keepTailUnderTokenBudget(
            merged,
            maxTokens: budgets.historyPromptTokens,
          );

    int historyUser = 0;
    int historyAssistant = 0;
    int historyTool = 0;
    for (final AIMessage m in trimmedHistory) {
      final int t = msgTokens(m.role, m.content);
      if (m.role == 'assistant') {
        historyAssistant += t;
      } else if (m.role == 'tool') {
        historyTool += t;
      } else {
        historyUser += t;
      }
    }
    if (historyUser > 0) parts[PromptTokenPart.historyUser.key] = historyUser;
    if (historyAssistant > 0) {
      parts[PromptTokenPart.historyAssistant.key] = historyAssistant;
    }
    if (historyTool > 0) parts[PromptTokenPart.historyTool.key] = historyTool;

    final int total = parts.values.fold(0, (a, b) => a + b);
    return _PromptUsageEstimate(
      model: model,
      contextCapTokens: capTokens,
      outputCapTokens: outTokens,
      totalTokens: total,
      parts: parts,
    );
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

  String _sanitizeCidForFileName(String cid) {
    final String t = cid.trim();
    if (t.isEmpty) return 'conversation';
    final String safe = t.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    if (safe.isEmpty) return 'conversation';
    return safe.length <= 64 ? safe : safe.substring(0, 64);
  }

  String _formatRoleForExport(String role) {
    final String v = role.trim().toLowerCase();
    if (v == 'assistant') return 'Assistant';
    return 'User';
  }

  String _buildConversationExportText({
    required ChatContextSnapshot snapshot,
    required List<AIMessage> messages,
    required List<ChatContextEvent> trimEvents,
    required DateTime exportedAt,
  }) {
    final String summary = snapshot.summary.trim();
    final String ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(exportedAt);

    final StringBuffer sb = StringBuffer();
    sb.writeln('=== Chat Transcript Export ===');
    sb.writeln('${ChatContextSheet._loc(context, '导出时间', 'Export time')}: $ts');
    sb.writeln('conversation_id: ${snapshot.cid}');
    sb.writeln(
      '${ChatContextSheet._loc(context, '消息数量', 'Message count')}: ${messages.length}',
    );
    sb.writeln(
      '${ChatContextSheet._loc(context, '压缩次数', 'Compactions')}: ${snapshot.compactionCount}',
    );

    if (summary.isNotEmpty) {
      sb.writeln();
      sb.writeln(
        '--- ${ChatContextSheet._loc(context, '对话摘要（压缩）', 'Conversation summary (compacted)')} ---',
      );
      sb.writeln(summary);
    }

    if (messages.isNotEmpty) {
      sb.writeln();
      sb.writeln(
        '--- ${ChatContextSheet._loc(context, '逐条对话', 'Messages')} ---',
      );
      for (int i = 0; i < messages.length; i++) {
        final AIMessage m = messages[i];
        final String index = (i + 1).toString().padLeft(4, '0');
        final String lineTs = DateFormat(
          'yyyy-MM-dd HH:mm:ss',
        ).format(m.createdAt.toLocal());
        sb.writeln('[$index] $lineTs [${_formatRoleForExport(m.role)}]');
        sb.writeln(m.content);
        if (i < messages.length - 1) sb.writeln();
      }
    }

    if (trimEvents.isNotEmpty) {
      sb.writeln();
      sb.writeln('--- Context Trim Events ---');
      for (final ChatContextEvent e in trimEvents) {
        final String tsLine = DateFormat(
          'yyyy-MM-dd HH:mm:ss',
        ).format(DateTime.fromMillisecondsSinceEpoch(e.createdAtMs).toLocal());
        final String stage = e.stage.isEmpty ? '-' : e.stage;
        final String kind = e.kind.isEmpty ? '-' : e.kind;
        final String reason = e.reason.isEmpty ? '-' : e.reason;
        sb.writeln(
          '[$tsLine] stage=$stage kind=$kind tokens=${e.beforeTokens}->${e.afterTokens} dropped=${e.droppedTokens} reason=$reason',
        );
      }
    }

    return sb.toString().trimRight();
  }

  Future<_ConversationExportPayload?>
  _prepareConversationExportPayload() async {
    final ChatContextSnapshot snapshot = await ChatContextService.instance
        .getSnapshot();
    final List<AIMessage> messages = await ChatContextService.instance
        .loadMessagesForExport(cid: snapshot.cid);
    final List<ChatContextEvent> trimEvents = await ChatContextService.instance
        .listRecentContextEvents(
          cid: snapshot.cid,
          type: 'prompt_trim',
          limit: _ChatContextPanelState._trimEventsDefaultLimit,
        );
    final String summary = snapshot.summary.trim();
    if (summary.isEmpty && messages.isEmpty && trimEvents.isEmpty) return null;
    final String text = _buildConversationExportText(
      snapshot: snapshot,
      messages: messages,
      trimEvents: trimEvents,
      exportedAt: DateTime.now(),
    );
    if (text.trim().isEmpty) return null;
    return _ConversationExportPayload(
      snapshot: snapshot,
      messages: messages,
      trimEvents: trimEvents,
      text: text,
    );
  }

  String _trimEventTitle(ChatContextEvent event) {
    final String stage = event.stage.isEmpty ? 'chat' : event.stage;
    final String kind = event.kind.isEmpty ? 'trim' : event.kind;
    return '$stage · $kind';
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

  String _trimEventRawLine(ChatContextEvent event) {
    final NumberFormat nf = NumberFormat.decimalPattern();
    final String time = ChatContextSheet._fmtTs(event.createdAtMs);
    final String stage = event.stage.isEmpty ? '-' : event.stage;
    final String kind = event.kind.isEmpty ? '-' : event.kind;
    final String reason = event.reason.isEmpty ? '-' : event.reason;
    return '[$time] stage=$stage kind=$kind tokens=${nf.format(event.beforeTokens)}->${nf.format(event.afterTokens)} dropped=${nf.format(event.droppedTokens)} reason=$reason';
  }

  Future<void> _copyTrimEvent(ChatContextEvent event) async {
    await Clipboard.setData(ClipboardData(text: _trimEventRawLine(event)));
    if (!mounted) return;
    UINotifier.success(
      context,
      ChatContextSheet._loc(context, '已复制事件', 'Event copied'),
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
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.4)),
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
              '显示最近 ${shown.length} 条（默认 50，最多 200）',
              'Showing latest ${shown.length} events (default 50, max 200)',
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
                    color: theme.colorScheme.outline.withOpacity(0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _trimEventTitle(e),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: ChatContextSheet._loc(
                            context,
                            '复制事件',
                            'Copy event',
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _copyTrimEvent(e),
                        ),
                      ],
                    ),
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

  Future<void> _copyConversationTranscript() async {
    if (_busy) return;
    _panelSetState(() => _busy = true);
    try {
      final _ConversationExportPayload? payload =
          await _prepareConversationExportPayload();
      if (payload == null) {
        if (!mounted) return;
        UINotifier.success(
          context,
          ChatContextSheet._loc(context, '暂无可导出内容', 'No exportable content.'),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: payload.text));
      if (!mounted) return;
      UINotifier.success(
        context,
        ChatContextSheet._loc(context, '已复制当前会话', 'Conversation copied'),
      );
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        ChatContextSheet._loc(context, '复制失败：$e', 'Copy failed: $e'),
      );
    } finally {
      if (mounted) _panelSetState(() => _busy = false);
    }
  }

  Future<void> _saveConversationTranscriptToFile() async {
    if (_busy) return;
    _panelSetState(() => _busy = true);
    try {
      final _ConversationExportPayload? payload =
          await _prepareConversationExportPayload();
      if (payload == null) {
        if (!mounted) return;
        UINotifier.success(
          context,
          ChatContextSheet._loc(context, '暂无可导出内容', 'No exportable content.'),
        );
        return;
      }

      String? baseDirPath;
      try {
        baseDirPath = await FlutterLogger.getTodayLogsDir();
      } catch (_) {
        baseDirPath = null;
      }

      Directory baseDir = Directory.systemTemp;
      if (baseDirPath != null && baseDirPath.trim().isNotEmpty) {
        baseDir = Directory(baseDirPath.trim());
      }

      final String sep = Platform.pathSeparator;
      final Directory outDir = Directory(
        baseDir.path + sep + 'ai_chat_exports',
      );
      await outDir.create(recursive: true);

      final String ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final String fileName =
          'chat_transcript_${_sanitizeCidForFileName(payload.snapshot.cid)}_$ts.txt';
      final File f = File(outDir.path + sep + fileName);
      await f.writeAsString(payload.text + '\n', flush: true);

      try {
        await Clipboard.setData(ClipboardData(text: f.path));
      } catch (_) {}

      if (!mounted) return;
      UINotifier.success(
        context,
        ChatContextSheet._loc(context, '已保存到：${f.path}', 'Saved to: ${f.path}'),
      );
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        ChatContextSheet._loc(context, '保存失败：$e', 'Save failed: $e'),
      );
    } finally {
      if (mounted) _panelSetState(() => _busy = false);
    }
  }

  Future<void> _onExportActionSelected(_ConversationExportAction action) async {
    switch (action) {
      case _ConversationExportAction.copy:
        await _copyConversationTranscript();
        break;
      case _ConversationExportAction.save:
        await _saveConversationTranscriptToFile();
        break;
    }
  }

  Future<void> _editModelPromptCapDialog(
    BuildContext context, {
    required String model,
    required int fallbackPromptCapTokens,
  }) async {
    final String m = model.trim();
    if (m.isEmpty) return;

    final int? override0 = await AIModelPromptCapsService.instance.getOverride(
      m,
    );
    final bool hasOverride = override0 != null;
    final int cap0 = (override0 ?? fallbackPromptCapTokens)
        .clamp(256, 1 << 30)
        .toInt();

    final TextEditingController ctrl = TextEditingController(text: '$cap0');

    // Keep the dialog open on invalid input.
    Future<void> save(BuildContext ctx) async {
      final int? v = int.tryParse(ctrl.text.trim());
      if (v == null) {
        UINotifier.error(
          context,
          ChatContextSheet._loc(context, '请输入数字', 'Please enter a number.'),
        );
        return;
      }
      if (v < 256) {
        UINotifier.error(
          context,
          ChatContextSheet._loc(
            context,
            '值过小（至少 256）',
            'Value too small (min 256).',
          ),
        );
        return;
      }

      await AIModelPromptCapsService.instance.setOverride(m, v);
      if (mounted) _panelSetState(() {});
      if (!ctx.mounted) return;
      Navigator.of(ctx).pop();
      UINotifier.success(
        context,
        ChatContextSheet._loc(context, '已保存', 'Saved'),
      );
    }

    Future<void> clear(BuildContext ctx) async {
      await AIModelPromptCapsService.instance.clearOverride(m);
      if (mounted) _panelSetState(() {});
      if (!ctx.mounted) return;
      Navigator.of(ctx).pop();
      UINotifier.success(
        context,
        ChatContextSheet._loc(context, '已清除', 'Cleared'),
      );
    }

    await showUIDialog<void>(
      context: context,
      title: ChatContextSheet._loc(
        context,
        '设置模型最大 token',
        'Set model max tokens',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ChatContextSheet._loc(context, '模型', 'Model'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            m,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppTheme.spacing3),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: ChatContextSheet._loc(
                context,
                '最大 token（prompt）',
                'Max tokens (prompt)',
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            hasOverride
                ? ChatContextSheet._loc(
                    context,
                    '当前为自定义值（可清除恢复默认推断）',
                    'Custom value is set (you can clear to restore defaults).',
                  )
                : ChatContextSheet._loc(
                    context,
                    '未设置自定义值（当前为默认推断）',
                    'No custom value (using defaults).',
                  ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: <UIDialogAction<void>>[
        UIDialogAction<void>(
          text: ChatContextSheet._loc(context, '取消', 'Cancel'),
        ),
        if (hasOverride)
          UIDialogAction<void>(
            text: ChatContextSheet._loc(context, '清除', 'Clear'),
            style: UIDialogActionStyle.destructive,
            closeOnPress: false,
            onPressed: clear,
          ),
        UIDialogAction<void>(
          text: ChatContextSheet._loc(context, '保存', 'Save'),
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: save,
        ),
      ],
    );
  }

  Future<void> _run({
    required Future<void> Function() action,
    required String okTextZh,
    required String okTextEn,
  }) async {
    if (_busy) return;
    _panelSetState(() => _busy = true);
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
      if (mounted) _panelSetState(() => _busy = false);
      _reload();
    }
  }
}
