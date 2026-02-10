part of 'ai_chat_service.dart';

class _ToolUiThinkingPersister {
  _ToolUiThinkingPersister({
    required this.cid,
    required this.displayUserMessage,
    required this.assistantCreatedAtMs,
    required this.toolsTitle,
    required this.settings,
    String? seededUiThinkingJson,
  }) : uiThinkingJson = ((seededUiThinkingJson ?? '').trim().isNotEmpty)
           ? seededUiThinkingJson!.trim()
           : null;

  final String cid;
  final String displayUserMessage;
  final int assistantCreatedAtMs;
  final String toolsTitle;
  final AISettingsService settings;

  String? uiThinkingJson;

  final List<Map<String, dynamic>> _payloads = <Map<String, dynamic>>[];
  Timer? _debounce;
  Future<void> _flushChain = Future<void>.value();
  bool _fallbackInserted = false;
  bool _disposed = false;

  Map<String, dynamic>? _tryDecodePayload(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(t);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  void handle(AIStreamEvent event) {
    if (_disposed) return;
    if (event.kind != 'ui') return;
    final Map<String, dynamic>? payload = _tryDecodePayload(event.data);
    if (payload == null) return;
    final String type = (payload['type'] ?? '').toString().trim();
    if (type != 'tool_batch_begin' && type != 'tool_call_end') return;

    _payloads.add(payload);
    uiThinkingJson = patchUiThinkingJsonWithToolUiEvent(
      uiThinkingJson,
      payload,
      assistantCreatedAtMs: assistantCreatedAtMs,
      toolsTitle: toolsTitle,
    );
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _debounce?.cancel();
    // Keep this fairly low-frequency to avoid excessive DB churn while still
    // making the tool timeline resilient to conversation switches.
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(flushNow());
    });
  }

  Future<void> flushNow() {
    _debounce?.cancel();
    _debounce = null;
    if (_disposed) return Future<void>.value();
    if (_payloads.isEmpty) return Future<void>.value();

    final Future<void> next = _flushChain.then((_) async {
      await _flushOnce();
    });
    _flushChain = next.catchError((_) {});
    return _flushChain;
  }

  Future<void> _ensurePlaceholderExists(String uiJson) async {
    final String cidTrim = cid.trim();
    if (cidTrim.isEmpty) return;
    final List<AIMessage> existing = await settings.getChatHistoryByCid(
      cidTrim,
    );
    final List<AIMessage> out = List<AIMessage>.from(existing);

    int assistantIdx = -1;
    for (int i = out.length - 1; i >= 0; i--) {
      final AIMessage m = out[i];
      if (m.role != 'assistant') continue;
      if (m.createdAt.millisecondsSinceEpoch == assistantCreatedAtMs) {
        assistantIdx = i;
        break;
      }
    }

    if (assistantIdx >= 0) {
      final AIMessage base = out[assistantIdx];
      out[assistantIdx] = AIMessage(
        role: base.role,
        content: base.content,
        createdAt: base.createdAt,
        reasoningContent: base.reasoningContent,
        reasoningDuration: base.reasoningDuration,
        uiThinkingJson: uiJson,
      );
      await settings.saveChatHistoryByCid(cidTrim, out);
      return;
    }

    // Fallback: insert after the matching user message if present.
    final String userTrim = displayUserMessage.trim();
    int userIdx = -1;
    for (int i = out.length - 1; i >= 0; i--) {
      final AIMessage m = out[i];
      if (m.role == 'user' && m.content.trim() == userTrim) {
        userIdx = i;
        break;
      }
    }

    final AIMessage placeholder = AIMessage(
      role: 'assistant',
      content: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(assistantCreatedAtMs),
      uiThinkingJson: uiJson,
    );

    if (userIdx >= 0) {
      out.insert(userIdx + 1, placeholder);
    } else {
      if (userTrim.isNotEmpty) {
        out.add(AIMessage(role: 'user', content: userTrim));
      }
      out.add(placeholder);
    }
    await settings.saveChatHistoryByCid(cidTrim, out);
  }

  Future<void> _flushOnce() async {
    final String cidTrim = cid.trim();
    if (cidTrim.isEmpty || assistantCreatedAtMs <= 0) return;

    final String? base = await ScreenshotDatabase.instance
        .getAiAssistantUiThinkingJson(cidTrim, assistantCreatedAtMs);
    String? next = base;
    for (final Map<String, dynamic> p in _payloads) {
      next = patchUiThinkingJsonWithToolUiEvent(
        next,
        p,
        assistantCreatedAtMs: assistantCreatedAtMs,
        toolsTitle: toolsTitle,
      );
    }
    final String t = (next ?? '').trim();
    if (t.isEmpty) return;

    int updated = await ScreenshotDatabase.instance
        .updateAiAssistantUiThinkingJson(cidTrim, assistantCreatedAtMs, t);

    if (updated <= 0 && !_fallbackInserted) {
      _fallbackInserted = true;
      try {
        await _ensurePlaceholderExists(t);
      } catch (_) {}
      updated = await ScreenshotDatabase.instance
          .updateAiAssistantUiThinkingJson(cidTrim, assistantCreatedAtMs, t);
    }

    if (updated > 0) {
      uiThinkingJson = t;
      settings.notifyChatHistoryChanged(cidTrim);
    }
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
  }
}

extension AIChatServiceSendExt on AIChatService {
  static const int _minHistoryReserveTokens = 512;
  static const int _summaryAppsPromptMaxItems = 60;

  int _approxMsgTokens(String role, String content) {
    return PromptBudget.approxTokensForMessageJson(
      AIMessage(role: role, content: content),
    );
  }

  bool _retrievalPayloadHasPagingSignal(Map<String, dynamic> payload) {
    final dynamic paging = payload['paging'];
    if (paging is Map && paging.isNotEmpty) return true;

    final dynamic span = payload['time_span_limit'];
    if (span is Map && _toBool(span['clamped'])) return true;

    final dynamic guard = payload['time_guard'];
    if (guard is Map && _toBool(guard['clamped'])) return true;

    final dynamic warnings = payload['warnings'];
    if (warnings is List) {
      for (final dynamic w in warnings) {
        final String s = w.toString().toLowerCase();
        if (s.contains('paging.prev') ||
            s.contains('paging.next') ||
            s.contains('clamped') ||
            s.contains('裁剪')) {
          return true;
        }
      }
    }
    return false;
  }

  bool debugRetrievalPayloadHasPagingSignal(Map<String, dynamic> payload) {
    return _retrievalPayloadHasPagingSignal(payload);
  }

  bool _shouldTryStrictFullContext({
    required String context,
    required bool persistHistory,
    required bool includeHistory,
  }) {
    return context == 'chat' && persistHistory && includeHistory;
  }

  Future<List<AIMessage>> _loadStrictRawHistoryForChat(String cid) async {
    final String resolvedCid = cid.trim();
    if (resolvedCid.isEmpty) return const <AIMessage>[];
    try {
      return await _chatContext.loadRawTranscriptForPrompt(
        cid: resolvedCid,
        maxTokens: 0,
      );
    } catch (_) {
      return const <AIMessage>[];
    }
  }

  Future<String> _buildSummaryAppsContextMessage() async {
    try {
      final List<String> raw = await ScreenshotDatabase.instance
          .listAppDisplayNamesWithSegmentSummaries(limit: 200);
      final List<String> names = raw
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      if (names.isEmpty) return '';
      names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final List<String> picked = names
          .take(_summaryAppsPromptMaxItems)
          .toList(growable: false);
      final int omitted = (names.length - picked.length).clamp(0, 1 << 30);
      final String listText = _isZhLocale()
          ? picked.join('、')
          : picked.join(', ');
      if (_isZhLocale()) {
        return [
          '数据源提示（动态总结）：以下应用存在可检索的动态总结数据（应用显示名）：$listText'
              '${omitted > 0 ? ' 等（共 ${names.length} 个）' : ''}。',
          '未在此列表中的应用暂不作为“动态总结”数据源。',
        ].join('\n');
      }
      return [
        'Dynamic-summary data-source hint: the following apps currently have retrievable dynamic-summary data (display names): $listText'
            '${omitted > 0 ? ' (total ${names.length})' : ''}.',
        'Apps not in this list are currently not considered dynamic-summary data sources.',
      ].join('\n');
    } catch (_) {
      return '';
    }
  }

  String _mergePromptUsageIntoBreakdownJson({
    required String baseBreakdownJson,
    required int promptEstBefore,
    required int promptEstSent,
    int? usagePromptTokens,
    int? usageCompletionTokens,
    int? usageTotalTokens,
    required bool strictFullAttempted,
    required bool fallbackTriggered,
  }) {
    final Map<String, dynamic> payload = <String, dynamic>{};
    final String raw = baseBreakdownJson.trim();
    if (raw.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map) {
          payload.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    payload['prompt_est_before'] = promptEstBefore;
    payload['prompt_est_sent'] = promptEstSent;
    if (usagePromptTokens != null) {
      payload['usage_prompt_tokens'] = usagePromptTokens;
    }
    if (usageCompletionTokens != null) {
      payload['usage_completion_tokens'] = usageCompletionTokens;
    }
    if (usageTotalTokens != null) {
      payload['usage_total_tokens'] = usageTotalTokens;
    }
    payload['strict_full_attempted'] = strictFullAttempted;
    payload['fallback_triggered'] = fallbackTriggered;
    payload['source'] =
        (usagePromptTokens != null ||
            usageCompletionTokens != null ||
            usageTotalTokens != null)
        ? 'usage'
        : 'estimate';
    if (!payload.containsKey('completion_estimate')) {
      payload['completion_estimate'] = 0;
    }
    if (!payload.containsKey('total_estimate')) {
      payload['total_estimate'] = promptEstSent;
    }
    try {
      return jsonEncode(payload);
    } catch (_) {
      return raw;
    }
  }

  void _recordPromptUsageForCall({
    required String cid,
    required String model,
    required int promptEstBefore,
    required int promptEstSent,
    required AIGatewayResult result,
    required bool isToolLoop,
    required bool includeHistory,
    required int toolsCount,
    required bool strictFullAttempted,
    required bool fallbackTriggered,
    required String breakdownJson,
  }) {
    final String resolvedCid = cid.trim();
    if (resolvedCid.isEmpty) return;

    final int snapshotPrompt = result.usagePromptTokens ?? promptEstSent;
    final String mergedBreakdown = _mergePromptUsageIntoBreakdownJson(
      baseBreakdownJson: breakdownJson,
      promptEstBefore: promptEstBefore,
      promptEstSent: promptEstSent,
      usagePromptTokens: result.usagePromptTokens,
      usageCompletionTokens: result.usageCompletionTokens,
      usageTotalTokens: result.usageTotalTokens,
      strictFullAttempted: strictFullAttempted,
      fallbackTriggered: fallbackTriggered,
    );

    unawaited(() async {
      try {
        await _chatContext.recordPromptTokens(
          cid: resolvedCid,
          tokensApprox: snapshotPrompt,
          breakdownJson: mergedBreakdown.trim().isEmpty
              ? null
              : mergedBreakdown,
        );
      } catch (_) {}
      try {
        await _chatContext.recordPromptUsageEvent(
          cid: resolvedCid,
          model: model,
          promptEstBefore: promptEstBefore,
          promptEstSent: promptEstSent,
          usagePromptTokens: result.usagePromptTokens,
          usageCompletionTokens: result.usageCompletionTokens,
          usageTotalTokens: result.usageTotalTokens,
          isToolLoop: isToolLoop,
          includeHistory: includeHistory,
          toolsCount: toolsCount,
          strictFullAttempted: strictFullAttempted,
          fallbackTriggered: fallbackTriggered,
          breakdownJson: mergedBreakdown,
        );
      } catch (_) {}
      try {
        _settings.notifyContextChanged('chat:prompt_tokens');
      } catch (_) {}
    }());
  }

  Future<void> _logPromptTrimEvent(
    String cid, {
    required String stage,
    required String kind,
    required int beforeTokens,
    required int afterTokens,
    int droppedMessages = 0,
    int droppedChunks = 0,
    bool truncatedOldest = false,
    String reason = '',
    String model = '',
  }) async {
    if (cid.trim().isEmpty) return;
    await _chatContext.logPromptTrimEvent(
      cid: cid,
      stage: stage,
      kind: kind,
      beforeTokens: beforeTokens,
      afterTokens: afterTokens,
      droppedMessages: droppedMessages,
      droppedChunks: droppedChunks,
      truncatedOldest: truncatedOldest,
      reason: reason,
      model: model,
    );
  }

  Future<List<String>> _buildHistoryFirstExtras({
    required String cid,
    required String stage,
    required String model,
    required String systemPrompt,
    required String userMessage,
    required bool includeHistory,
    required int toolsSchemaTokens,
    required AIContextBudgets budgets,
    required String toolUsageInstruction,
    required String conversationContextMsg,
    required String atomicMemoryMsg,
    required List<String> extraSystemMessages,
  }) async {
    final List<String> extras = <String>[];
    final List<String> optional = <String>[];

    final String toolInst = toolUsageInstruction.trim();
    final String ctx = conversationContextMsg.trim();
    final String am = atomicMemoryMsg.trim();

    if (toolInst.isNotEmpty) extras.add(toolInst);

    if (ctx.isNotEmpty) optional.add(ctx);
    if (am.isNotEmpty) optional.add(am);
    for (final String s in extraSystemMessages) {
      final String t = s.trim();
      if (t.isNotEmpty) optional.add(t);
    }

    extras.addAll(optional);

    if (!includeHistory) return extras;

    int reserved = _approxReservedPromptTokens(
      systemPrompt: systemPrompt,
      extraSystemMessages: extras,
      userMessage: userMessage,
    );
    int historyBudget = _historyBudgetTokensForPrompt(
      budgets: budgets,
      reservedTokens: reserved,
      toolsSchemaTokens: toolsSchemaTokens,
    );
    if (historyBudget >= _minHistoryReserveTokens) return extras;

    int before =
        _approxMsgTokens('system', systemPrompt) +
        _approxMsgTokens('user', userMessage) +
        toolsSchemaTokens;
    for (final String s in extras) {
      before += _approxMsgTokens('system', s);
    }

    final List<String> kept = <String>[];
    if (toolInst.isNotEmpty) kept.add(toolInst);

    int droppedMessages = 0;
    for (final String s in optional) {
      final int nextReserved = _approxReservedPromptTokens(
        systemPrompt: systemPrompt,
        extraSystemMessages: <String>[...kept, s],
        userMessage: userMessage,
      );
      final int nextBudget = _historyBudgetTokensForPrompt(
        budgets: budgets,
        reservedTokens: nextReserved,
        toolsSchemaTokens: toolsSchemaTokens,
      );
      if (nextBudget >= _minHistoryReserveTokens) {
        kept.add(s);
      } else {
        droppedMessages += 1;
      }
    }

    int after =
        _approxMsgTokens('system', systemPrompt) +
        _approxMsgTokens('user', userMessage) +
        toolsSchemaTokens;
    for (final String s in kept) {
      after += _approxMsgTokens('system', s);
    }

    if (droppedMessages > 0 && after < before) {
      unawaited(
        _logPromptTrimEvent(
          cid,
          stage: stage,
          kind: 'extras_drop',
          beforeTokens: before,
          afterTokens: after,
          droppedMessages: droppedMessages,
          reason: 'reserve_history',
          model: model,
        ),
      );
    }

    reserved = _approxReservedPromptTokens(
      systemPrompt: systemPrompt,
      extraSystemMessages: kept,
      userMessage: userMessage,
    );
    historyBudget = _historyBudgetTokensForPrompt(
      budgets: budgets,
      reservedTokens: reserved,
      toolsSchemaTokens: toolsSchemaTokens,
    );
    if (historyBudget < 64) {
      unawaited(
        _chatContext.logContextEvent(
          cid: cid,
          type: 'prompt_trim',
          payload: <String, dynamic>{
            'stage': stage,
            'kind': 'history_starved',
            'before_tokens': before,
            'after_tokens': after,
            'dropped_tokens': (before - after).clamp(0, 1 << 62),
            'dropped_messages': droppedMessages,
            'dropped_chunks': 0,
            'truncated_oldest': false,
            'reason': 'minimal_budget',
            if (model.trim().isNotEmpty) 'model': model.trim(),
            'created_at_ms': DateTime.now().millisecondsSinceEpoch,
          },
        ),
      );
    }

    return kept;
  }

  List<AIMessage> _trimHistoryTailWithEvent({
    required String cid,
    required String stage,
    required String model,
    required List<AIMessage> history,
    required int maxTokens,
  }) {
    if (history.isEmpty) return history;

    final int beforeTokens = PromptBudget.approxTokensForMessagesJson(history);
    final List<AIMessage> trimmed = PromptBudget.keepTailUnderTokenBudget(
      history,
      maxTokens: maxTokens,
    );
    final int afterTokens = PromptBudget.approxTokensForMessagesJson(trimmed);

    if (cid.trim().isNotEmpty && afterTokens < beforeTokens) {
      final int droppedMessages = (history.length - trimmed.length)
          .clamp(0, 1 << 30)
          .toInt();
      bool truncatedOldest = false;
      if (trimmed.isNotEmpty && history.length >= trimmed.length) {
        final int srcStart = history.length - trimmed.length;
        final AIMessage oldestSource = history[srcStart];
        final AIMessage oldestKept = trimmed.first;
        truncatedOldest =
            oldestSource.role == oldestKept.role &&
            oldestSource.content != oldestKept.content;
      }
      unawaited(
        _logPromptTrimEvent(
          cid,
          stage: stage,
          kind: 'history_tail',
          beforeTokens: beforeTokens,
          afterTokens: afterTokens,
          droppedMessages: droppedMessages,
          truncatedOldest: truncatedOldest,
          reason: 'max_history_tokens',
          model: model,
        ),
      );
    }

    return trimmed;
  }

  int _approxReservedPromptTokens({
    required String systemPrompt,
    required List<String> extraSystemMessages,
    required String userMessage,
  }) {
    int total = 0;
    total += _approxMsgTokens('system', systemPrompt);
    for (final String s in extraSystemMessages) {
      final String t = s.trim();
      if (t.isEmpty) continue;
      total += _approxMsgTokens('system', t);
    }
    total += _approxMsgTokens('user', userMessage);
    return total;
  }

  int _historyBudgetTokensForPrompt({
    required AIContextBudgets budgets,
    required int reservedTokens,
    required int toolsSchemaTokens,
  }) {
    final int v =
        budgets.effectivePromptCapTokens - reservedTokens - toolsSchemaTokens;
    if (v <= 0) return 0;
    return v.clamp(0, budgets.effectivePromptCapTokens);
  }

  int _toolLoopBudgetTokensForPrompt({
    required AIContextBudgets budgets,
    required int toolsSchemaTokens,
  }) {
    final int v = budgets.effectivePromptCapTokens - toolsSchemaTokens;
    if (v <= 0) return 0;
    return v.clamp(0, budgets.effectivePromptCapTokens);
  }

  int _approxToolSchemaTokens(List<Map<String, dynamic>> tools) {
    if (tools.isEmpty) return 0;
    try {
      return PromptBudget.approxTokensForText(jsonEncode(tools));
    } catch (_) {
      return PromptBudget.approxTokensForText('$tools');
    }
  }

  String _buildPromptBreakdownJson({
    required String model,
    required String systemPrompt,
    required String userMessage,
    required List<AIMessage> history,
    required bool includeHistory,
    required List<Map<String, dynamic>> tools,
    String toolUsageInstruction = '',
    String conversationContextMsg = '',
    String atomicMemoryMsg = '',
    List<String> extraSystemMessages = const <String>[],
    int? historyMaxTokens,
  }) {
    int msgTokens(String role, String content) {
      return PromptBudget.approxTokensForMessageJson(
        AIMessage(role: role, content: content),
      );
    }

    final Map<String, int> parts = <String, int>{};

    final int systemTokens = msgTokens('system', systemPrompt);
    parts['system_prompt'] = systemTokens;

    int addExtra(String key, String raw) {
      final String t = raw.trim();
      if (t.isEmpty) return 0;
      final int v = msgTokens('system', t);
      parts[key] = (parts[key] ?? 0) + v;
      return v;
    }

    addExtra('tool_instruction', toolUsageInstruction);
    addExtra('conversation_context', conversationContextMsg);
    addExtra('atomic_memory', atomicMemoryMsg);
    for (final String s in extraSystemMessages) {
      addExtra('extra_system', s);
    }

    int historyUser = 0;
    int historyAssistant = 0;
    int historyTool = 0;
    if (includeHistory && history.isNotEmpty) {
      final int maxTokens =
          (historyMaxTokens ??
                  AIContextBudgets.forModelWithPeekOverride(
                    model,
                  ).historyPromptTokens)
              .clamp(0, 1 << 30);
      final List<AIMessage> trimmed = PromptBudget.keepTailUnderTokenBudget(
        history,
        maxTokens: maxTokens,
      );
      for (final AIMessage m in trimmed) {
        final int t = msgTokens(m.role, m.content);
        if (m.role == 'assistant') {
          historyAssistant += t;
        } else if (m.role == 'tool') {
          historyTool += t;
        } else {
          historyUser += t;
        }
      }
    }
    if (historyUser > 0) parts['history_user'] = historyUser;
    if (historyAssistant > 0) parts['history_assistant'] = historyAssistant;
    if (historyTool > 0) parts['history_tool'] = historyTool;

    final int userTokens = msgTokens('user', userMessage);
    parts['user_message'] = userTokens;

    final int toolsSchemaTokens = _approxToolSchemaTokens(tools);
    if (toolsSchemaTokens > 0) parts['tool_schema'] = toolsSchemaTokens;

    final int total = parts.values.fold(0, (a, b) => a + b);

    try {
      return jsonEncode(<String, dynamic>{
        'v': 1,
        'model': model,
        'total_tokens': total,
        'parts': parts,
        'tools_count': tools.length,
        'include_history': includeHistory,
      });
    } catch (_) {
      return '';
    }
  }

  bool _looksLikeToolUsageInstruction(String text) {
    final String t = text.trim();
    if (t.isEmpty) return false;
    final String lower = t.toLowerCase();
    // Heuristic: detect the common tool-instruction preface (zh/en).
    return lower.contains('tool calling is enabled') ||
        lower.contains('available tools:') ||
        t.contains('已启用工具调用') ||
        t.contains('可用工具：');
  }

  String _buildPromptBreakdownJsonFromMessages({
    required String model,
    required List<AIMessage> messages,
    required List<Map<String, dynamic>> tools,
  }) {
    int msgTokens(AIMessage m) => PromptBudget.approxTokensForMessageJson(m);

    final Map<String, int> parts = <String, int>{};

    final int toolsSchemaTokens = _approxToolSchemaTokens(tools);
    if (toolsSchemaTokens > 0) parts['tool_schema'] = toolsSchemaTokens;

    bool firstSystem = true;
    int lastUserIdx = -1;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'user') {
        lastUserIdx = i;
        break;
      }
    }

    for (int i = 0; i < messages.length; i++) {
      final AIMessage m = messages[i];
      final String role = m.role;
      final int t = msgTokens(m);
      if (t <= 0) continue;

      if (role == 'system') {
        if (firstSystem) {
          parts['system_prompt'] = (parts['system_prompt'] ?? 0) + t;
          firstSystem = false;
          continue;
        }
        final String content = m.content;
        final String trimmed = content.trim();
        if (trimmed.contains('<conversation_context>')) {
          parts['conversation_context'] =
              (parts['conversation_context'] ?? 0) + t;
        } else if (trimmed.contains('<atomic_memory>')) {
          parts['atomic_memory'] = (parts['atomic_memory'] ?? 0) + t;
        } else if (_looksLikeToolUsageInstruction(trimmed)) {
          parts['tool_instruction'] = (parts['tool_instruction'] ?? 0) + t;
        } else {
          parts['extra_system'] = (parts['extra_system'] ?? 0) + t;
        }
        continue;
      }

      if (role == 'user') {
        final String k = (i == lastUserIdx) ? 'user_message' : 'history_user';
        parts[k] = (parts[k] ?? 0) + t;
        continue;
      }

      if (role == 'assistant') {
        parts['history_assistant'] = (parts['history_assistant'] ?? 0) + t;
        continue;
      }

      if (role == 'tool') {
        parts['history_tool'] = (parts['history_tool'] ?? 0) + t;
        continue;
      }

      // Unknown role: keep it under "extra_system" so we don't drop tokens.
      parts['extra_system'] = (parts['extra_system'] ?? 0) + t;
    }

    final int total = parts.values.fold(0, (a, b) => a + b);

    try {
      return jsonEncode(<String, dynamic>{
        'v': 1,
        'model': model,
        'total_tokens': total,
        'parts': parts,
        'tools_count': tools.length,
        'include_history': true,
      });
    } catch (_) {
      return '';
    }
  }

  Future<AIMessage> sendMessage(String userMessage, {Duration? timeout}) async {
    try {
      await FlutterLogger.nativeInfo(
        'AI',
        'sendMessage begin len=${userMessage.length}',
      );
    } catch (_) {}

    final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
      context: 'chat',
    );
    final String modelForBudget = endpoints.isNotEmpty
        ? endpoints.first.model
        : (await _settings.getModel());
    final AIContextBudgets budgets =
        await AIContextBudgets.forModelWithOverrides(modelForBudget);
    final String cid = await _settings.getActiveConversationCid();
    final List<AIMessage> history = await _settings.getChatHistoryByCid(cid);
    final bool strictFullAttempted = _shouldTryStrictFullContext(
      context: 'chat',
      persistHistory: true,
      includeHistory: true,
    );
    bool fallbackTriggered = false;
    final List<AIMessage> strictRawHistory = strictFullAttempted
        ? await _loadStrictRawHistoryForChat(cid)
        : const <AIMessage>[];
    // Best-effort bootstrap: seed append-only transcript from existing tail.
    try {
      await _chatContext.seedFromChatHistoryIfEmpty(cid: cid, history: history);
    } catch (_) {}

    final String systemPrompt = _systemPromptForLocale();
    List<String> extras = <String>[];
    String ctxMsg = '';
    try {
      ctxMsg = await _chatContext.buildSystemContextMessage(cid: cid);
    } catch (_) {}
    String amMsg = '';
    try {
      amMsg = await AtomicMemoryService.instance
          .buildAtomicMemoryContextMessage(cid: cid, query: userMessage.trim());
    } catch (_) {}
    String summaryAppsMsg = '';
    try {
      summaryAppsMsg = await _buildSummaryAppsContextMessage();
    } catch (_) {}

    extras = await _buildHistoryFirstExtras(
      cid: cid,
      stage: 'chat_setup',
      model: modelForBudget,
      systemPrompt: systemPrompt,
      userMessage: userMessage,
      includeHistory: true,
      toolsSchemaTokens: 0,
      budgets: budgets,
      toolUsageInstruction: '',
      conversationContextMsg: ctxMsg,
      atomicMemoryMsg: amMsg,
      extraSystemMessages: <String>[
        if (summaryAppsMsg.trim().isNotEmpty) summaryAppsMsg,
      ],
    );

    // Codex-style dynamic history budget: keep as much history as fits after
    // accounting for system/extras/user (+ tool schema, if any).
    const int toolsSchemaTokens = 0;
    int reservedTokens = _approxReservedPromptTokens(
      systemPrompt: systemPrompt,
      extraSystemMessages: extras,
      userMessage: userMessage,
    );
    int historyMaxTokens = _historyBudgetTokensForPrompt(
      budgets: budgets,
      reservedTokens: reservedTokens,
      toolsSchemaTokens: toolsSchemaTokens,
    );

    // Prefer strict raw transcript first (chat-only), then fallback to legacy.
    List<AIMessage> requestHistory = strictRawHistory.isNotEmpty
        ? strictRawHistory
        : history;
    if (strictFullAttempted && strictRawHistory.isNotEmpty) {
      final int strictPromptTokens =
          toolsSchemaTokens +
          PromptBudget.approxTokensForMessagesJson(
            _composeMessages(
              systemMessage: systemPrompt,
              history: requestHistory,
              userMessage: userMessage,
              extraSystemMessages: extras,
              includeHistory: true,
              historyMaxTokens: 1 << 30,
            ),
          );
      if (strictPromptTokens > budgets.effectivePromptCapTokens) {
        fallbackTriggered = true;
      }
    }
    if (historyMaxTokens > 0 && (!strictFullAttempted || fallbackTriggered)) {
      try {
        final List<AIMessage> full = await _chatContext
            .loadRecentMessagesForPrompt(cid: cid, maxTokens: historyMaxTokens);
        if (full.isNotEmpty) requestHistory = full;
      } catch (_) {}
    }

    final int promptEstBefore =
        toolsSchemaTokens +
        PromptBudget.approxTokensForMessagesJson(
          _composeMessages(
            systemMessage: systemPrompt,
            history: requestHistory,
            userMessage: userMessage,
            extraSystemMessages: extras,
            includeHistory: true,
            historyMaxTokens: 1 << 30,
          ),
        );
    List<AIMessage> requestMessages = _composeMessages(
      systemMessage: systemPrompt,
      history: _trimHistoryTailWithEvent(
        cid: cid,
        stage: 'chat_history_tail_setup',
        model: modelForBudget,
        history: requestHistory,
        maxTokens: (strictFullAttempted && !fallbackTriggered)
            ? (1 << 30)
            : historyMaxTokens,
      ),
      userMessage: userMessage,
      extraSystemMessages: extras,
      historyMaxTokens: (strictFullAttempted && !fallbackTriggered)
          ? (1 << 30)
          : historyMaxTokens,
    );

    // Codex-style: if we are close to the window, compact first, then retry once.
    int tokensApprox =
        toolsSchemaTokens +
        PromptBudget.approxTokensForMessagesJson(requestMessages);
    if ((!strictFullAttempted || fallbackTriggered) &&
        tokensApprox >= budgets.autoCompactTriggerTokens) {
      fallbackTriggered = true;
      try {
        await _chatContext.compactNow(cid: cid, reason: 'preflight');
        // Rebuild context message (summary likely changed) and recompute budgets.
        ctxMsg = '';
        try {
          ctxMsg = await _chatContext.buildSystemContextMessage(cid: cid);
        } catch (_) {}
        extras = await _buildHistoryFirstExtras(
          cid: cid,
          stage: 'chat_preflight',
          model: modelForBudget,
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          includeHistory: true,
          toolsSchemaTokens: toolsSchemaTokens,
          budgets: budgets,
          toolUsageInstruction: '',
          conversationContextMsg: ctxMsg,
          atomicMemoryMsg: amMsg,
          extraSystemMessages: <String>[
            if (summaryAppsMsg.trim().isNotEmpty) summaryAppsMsg,
          ],
        );
        reservedTokens = _approxReservedPromptTokens(
          systemPrompt: systemPrompt,
          extraSystemMessages: extras,
          userMessage: userMessage,
        );
        historyMaxTokens = _historyBudgetTokensForPrompt(
          budgets: budgets,
          reservedTokens: reservedTokens,
          toolsSchemaTokens: toolsSchemaTokens,
        );
        requestHistory = history;
        if (historyMaxTokens > 0) {
          try {
            final List<AIMessage> full = await _chatContext
                .loadRecentMessagesForPrompt(
                  cid: cid,
                  maxTokens: historyMaxTokens,
                );
            if (full.isNotEmpty) requestHistory = full;
          } catch (_) {}
        }
        requestMessages = _composeMessages(
          systemMessage: systemPrompt,
          history: _trimHistoryTailWithEvent(
            cid: cid,
            stage: 'chat_history_tail_preflight',
            model: modelForBudget,
            history: requestHistory,
            maxTokens: historyMaxTokens,
          ),
          userMessage: userMessage,
          extraSystemMessages: extras,
          historyMaxTokens: historyMaxTokens,
        );
        tokensApprox =
            toolsSchemaTokens +
            PromptBudget.approxTokensForMessagesJson(requestMessages);
      } catch (_) {}
    }
    final String modelForPrompt = endpoints.isNotEmpty
        ? endpoints.first.model
        : '';
    String promptBreakdownJson = '';
    try {
      promptBreakdownJson = _buildPromptBreakdownJson(
        model: modelForPrompt,
        systemPrompt: systemPrompt,
        userMessage: userMessage,
        history: requestHistory,
        includeHistory: true,
        tools: const <Map<String, dynamic>>[],
        conversationContextMsg: ctxMsg,
        atomicMemoryMsg: amMsg,
        historyMaxTokens: historyMaxTokens,
      );
    } catch (_) {}
    final int promptEstSent = PromptBudget.approxTokensForMessagesJson(
      requestMessages,
    );
    try {
      final bool amEnabled = await _settings.getAtomicMemoryInjectionEnabled();
      final bool amAutoExtract = await _settings
          .getAtomicMemoryAutoExtractEnabled();
      final int amMaxTokens = await _settings.getAtomicMemoryPromptTokens();
      final int amMaxItems = await _settings.getAtomicMemoryMaxItems();
      unawaited(
        _chatContext.logContextEvent(
          cid: cid,
          type: 'atomic_memory',
          payload: <String, dynamic>{
            'enabled': amEnabled,
            'auto_extract': amAutoExtract,
            'injected': amMsg.trim().isNotEmpty,
            'am_tokens': PromptBudget.approxTokensForText(amMsg),
            'max_tokens': amMaxTokens,
            'max_items': amMaxItems,
          },
        ),
      );
    } catch (_) {}

    final AIGatewayResult result = await _gateway.complete(
      endpoints: endpoints,
      messages: requestMessages,
      responseStartMarker: AIChatService.responseStartMarker,
      timeout: timeout,
      preferStreaming: true,
      logContext: 'chat',
    );

    _recordPromptUsageForCall(
      cid: cid,
      model: modelForPrompt,
      promptEstBefore: promptEstBefore,
      promptEstSent: promptEstSent,
      result: result,
      isToolLoop: false,
      includeHistory: true,
      toolsCount: 0,
      strictFullAttempted: strictFullAttempted,
      fallbackTriggered: fallbackTriggered,
      breakdownJson: promptBreakdownJson,
    );

    final AIMessage assistant = AIMessage(
      role: 'assistant',
      content: result.content,
      reasoningContent: result.reasoning,
      reasoningDuration: result.reasoningDuration,
    );

    // Do not block UI / streaming completion on history persistence.
    // Persist best-effort in background to avoid "stuck at final answer" when DB is slow/locked.
    unawaited(() async {
      try {
        await _persistConversation(
          cid: cid,
          history: history,
          userMessage: userMessage,
          assistant: assistant,
          modelUsed: result.modelUsed,
          toolSignatureDigests: const <String, Map<String, dynamic>>{},
          rawTurnTranscript: const <AIMessage>[],
        );
      } catch (_) {}
    }());

    return assistant;
  }

  Future<AIStreamingSession> sendMessageStreamedV2(
    String userMessage, {
    Duration? timeout,
    String context = 'chat',
    String? conversationCid,
  }) async {
    try {
      await FlutterLogger.nativeInfo(
        'AI',
        'sendMessageStreamedV2 begin len=${userMessage.length}',
      );
    } catch (_) {}

    final String cid = (conversationCid ?? '').trim().isNotEmpty
        ? conversationCid!.trim()
        : await _settings.getActiveConversationCid();
    final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
      context: context,
    );
    final List<AIMessage> history = await _settings.getChatHistoryByCid(cid);

    return _startStreamingSession(
      conversationCid: cid,
      userMessage: userMessage,
      displayUserMessage: userMessage,
      endpoints: endpoints,
      history: history,
      timeout: timeout,
      context: context,
      includeHistory: true,
      persistHistory: true,
      extraSystemMessages: const <String>[],
    );
  }

  Future<AIStreamingSession> sendMessageStreamedV2WithDisplayOverride(
    String displayUserMessage,
    String actualUserMessage, {
    Duration? timeout,
    bool includeHistory = false,
    List<String> extraSystemMessages = const <String>[],
    bool persistHistory = true,
    // When true, persist UI tail history into `ai_messages`.
    // Some callers (e.g., chat UI) may persist their own post-processed content and
    // only want the service to update the append-only transcript/tool memory.
    bool persistHistoryTail = true,
    String context = 'chat',
    String? conversationCid,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Object? toolChoice,
    int maxToolIters =
        0, // 0 = unlimited (HARD RULE: do NOT introduce a fixed cap)
    int? toolStartMs,
    int? toolEndMs,
    bool forceToolFirstIfNoToolCalls = false,
    int? uiAssistantCreatedAtMs,
  }) async {
    if (tools.isNotEmpty) {
      final String cid = (conversationCid ?? '').trim().isNotEmpty
          ? conversationCid!.trim()
          : (await _settings.getActiveConversationCid()).trim();
      final int assistantCreatedAtMs = (uiAssistantCreatedAtMs ?? 0);
      final bool enableTimelinePersist =
          persistHistory &&
          persistHistoryTail &&
          cid.isNotEmpty &&
          assistantCreatedAtMs > 0;
      String? seededUi;
      if (enableTimelinePersist) {
        try {
          seededUi = await ScreenshotDatabase.instance
              .getAiAssistantUiThinkingJson(cid, assistantCreatedAtMs);
        } catch (_) {
          seededUi = null;
        }
      }
      final _ToolUiThinkingPersister? timelinePersister = enableTimelinePersist
          ? _ToolUiThinkingPersister(
              cid: cid,
              displayUserMessage: displayUserMessage,
              assistantCreatedAtMs: assistantCreatedAtMs,
              toolsTitle: _loc('工具调用', 'Tools'),
              settings: _settings,
              seededUiThinkingJson: seededUi,
            )
          : null;

      // 工具调用采用 tool-loop。模型侧请求支持流式增量输出（content/reasoning），
      // 同时在 tool-loop 过程中持续输出“当前在做什么”的进度事件。
      final StreamController<AIStreamEvent> controller =
          StreamController<AIStreamEvent>();

      bool sawContent = false;
      bool sawModelReasoning = false;
      void emitSafe(AIStreamEvent evt) {
        timelinePersister?.handle(evt);
        if (controller.isClosed) return;
        if (evt.kind == 'content' && evt.data.trim().isNotEmpty) {
          sawContent = true;
        }
        if (evt.kind == 'reasoning' &&
            evt.data.trim().isNotEmpty &&
            !evt.data.startsWith('- ')) {
          // _emitProgress() always prefixes "- "; treat non-prefixed chunks as model reasoning.
          sawModelReasoning = true;
        }
        controller.add(evt);
      }

      final Future<AIMessage> completed =
          _sendMessageWithDisplayOverrideInternal(
            displayUserMessage,
            actualUserMessage,
            timeout: timeout,
            includeHistory: includeHistory,
            extraSystemMessages: extraSystemMessages,
            tools: tools,
            toolChoice: toolChoice,
            maxToolIters: maxToolIters,
            persistHistory: persistHistory,
            persistHistoryTail: persistHistoryTail,
            context: context,
            conversationCid: cid,
            toolStartMs: toolStartMs,
            toolEndMs: toolEndMs,
            forceToolFirstIfNoToolCalls: forceToolFirstIfNoToolCalls,
            emitEvent: emitSafe,
            uiThinkingJsonProvider: () => timelinePersister?.uiThinkingJson,
          );
      // ignore: discarded_futures
      completed
          .then((AIMessage message) {
            if (timelinePersister != null) {
              unawaited(
                timelinePersister.flushNow().whenComplete(
                  () => timelinePersister.dispose(),
                ),
              );
            }
            if (controller.isClosed) return;
            final String reasoning = (message.reasoningContent ?? '')
                .trimRight();
            if (reasoning.isNotEmpty && !sawModelReasoning) {
              controller.add(AIStreamEvent('reasoning', reasoning));
            }
            if (message.content.isNotEmpty && !sawContent) {
              controller.add(AIStreamEvent('content', message.content));
            }
            unawaited(controller.close());
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (timelinePersister != null) {
              unawaited(
                timelinePersister.flushNow().whenComplete(
                  () => timelinePersister.dispose(),
                ),
              );
            }
            if (controller.isClosed) return;
            controller.addError(error, stackTrace);
            unawaited(controller.close());
          });
      return AIStreamingSession(
        stream: controller.stream,
        completed: completed,
      );
    }

    try {
      await FlutterLogger.nativeInfo(
        'AI',
        'sendMessageStreamedV2WithDisplayOverride begin displayLen=${displayUserMessage.length} actualLen=${actualUserMessage.length}',
      );
    } catch (_) {}

    final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
      context: context,
    );
    final String cid = (conversationCid ?? '').trim().isNotEmpty
        ? conversationCid!.trim()
        : await _settings.getActiveConversationCid();
    final List<AIMessage> history = await _settings.getChatHistoryByCid(cid);

    return _startStreamingSession(
      conversationCid: cid,
      userMessage: actualUserMessage,
      displayUserMessage: displayUserMessage,
      endpoints: endpoints,
      history: history,
      // Let _startStreamingSession decide the optimal prompt history (prefer
      // append-only transcript). Keep this param only as an override.
      requestHistory: null,
      timeout: timeout,
      context: context,
      includeHistory: includeHistory,
      persistHistory: persistHistory,
      persistHistoryTail: persistHistoryTail,
      extraSystemMessages: extraSystemMessages,
    );
  }

  Future<AIStreamingSession> _startStreamingSession({
    required String conversationCid,
    required String userMessage,
    required String displayUserMessage,
    required List<AIEndpoint> endpoints,
    required List<AIMessage> history,
    List<AIMessage>? requestHistory,
    Duration? timeout,
    String context = 'chat',
    bool includeHistory = true,
    bool persistHistory = true,
    bool persistHistoryTail = true,
    List<String> extraSystemMessages = const <String>[],
  }) async {
    final String cid = conversationCid.trim();
    final String modelForBudget = endpoints.isNotEmpty
        ? endpoints.first.model
        : (await _settings.getModel());
    final AIContextBudgets budgets =
        await AIContextBudgets.forModelWithOverrides(modelForBudget);
    bool fallbackTriggered = false;

    // Best-effort bootstrap: seed append-only transcript from existing tail.
    try {
      await _chatContext.seedFromChatHistoryIfEmpty(cid: cid, history: history);
    } catch (_) {}

    final bool includeHistoryEffective = AIChatService.includeHistoryEffective(
      context: context,
      includeHistory: includeHistory,
      persistHistory: persistHistory,
    );
    final bool strictFullAttempted = _shouldTryStrictFullContext(
      context: context,
      persistHistory: persistHistory,
      includeHistory: includeHistoryEffective,
    );
    final List<AIMessage> strictRawHistory = strictFullAttempted
        ? await _loadStrictRawHistoryForChat(cid)
        : const <AIMessage>[];
    List<String> effectiveExtras = <String>[];
    String ctxMsg = '';
    String amMsg = '';
    String summaryAppsMsg = '';
    if (context == 'chat' && persistHistory) {
      try {
        ctxMsg = await _chatContext.buildSystemContextMessage(cid: cid);
      } catch (_) {}
      try {
        amMsg = await AtomicMemoryService.instance
            .buildAtomicMemoryContextMessage(
              cid: cid,
              query: userMessage.trim(),
            );
      } catch (_) {}
      try {
        summaryAppsMsg = await _buildSummaryAppsContextMessage();
      } catch (_) {}
    }
    final String systemPrompt = _systemPromptForLocale();

    effectiveExtras = await _buildHistoryFirstExtras(
      cid: cid,
      stage: 'stream_setup',
      model: modelForBudget,
      systemPrompt: systemPrompt,
      userMessage: userMessage,
      includeHistory: includeHistoryEffective,
      toolsSchemaTokens: 0,
      budgets: budgets,
      toolUsageInstruction: '',
      conversationContextMsg: ctxMsg,
      atomicMemoryMsg: amMsg,
      extraSystemMessages: <String>[
        if (summaryAppsMsg.trim().isNotEmpty) summaryAppsMsg,
        ...extraSystemMessages,
      ],
    );

    const int toolsSchemaTokens = 0;
    int reservedTokens = _approxReservedPromptTokens(
      systemPrompt: systemPrompt,
      extraSystemMessages: effectiveExtras,
      userMessage: userMessage,
    );
    int historyMaxTokens = includeHistoryEffective
        ? _historyBudgetTokensForPrompt(
            budgets: budgets,
            reservedTokens: reservedTokens,
            toolsSchemaTokens: toolsSchemaTokens,
          )
        : 0;

    List<AIMessage> effectiveHistory = const <AIMessage>[];
    if (includeHistoryEffective && historyMaxTokens > 0) {
      if (strictFullAttempted && strictRawHistory.isNotEmpty) {
        effectiveHistory = strictRawHistory;
        final int strictPromptTokens =
            toolsSchemaTokens +
            PromptBudget.approxTokensForMessagesJson(
              _composeMessages(
                systemMessage: systemPrompt,
                history: effectiveHistory,
                userMessage: userMessage,
                extraSystemMessages: effectiveExtras,
                includeHistory: includeHistoryEffective,
                historyMaxTokens: 1 << 30,
              ),
            );
        if (strictPromptTokens > budgets.effectivePromptCapTokens) {
          fallbackTriggered = true;
        }
      }
      if (!strictFullAttempted || fallbackTriggered) {
        try {
          final List<AIMessage> full = await _chatContext
              .loadRecentMessagesForPrompt(
                cid: cid,
                maxTokens: historyMaxTokens,
              );
          if (full.isNotEmpty) {
            effectiveHistory = full;
          } else {
            effectiveHistory = requestHistory ?? history;
          }
        } catch (_) {
          effectiveHistory = requestHistory ?? history;
        }
      }
    }

    final int promptEstBefore =
        toolsSchemaTokens +
        PromptBudget.approxTokensForMessagesJson(
          _composeMessages(
            systemMessage: systemPrompt,
            history: effectiveHistory,
            userMessage: userMessage,
            extraSystemMessages: effectiveExtras,
            includeHistory: includeHistoryEffective,
            historyMaxTokens: 1 << 30,
          ),
        );

    List<AIMessage> requestMessages = _composeMessages(
      systemMessage: systemPrompt,
      history: _trimHistoryTailWithEvent(
        cid: cid,
        stage: 'stream_history_tail_setup',
        model: modelForBudget,
        history: effectiveHistory,
        maxTokens: (strictFullAttempted && !fallbackTriggered)
            ? (1 << 30)
            : historyMaxTokens,
      ),
      userMessage: userMessage,
      extraSystemMessages: effectiveExtras,
      includeHistory: includeHistoryEffective,
      historyMaxTokens: (strictFullAttempted && !fallbackTriggered)
          ? (1 << 30)
          : historyMaxTokens,
    );

    // If close to the window, compact first, then retry once.
    int tokensApprox =
        toolsSchemaTokens +
        PromptBudget.approxTokensForMessagesJson(requestMessages);
    if (context == 'chat' &&
        persistHistory &&
        (!strictFullAttempted || fallbackTriggered) &&
        tokensApprox >= budgets.autoCompactTriggerTokens) {
      fallbackTriggered = true;
      try {
        await _chatContext.compactNow(cid: cid, reason: 'preflight');
        // Refresh only the context message + history tail; keep AM/WM stable.
        final List<String> extras2 = <String>[];
        ctxMsg = '';
        try {
          ctxMsg = await _chatContext.buildSystemContextMessage(cid: cid);
          if (ctxMsg.trim().isNotEmpty) extras2.add(ctxMsg.trim());
        } catch (_) {}
        final List<String> rebuilt = await _buildHistoryFirstExtras(
          cid: cid,
          stage: 'stream_preflight',
          model: modelForBudget,
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          includeHistory: includeHistoryEffective,
          toolsSchemaTokens: toolsSchemaTokens,
          budgets: budgets,
          toolUsageInstruction: '',
          conversationContextMsg: ctxMsg,
          atomicMemoryMsg: amMsg,
          extraSystemMessages: <String>[
            if (summaryAppsMsg.trim().isNotEmpty) summaryAppsMsg,
            ...extraSystemMessages,
          ],
        );
        extras2
          ..clear()
          ..addAll(rebuilt);
        effectiveExtras = extras2;
        reservedTokens = _approxReservedPromptTokens(
          systemPrompt: systemPrompt,
          extraSystemMessages: extras2,
          userMessage: userMessage,
        );
        historyMaxTokens = includeHistoryEffective
            ? _historyBudgetTokensForPrompt(
                budgets: budgets,
                reservedTokens: reservedTokens,
                toolsSchemaTokens: toolsSchemaTokens,
              )
            : 0;
        effectiveHistory = const <AIMessage>[];
        if (includeHistoryEffective && historyMaxTokens > 0) {
          try {
            final List<AIMessage> full = await _chatContext
                .loadRecentMessagesForPrompt(
                  cid: cid,
                  maxTokens: historyMaxTokens,
                );
            if (full.isNotEmpty) {
              effectiveHistory = full;
            } else {
              effectiveHistory = requestHistory ?? history;
            }
          } catch (_) {
            effectiveHistory = requestHistory ?? history;
          }
        }
        requestMessages = _composeMessages(
          systemMessage: systemPrompt,
          history: _trimHistoryTailWithEvent(
            cid: cid,
            stage: 'stream_history_tail_preflight',
            model: modelForBudget,
            history: effectiveHistory,
            maxTokens: historyMaxTokens,
          ),
          userMessage: userMessage,
          extraSystemMessages: extras2,
          includeHistory: includeHistoryEffective,
          historyMaxTokens: historyMaxTokens,
        );
        tokensApprox =
            toolsSchemaTokens +
            PromptBudget.approxTokensForMessagesJson(requestMessages);
      } catch (_) {}
    }
    final String modelForPrompt = endpoints.isNotEmpty
        ? endpoints.first.model
        : '';
    String promptBreakdownJson = '';
    if (context == 'chat' && persistHistory) {
      try {
        promptBreakdownJson = _buildPromptBreakdownJson(
          model: modelForPrompt,
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          history: effectiveHistory,
          includeHistory: includeHistoryEffective,
          tools: const <Map<String, dynamic>>[],
          conversationContextMsg: ctxMsg,
          atomicMemoryMsg: amMsg,
          extraSystemMessages: effectiveExtras,
          historyMaxTokens: historyMaxTokens,
        );
      } catch (_) {}
      try {
        final bool amEnabled = await _settings
            .getAtomicMemoryInjectionEnabled();
        final bool amAutoExtract = await _settings
            .getAtomicMemoryAutoExtractEnabled();
        final int amMaxTokens = await _settings.getAtomicMemoryPromptTokens();
        final int amMaxItems = await _settings.getAtomicMemoryMaxItems();
        unawaited(
          _chatContext.logContextEvent(
            cid: cid,
            type: 'atomic_memory',
            payload: <String, dynamic>{
              'enabled': amEnabled,
              'auto_extract': amAutoExtract,
              'injected': amMsg.trim().isNotEmpty,
              'am_tokens': PromptBudget.approxTokensForText(amMsg),
              'max_tokens': amMaxTokens,
              'max_items': amMaxItems,
            },
          ),
        );
      } catch (_) {}
    }

    final AIGatewayStreamingSession gatewaySession = _gateway.startStreaming(
      endpoints: endpoints,
      messages: requestMessages,
      responseStartMarker: AIChatService.responseStartMarker,
      timeout: timeout,
      logContext: context,
    );

    final Stream<AIStreamEvent> stream = gatewaySession.stream.map(
      (AIGatewayEvent event) => AIStreamEvent(event.kind, event.data),
    );
    final Future<AIMessage> completed = gatewaySession.completed.then((
      AIGatewayResult result,
    ) async {
      if (context == 'chat' && persistHistory) {
        _recordPromptUsageForCall(
          cid: cid,
          model: modelForPrompt,
          promptEstBefore: promptEstBefore,
          promptEstSent: PromptBudget.approxTokensForMessagesJson(
            requestMessages,
          ),
          result: result,
          isToolLoop: false,
          includeHistory: includeHistoryEffective,
          toolsCount: 0,
          strictFullAttempted: strictFullAttempted,
          fallbackTriggered: fallbackTriggered,
          breakdownJson: promptBreakdownJson,
        );
      }

      final AIMessage assistant = AIMessage(
        role: 'assistant',
        content: result.content,
        reasoningContent: result.reasoning,
        reasoningDuration: result.reasoningDuration,
      );

      if (persistHistory) {
        // Persist best-effort without blocking completion.
        unawaited(() async {
          try {
            await _persistConversation(
              cid: cid,
              history: history,
              userMessage: displayUserMessage,
              assistant: assistant,
              modelUsed: result.modelUsed,
              toolSignatureDigests: const <String, Map<String, dynamic>>{},
              rawTurnTranscript: const <AIMessage>[],
              persistHistoryTail: persistHistoryTail,
            );
          } catch (_) {}
        }());
      }

      return assistant;
    });

    return AIStreamingSession(stream: stream, completed: completed);
  }

  Future<AIMessage> sendMessageWithDisplayOverride(
    String displayUserMessage,
    String actualUserMessage, {
    Duration? timeout,
    bool includeHistory = false,
    List<String> extraSystemMessages = const <String>[],
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Object? toolChoice,
    int maxToolIters =
        0, // 0 = unlimited (HARD RULE: do NOT introduce a fixed cap)
    bool persistHistory = true,
    bool persistHistoryTail = true,
    String context = 'chat',
    String? conversationCid,
    int? toolStartMs,
    int? toolEndMs,
    bool forceToolFirstIfNoToolCalls = false,
    void Function(AIStreamEvent event)? emitEvent,
  }) async {
    return _sendMessageWithDisplayOverrideInternal(
      displayUserMessage,
      actualUserMessage,
      timeout: timeout,
      includeHistory: includeHistory,
      extraSystemMessages: extraSystemMessages,
      tools: tools,
      toolChoice: toolChoice,
      maxToolIters: maxToolIters,
      persistHistory: persistHistory,
      persistHistoryTail: persistHistoryTail,
      context: context,
      conversationCid: conversationCid,
      toolStartMs: toolStartMs,
      toolEndMs: toolEndMs,
      forceToolFirstIfNoToolCalls: forceToolFirstIfNoToolCalls,
      emitEvent: emitEvent,
    );
  }

  Future<AIMessage> _sendMessageWithDisplayOverrideInternal(
    String displayUserMessage,
    String actualUserMessage, {
    Duration? timeout,
    bool includeHistory = false,
    List<String> extraSystemMessages = const <String>[],
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Object? toolChoice,
    int maxToolIters =
        0, // 0 = unlimited (HARD RULE: do NOT introduce a fixed cap)
    bool persistHistory = true,
    bool persistHistoryTail = true,
    String context = 'chat',
    String? conversationCid,
    int? toolStartMs,
    int? toolEndMs,
    bool forceToolFirstIfNoToolCalls = false,
    void Function(AIStreamEvent event)? emitEvent,
    String? Function()? uiThinkingJsonProvider,
  }) async {
    if (tools.isNotEmpty) {
      _emitProgress(emitEvent, _loc('准备 agent loop…', 'Preparing agent loop…'));
    }
    final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
      context: context,
    );
    final String modelForBudget = endpoints.isNotEmpty
        ? endpoints.first.model
        : (await _settings.getModel());
    final AIContextBudgets budgets =
        await AIContextBudgets.forModelWithOverrides(modelForBudget);
    final String cid = (conversationCid ?? '').trim().isNotEmpty
        ? conversationCid!.trim()
        : await _settings.getActiveConversationCid();
    final List<AIMessage> history = await _settings.getChatHistoryByCid(cid);
    bool fallbackTriggered = false;
    // Best-effort bootstrap: seed append-only transcript from existing tail.
    try {
      await _chatContext.seedFromChatHistoryIfEmpty(cid: cid, history: history);
    } catch (_) {}
    final String systemPrompt = _systemPromptForLocale();
    final bool includeHistoryEffective = AIChatService.includeHistoryEffective(
      context: context,
      includeHistory: includeHistory,
      persistHistory: persistHistory,
    );
    final bool strictFullAttempted = _shouldTryStrictFullContext(
      context: context,
      persistHistory: persistHistory,
      includeHistory: includeHistoryEffective,
    );
    final List<AIMessage> strictRawHistory = strictFullAttempted
        ? await _loadStrictRawHistoryForChat(cid)
        : const <AIMessage>[];
    List<String> effectiveExtras = <String>[];
    String toolUsageInstruction = '';
    if (tools.isNotEmpty) {
      toolUsageInstruction = _buildToolUsageInstruction(tools);
    }
    String ctxMsg = '';
    String amMsg = '';
    String summaryAppsMsg = '';
    if (context == 'chat' && persistHistory) {
      try {
        ctxMsg = await _chatContext.buildSystemContextMessage(cid: cid);
      } catch (_) {}
      try {
        amMsg = await AtomicMemoryService.instance
            .buildAtomicMemoryContextMessage(
              cid: cid,
              query: actualUserMessage.trim(),
            );
      } catch (_) {}
      try {
        summaryAppsMsg = await _buildSummaryAppsContextMessage();
      } catch (_) {}
    }

    effectiveExtras = await _buildHistoryFirstExtras(
      cid: cid,
      stage: tools.isNotEmpty ? 'tool_loop_setup' : 'chat_setup',
      model: modelForBudget,
      systemPrompt: systemPrompt,
      userMessage: actualUserMessage,
      includeHistory: includeHistoryEffective,
      toolsSchemaTokens: _approxToolSchemaTokens(tools),
      budgets: budgets,
      toolUsageInstruction: toolUsageInstruction,
      conversationContextMsg: ctxMsg,
      atomicMemoryMsg: amMsg,
      extraSystemMessages: <String>[
        if (summaryAppsMsg.trim().isNotEmpty) summaryAppsMsg,
        ...extraSystemMessages,
      ],
    );

    final int toolsSchemaTokens = _approxToolSchemaTokens(tools);
    final int reservedTokens = _approxReservedPromptTokens(
      systemPrompt: systemPrompt,
      extraSystemMessages: effectiveExtras,
      userMessage: actualUserMessage,
    );
    final int historyMaxTokens = includeHistoryEffective
        ? _historyBudgetTokensForPrompt(
            budgets: budgets,
            reservedTokens: reservedTokens,
            toolsSchemaTokens: toolsSchemaTokens,
          )
        : 0;
    int historyMaxTokensForBreakdown = historyMaxTokens;

    List<AIMessage> filteredHistory = const <AIMessage>[];
    if (includeHistoryEffective && historyMaxTokens > 0) {
      if (strictFullAttempted && strictRawHistory.isNotEmpty) {
        filteredHistory = strictRawHistory;
        final int strictPromptTokens =
            toolsSchemaTokens +
            PromptBudget.approxTokensForMessagesJson(
              _composeMessages(
                systemMessage: systemPrompt,
                history: filteredHistory,
                userMessage: actualUserMessage,
                extraSystemMessages: effectiveExtras,
                includeHistory: includeHistoryEffective,
                historyMaxTokens: 1 << 30,
              ),
            );
        if (strictPromptTokens > budgets.effectivePromptCapTokens) {
          fallbackTriggered = true;
        }
      }
      if (!strictFullAttempted || fallbackTriggered) {
        try {
          final List<AIMessage> full = await _chatContext
              .loadRecentMessagesForPrompt(
                cid: cid,
                maxTokens: historyMaxTokens,
              );
          if (full.isNotEmpty) {
            filteredHistory = full;
          } else {
            filteredHistory = history
                .where((m) => m.role == 'user' || m.role == 'assistant')
                .toList();
          }
        } catch (_) {
          filteredHistory = history
              .where((m) => m.role == 'user' || m.role == 'assistant')
              .toList();
        }
      }
    }

    List<AIMessage> requestMessages = _composeMessages(
      systemMessage: systemPrompt,
      history: _trimHistoryTailWithEvent(
        cid: cid,
        stage: tools.isNotEmpty
            ? 'tool_loop_history_tail_setup'
            : 'chat_history_tail_setup',
        model: modelForBudget,
        history: filteredHistory,
        maxTokens: (strictFullAttempted && !fallbackTriggered)
            ? (1 << 30)
            : historyMaxTokens,
      ),
      userMessage: actualUserMessage,
      extraSystemMessages: effectiveExtras,
      includeHistory: includeHistoryEffective,
      historyMaxTokens: (strictFullAttempted && !fallbackTriggered)
          ? (1 << 30)
          : historyMaxTokens,
    );
    const int dynamicToolMessageTokens =
        0; // 0 => do not compact per-tool result payloads.

    // If close to the window, compact first, then rebuild the prompt once.
    int promptTokensApprox =
        toolsSchemaTokens +
        PromptBudget.approxTokensForMessagesJson(requestMessages);
    if (context == 'chat' &&
        persistHistory &&
        (!strictFullAttempted || fallbackTriggered) &&
        promptTokensApprox >= budgets.autoCompactTriggerTokens) {
      fallbackTriggered = true;
      try {
        await _chatContext.compactNow(cid: cid, reason: 'preflight');
        // Refresh ctx message and history tail; keep tool instruction + AM/WM stable.
        final List<String> extras2 = <String>[];
        ctxMsg = '';
        try {
          ctxMsg = await _chatContext.buildSystemContextMessage(cid: cid);
        } catch (_) {}
        final List<String> rebuilt = await _buildHistoryFirstExtras(
          cid: cid,
          stage: tools.isNotEmpty ? 'tool_loop_preflight' : 'chat_preflight',
          model: modelForBudget,
          systemPrompt: systemPrompt,
          userMessage: actualUserMessage,
          includeHistory: includeHistoryEffective,
          toolsSchemaTokens: toolsSchemaTokens,
          budgets: budgets,
          toolUsageInstruction: toolUsageInstruction,
          conversationContextMsg: ctxMsg,
          atomicMemoryMsg: amMsg,
          extraSystemMessages: <String>[
            if (summaryAppsMsg.trim().isNotEmpty) summaryAppsMsg,
            ...extraSystemMessages,
          ],
        );
        extras2
          ..clear()
          ..addAll(rebuilt);
        effectiveExtras = extras2;

        final int reserved2 = _approxReservedPromptTokens(
          systemPrompt: systemPrompt,
          extraSystemMessages: extras2,
          userMessage: actualUserMessage,
        );
        final int historyMax2 = includeHistoryEffective
            ? _historyBudgetTokensForPrompt(
                budgets: budgets,
                reservedTokens: reserved2,
                toolsSchemaTokens: toolsSchemaTokens,
              )
            : 0;
        filteredHistory = const <AIMessage>[];
        if (includeHistoryEffective && historyMax2 > 0) {
          try {
            final List<AIMessage> full = await _chatContext
                .loadRecentMessagesForPrompt(cid: cid, maxTokens: historyMax2);
            if (full.isNotEmpty) {
              filteredHistory = full;
            } else {
              filteredHistory = history
                  .where((m) => m.role == 'user' || m.role == 'assistant')
                  .toList();
            }
          } catch (_) {
            filteredHistory = history
                .where((m) => m.role == 'user' || m.role == 'assistant')
                .toList();
          }
        }
        requestMessages = _composeMessages(
          systemMessage: systemPrompt,
          history: _trimHistoryTailWithEvent(
            cid: cid,
            stage: tools.isNotEmpty
                ? 'tool_loop_history_tail_preflight'
                : 'chat_history_tail_preflight',
            model: modelForBudget,
            history: filteredHistory,
            maxTokens: historyMax2,
          ),
          userMessage: actualUserMessage,
          extraSystemMessages: extras2,
          includeHistory: includeHistoryEffective,
          historyMaxTokens: historyMax2,
        );
        historyMaxTokensForBreakdown = historyMax2;
        promptTokensApprox =
            toolsSchemaTokens +
            PromptBudget.approxTokensForMessagesJson(requestMessages);
      } catch (_) {}
    }
    final String modelForPrompt = endpoints.isNotEmpty
        ? endpoints.first.model
        : '';
    String promptBreakdownJson = '';
    if (context == 'chat' && persistHistory) {
      try {
        promptBreakdownJson = _buildPromptBreakdownJson(
          model: modelForPrompt,
          systemPrompt: systemPrompt,
          userMessage: actualUserMessage,
          history: filteredHistory,
          includeHistory: includeHistoryEffective,
          tools: tools,
          toolUsageInstruction: toolUsageInstruction,
          conversationContextMsg: ctxMsg,
          atomicMemoryMsg: amMsg,
          extraSystemMessages: effectiveExtras,
          historyMaxTokens: historyMaxTokensForBreakdown,
        );
      } catch (_) {}
      try {
        final bool amEnabled = await _settings
            .getAtomicMemoryInjectionEnabled();
        final bool amAutoExtract = await _settings
            .getAtomicMemoryAutoExtractEnabled();
        final int amMaxTokens = await _settings.getAtomicMemoryPromptTokens();
        final int amMaxItems = await _settings.getAtomicMemoryMaxItems();
        unawaited(
          _chatContext.logContextEvent(
            cid: cid,
            type: 'atomic_memory',
            payload: <String, dynamic>{
              'enabled': amEnabled,
              'auto_extract': amAutoExtract,
              'injected': amMsg.trim().isNotEmpty,
              'am_tokens': PromptBudget.approxTokensForText(amMsg),
              'max_tokens': amMaxTokens,
              'max_items': amMaxItems,
              'tool_loop': tools.isNotEmpty,
            },
          ),
        );
      } catch (_) {}
    }
    final int promptEstBefore =
        toolsSchemaTokens +
        PromptBudget.approxTokensForMessagesJson(
          _composeMessages(
            systemMessage: systemPrompt,
            history: filteredHistory,
            userMessage: actualUserMessage,
            extraSystemMessages: effectiveExtras,
            includeHistory: includeHistoryEffective,
            historyMaxTokens: 1 << 30,
          ),
        );
    final AIMessage pinnedUserMessage = requestMessages.isNotEmpty
        ? requestMessages.last
        : AIMessage(role: 'user', content: actualUserMessage);
    final List<AIMessage> rawTurnTranscript = <AIMessage>[];
    final Set<String> toolNames = _extractToolNames(tools);
    final bool hasRetrievalTools =
        toolNames.contains('search_segments') ||
        toolNames.contains('search_screenshots_ocr') ||
        toolNames.contains('search_ai_image_meta');

    Future<AIGatewayResult> callModel({
      required List<AIMessage> messages,
      List<Map<String, dynamic>> toolsForCall = const <Map<String, dynamic>>[],
      Object? toolChoiceForCall,
      bool preferStreaming = true,
      String trimStage = 'model_call',
      bool isToolLoop = false,
      int? forcedPromptEstBefore,
      String? forcedBreakdownJson,
    }) async {
      final int beforeEst =
          forcedPromptEstBefore ??
          (_approxToolSchemaTokens(toolsForCall) +
              PromptBudget.approxTokensForMessagesJson(messages));

      String callBreakdownJson = forcedBreakdownJson ?? '';
      if (context == 'chat' && persistHistory) {
        if (callBreakdownJson.trim().isEmpty) {
          try {
            callBreakdownJson = _buildPromptBreakdownJsonFromMessages(
              model: modelForPrompt,
              messages: messages,
              tools: toolsForCall,
            );
          } catch (_) {}
        }
      }

      if (context == 'chat' && persistHistory) {
        messages = _enforceToolLoopPromptBudget(
          messages,
          pinnedUser: pinnedUserMessage,
          maxPromptTokens: _toolLoopBudgetTokensForPrompt(
            budgets: budgets,
            toolsSchemaTokens: _approxToolSchemaTokens(toolsForCall),
          ),
          emitEvent: null,
          cid: cid,
          stage: trimStage,
          model: modelForBudget,
        );
      }

      final int sentEst =
          _approxToolSchemaTokens(toolsForCall) +
          PromptBudget.approxTokensForMessagesJson(messages);

      final bool fallbackNow = fallbackTriggered || sentEst < beforeEst;

      if (emitEvent != null && preferStreaming) {
        final AIGatewayStreamingSession session = _gateway.startStreaming(
          endpoints: endpoints,
          messages: messages,
          responseStartMarker: AIChatService.responseStartMarker,
          timeout: timeout,
          logContext: context,
          tools: toolsForCall,
          toolChoice: toolChoiceForCall,
        );
        final Future<AIGatewayResult> completed = session.completed;
        await for (final AIGatewayEvent e in session.stream) {
          emitEvent(AIStreamEvent(e.kind, e.data));
        }
        final AIGatewayResult result = await completed;
        if (context == 'chat' && persistHistory) {
          _recordPromptUsageForCall(
            cid: cid,
            model: modelForPrompt,
            promptEstBefore: beforeEst,
            promptEstSent: sentEst,
            result: result,
            isToolLoop: isToolLoop,
            includeHistory: includeHistoryEffective,
            toolsCount: toolsForCall.length,
            strictFullAttempted: strictFullAttempted,
            fallbackTriggered: fallbackNow,
            breakdownJson: callBreakdownJson,
          );
        }
        return result;
      }
      final AIGatewayResult result = await _gateway.complete(
        endpoints: endpoints,
        messages: messages,
        responseStartMarker: AIChatService.responseStartMarker,
        timeout: timeout,
        preferStreaming: preferStreaming,
        logContext: context,
        tools: toolsForCall,
        toolChoice: toolChoiceForCall,
      );
      if (context == 'chat' && persistHistory) {
        _recordPromptUsageForCall(
          cid: cid,
          model: modelForPrompt,
          promptEstBefore: beforeEst,
          promptEstSent: sentEst,
          result: result,
          isToolLoop: isToolLoop,
          includeHistory: includeHistoryEffective,
          toolsCount: toolsForCall.length,
          strictFullAttempted: strictFullAttempted,
          fallbackTriggered: fallbackNow,
          breakdownJson: callBreakdownJson,
        );
      }
      return result;
    }

    // === Tool loop (supports streaming) ===
    if (tools.isNotEmpty) {
      final String iterZh = maxToolIters <= 0 ? '无限制' : '$maxToolIters 轮';
      final String iterEn = maxToolIters <= 0
          ? 'unlimited'
          : '$maxToolIters iters';
      _emitProgress(
        emitEvent,
        _loc(
          'Agent loop 开始（tools=${tools.length}，迭代上限：$iterZh）',
          'Agent loop started (tools=${tools.length}, max: $iterEn)',
        ),
      );
    }
    List<AIMessage> working = List<AIMessage>.from(requestMessages);
    if (tools.isNotEmpty) {
      _emitProgress(
        emitEvent,
        _loc('请求模型生成工具调用/答案…', 'Calling model for tool calls/answer…'),
      );
    }
    final Stopwatch firstReq = Stopwatch()..start();
    Timer? firstHeartbeatStarter;
    Timer? firstHeartbeatTicker;
    if (tools.isNotEmpty && emitEvent != null) {
      firstHeartbeatStarter = Timer(const Duration(seconds: 12), () {
        firstHeartbeatTicker = Timer.periodic(const Duration(seconds: 10), (_) {
          final int secs = firstReq.elapsed.inSeconds;
          if (secs <= 0) return;
          _emitProgress(
            emitEvent,
            _loc(
              '等待模型响应中… 已等待 ${secs}s',
              'Waiting for model… ${secs}s elapsed',
            ),
          );
        });
      });
    }
    late AIGatewayResult result;
    try {
      working = _replaceImageMessagesWithPlaceholder(
        working,
        keepMostRecent: true,
        cid: cid,
        stage: 'tool_loop_initial_image',
        model: modelForBudget,
      );
      working = _enforceToolLoopPromptBudget(
        working,
        pinnedUser: pinnedUserMessage,
        maxPromptTokens: _toolLoopBudgetTokensForPrompt(
          budgets: budgets,
          toolsSchemaTokens: toolsSchemaTokens,
        ),
        emitEvent: emitEvent,
        cid: cid,
        stage: 'tool_loop_initial_budget',
        model: modelForBudget,
      );
      result = await callModel(
        messages: working,
        toolsForCall: tools,
        toolChoiceForCall: toolChoice,
        preferStreaming: true,
        trimStage: 'tool_loop_initial_call',
        isToolLoop: tools.isNotEmpty,
        forcedPromptEstBefore: promptEstBefore,
        forcedBreakdownJson: promptBreakdownJson,
      );
    } finally {
      firstHeartbeatStarter?.cancel();
      firstHeartbeatTicker?.cancel();
      firstReq.stop();
    }
    // Important: drop/replace multimodal image payloads after they have been sent
    // once; otherwise we will re-upload base64 blobs on every follow-up call.
    working = _replaceImageMessagesWithPlaceholder(
      working,
      keepMostRecent: false,
      cid: cid,
      stage: 'tool_loop_post_initial_image',
      model: modelForBudget,
    );
    if (tools.isNotEmpty && result.toolCalls.isEmpty) {
      final AIGatewayResult coerced = _maybeCoerceToolCallsFromText(
        result,
        tools,
      );
      if (coerced.toolCalls.isNotEmpty) {
        _emitProgress(
          emitEvent,
          _loc(
            '检测到模型以文本格式输出工具调用，已自动解析并继续执行。',
            'Detected text-form tool calls; parsed and continuing.',
          ),
        );
        result = coerced;
      }
    }
    if (tools.isNotEmpty) {
      _emitProgress(
        emitEvent,
        _loc(
          '模型已响应：tool_calls=${result.toolCalls.length}（${firstReq.elapsedMilliseconds}ms）',
          'Model responded: tool_calls=${result.toolCalls.length} (${firstReq.elapsedMilliseconds}ms)',
        ),
      );
    }

    // If tools are enabled but the model doesn't call any tool for lookup-style tasks
    // (or it outputs "searched/evidence" claims in plain text), do one extra "tool-first"
    // retry to avoid premature/hallucinated answers.
    final bool shouldForceRetrievalRetry =
        tools.isNotEmpty &&
        hasRetrievalTools &&
        result.toolCalls.isEmpty &&
        (forceToolFirstIfNoToolCalls ||
            _contentLooksLikeItReferencesEvidence(result.content));
    if (shouldForceRetrievalRetry) {
      _emitProgress(
        emitEvent,
        _loc(
          '模型未调用工具；为避免草率结论，触发强制检索重试…',
          'No tool calls; forcing a retrieval retry to avoid premature answers…',
        ),
      );

      List<AIMessage> retryMessages = List<AIMessage>.from(requestMessages)
        ..add(
          AIMessage(
            role: 'user',
            content: _loc(
              '请先至少调用一次检索类工具（search_segments 或 search_screenshots_ocr）。'
                  '若第一次结果为空，请更换关键词并至少再检索一次；必要时调整时间范围（start_local/end_local）或 offset/limit 分页继续检索。'
                  '确认后再输出最终回答；不要在未检索前直接下结论，也不要臆造 [evidence: ...]。',
              'Call at least one retrieval tool first (search_segments or search_screenshots_ocr), '
                  'if the first result is empty, try a different query and search again; '
                  'adjust the time window (start_local/end_local) or page via offset/limit if needed, then answer. '
                  'Do not conclude (or fabricate evidence) before searching.',
            ),
          ),
        );

      final Stopwatch retryReq = Stopwatch()..start();
      Timer? retryHeartbeatStarter;
      Timer? retryHeartbeatTicker;
      if (emitEvent != null) {
        retryHeartbeatStarter = Timer(const Duration(seconds: 12), () {
          retryHeartbeatTicker = Timer.periodic(const Duration(seconds: 10), (
            _,
          ) {
            final int secs = retryReq.elapsed.inSeconds;
            if (secs <= 0) return;
            _emitProgress(
              emitEvent,
              _loc(
                '等待模型响应中… 已等待 ${secs}s',
                'Waiting for model… ${secs}s elapsed',
              ),
            );
          });
        });
      }
      try {
        retryMessages = _replaceImageMessagesWithPlaceholder(
          retryMessages,
          keepMostRecent: true,
          cid: cid,
          stage: 'tool_loop_force_retry_image',
          model: modelForBudget,
        );
        retryMessages = _enforceToolLoopPromptBudget(
          retryMessages,
          pinnedUser: pinnedUserMessage,
          maxPromptTokens: _toolLoopBudgetTokensForPrompt(
            budgets: budgets,
            toolsSchemaTokens: toolsSchemaTokens,
          ),
          emitEvent: emitEvent,
          cid: cid,
          stage: 'tool_loop_force_retry_budget',
          model: modelForBudget,
        );
        result = await callModel(
          messages: retryMessages,
          toolsForCall: tools,
          toolChoiceForCall: toolChoice,
          preferStreaming: true,
          trimStage: 'tool_loop_force_retry_call',
          isToolLoop: true,
        );
      } finally {
        retryHeartbeatStarter?.cancel();
        retryHeartbeatTicker?.cancel();
        retryReq.stop();
      }
      retryMessages = _replaceImageMessagesWithPlaceholder(
        retryMessages,
        keepMostRecent: false,
        cid: cid,
        stage: 'tool_loop_force_retry_post_image',
        model: modelForBudget,
      );
      if (result.toolCalls.isEmpty) {
        result = _maybeCoerceToolCallsFromText(result, tools);
      }
      _emitProgress(
        emitEvent,
        _loc(
          '重试后模型已响应：tool_calls=${result.toolCalls.length}（${retryReq.elapsedMilliseconds}ms）',
          'Retry responded: tool_calls=${result.toolCalls.length} (${retryReq.elapsedMilliseconds}ms)',
        ),
      );

      // Keep the same message list that produced the tool calls.
      working = List<AIMessage>.from(retryMessages);
    }

    // HARD RULE: 禁止在 maxToolIters<=0（无限制）时引入任何“固定轮次上限/安全上限”。
    // 若担心模型陷入循环，优先用“无进展”护栏 + 强提示引导退出循环，
    // 避免用固定轮次截断（否则会破坏跨月/跨年检索等长任务）。
    final bool unlimitedIters = maxToolIters <= 0;
    int iters = 0;
    int totalToolCalls = 0;
    bool forcedEmptySearchRetry = false;
    bool hadAnyRetrievalHit = false;
    String lastRetrievalTool = '';
    int lastRetrievalCount = -1;
    bool lastRetrievalHasPagingSignal = false;
    final Map<String, Map<String, dynamic>> signatureDigests =
        <String, Map<String, dynamic>>{};
    int consecutiveEmptyRetrievalBatches = 0;
    bool forcedNoProgressStop = false;

    while (result.toolCalls.isNotEmpty &&
        (unlimitedIters || iters < maxToolIters)) {
      iters += 1;

      _emitProgress(
        emitEvent,
        _loc(
          '第 $iters 轮：执行 ${result.toolCalls.length} 个工具调用…',
          'Iteration $iters: executing ${result.toolCalls.length} tool calls…',
        ),
      );

      // Append assistant tool call message (required by OpenAI tool protocol)
      final AIMessage assistantToolCallMessage = AIMessage(
        role: 'assistant',
        content: result.content,
        toolCalls: result.toolCalls
            .map((e) => e.toOpenAIToolCallJson())
            .toList(),
      );
      working.add(assistantToolCallMessage);
      rawTurnTranscript.add(assistantToolCallMessage);

      final List<Map<String, dynamic>> uiTools = await Future.wait(
        result.toolCalls
            .map((c) async {
              final Map<String, dynamic> args = _safeJsonObject(
                c.argumentsJson,
              );
              final List<String> appNames = _normalizeAppNamesArg(args);
              final List<String> appPkgs = await _resolveAppPackagesFromArgs(
                args,
              );
              return <String, dynamic>{
                'call_id': c.id,
                'tool_name': c.name,
                'label': _toolCallUiLabel(c),
                if (appNames.isNotEmpty) 'app_names': appNames,
                if (appPkgs.isNotEmpty) 'app_package_names': appPkgs,
              };
            })
            .toList(growable: false),
      );
      _emitUi(emitEvent, <String, dynamic>{
        'type': 'tool_batch_begin',
        'iteration': iters,
        'tools': uiTools,
      });

      // Execute each tool call and append tool + follow-up user messages
      int idxInBatch = 0;
      int batchRetrievalCalls = 0;
      int batchRetrievalHits = 0;
      for (final AIToolCall call in result.toolCalls) {
        idxInBatch += 1;
        totalToolCalls += 1;
        final String argsPreview = call.argumentsJson.trim().isEmpty
            ? ''
            : _clipLine(call.argumentsJson, maxLen: 160);
        final String argsSuffix = argsPreview.isEmpty
            ? ''
            : ' args=$argsPreview';
        _emitProgress(
          emitEvent,
          _loc(
            '运行工具 #$totalToolCalls（本轮 $idxInBatch/${result.toolCalls.length}）：$call.name$argsSuffix',
            'Run tool #$totalToolCalls (batch $idxInBatch/${result.toolCalls.length}): $call.name$argsSuffix',
          ),
        );

        final String signature = _toolCallSignature(call);

        final Stopwatch toolSw = Stopwatch()..start();
        final List<AIMessage> toolMsgs = _compactToolMessagesForPrompt(
          await _executeToolCall(
            call,
            toolStartMs: toolStartMs,
            toolEndMs: toolEndMs,
          ),
          maxToolMessageTokens: dynamicToolMessageTokens,
          cid: cid,
          stage: 'tool_result_compact',
          model: modelForBudget,
        );
        toolSw.stop();
        working.addAll(toolMsgs);
        rawTurnTranscript.addAll(toolMsgs);
        if (toolMsgs.isNotEmpty) {
          final Map<String, dynamic> obj = _safeJsonObject(
            toolMsgs.first.content,
          );
          signatureDigests[signature] = _toolPayloadDigest(obj);
          final String tool = (obj['tool'] as String?)?.trim() ?? '';
          final int? count = _toInt(obj['count']);
          if (count != null &&
              (tool == 'search_segments' ||
                  tool == 'search_segments_ocr' ||
                  tool == 'search_screenshots_ocr' ||
                  tool == 'search_ai_image_meta')) {
            batchRetrievalCalls += 1;
            if (count > 0) batchRetrievalHits += 1;
            lastRetrievalTool = tool;
            lastRetrievalCount = count;
            lastRetrievalHasPagingSignal = _retrievalPayloadHasPagingSignal(
              obj,
            );
            if (count > 0) hadAnyRetrievalHit = true;
          }
        }
        final String toolSummary = _summarizeToolMessages(toolMsgs);
        final String summarySuffix = toolSummary.isEmpty
            ? ''
            : ' ($toolSummary)';
        _emitProgress(
          emitEvent,
          _loc(
            '完成工具 #$totalToolCalls：$call.name$summarySuffix（${toolSw.elapsedMilliseconds}ms）',
            'Finished tool #$totalToolCalls: $call.name$summarySuffix (${toolSw.elapsedMilliseconds}ms)',
          ),
        );
        _emitUi(emitEvent, <String, dynamic>{
          'type': 'tool_call_end',
          'call_id': call.id,
          'tool_name': call.name,
          'result_summary': toolSummary,
          'duration_ms': toolSw.elapsedMilliseconds,
        });
      }

      if (batchRetrievalCalls > 0) {
        if (batchRetrievalHits > 0) {
          consecutiveEmptyRetrievalBatches = 0;
        } else {
          consecutiveEmptyRetrievalBatches += 1;
        }
      }

      _emitProgress(
        emitEvent,
        _loc('将工具结果回传给模型…', 'Sending tool results back to model…'),
      );
      final Stopwatch followReq = Stopwatch()..start();
      Timer? followHeartbeatStarter;
      Timer? followHeartbeatTicker;
      final bool shouldForceNoProgressStop =
          !forcedNoProgressStop &&
          hasRetrievalTools &&
          !hadAnyRetrievalHit &&
          consecutiveEmptyRetrievalBatches >= 3;
      if (shouldForceNoProgressStop) {
        forcedNoProgressStop = true;
        working.add(
          AIMessage(
            role: 'user',
            content: _loc(
              '进展护栏：已连续多次检索仍无结果/无新信息（多次 count=0）。\n'
                  '请停止继续调用工具（避免陷入循环），改为：\n'
                  '1) 基于现有信息给出最佳努力答复，并明确哪些结论缺少证据；\n'
                  '2) 只有在硬阻塞（权限/数据源/输入冲突）时，才向用户询问 1 个最关键补充线索；非硬阻塞不要连续追问。\n'
                  '禁止编造证据或臆造 [evidence: ...]。',
              'Progress guard: repeated searches are yielding no new information (multiple count=0).\n'
                  'Stop calling tools (avoid loops). Instead:\n'
                  '1) Give a best-effort answer from what you have, clearly stating what lacks evidence.\n'
                  '2) Ask at most ONE key follow-up only on hard blockers (permissions/data source/conflicting inputs); avoid multi-question clarification loops.\n'
                  'Do not fabricate evidence or [evidence: ...].',
            ),
          ),
        );
      }
      final bool forceNoTools =
          shouldForceNoProgressStop && result.toolCalls.isNotEmpty;
      if (emitEvent != null) {
        followHeartbeatStarter = Timer(const Duration(seconds: 12), () {
          followHeartbeatTicker = Timer.periodic(const Duration(seconds: 10), (
            _,
          ) {
            final int secs = followReq.elapsed.inSeconds;
            if (secs <= 0) return;
            _emitProgress(
              emitEvent,
              _loc(
                '等待模型响应中… 已等待 ${secs}s',
                'Waiting for model… ${secs}s elapsed',
              ),
            );
          });
        });
      }
      try {
        working = _replaceImageMessagesWithPlaceholder(
          working,
          keepMostRecent: true,
          cid: cid,
          stage: 'tool_loop_follow_image',
          model: modelForBudget,
        );
        working = _enforceToolLoopPromptBudget(
          working,
          pinnedUser: pinnedUserMessage,
          maxPromptTokens: _toolLoopBudgetTokensForPrompt(
            budgets: budgets,
            toolsSchemaTokens: toolsSchemaTokens,
          ),
          emitEvent: emitEvent,
          cid: cid,
          stage: 'tool_loop_follow_budget',
          model: modelForBudget,
        );
        result = await callModel(
          messages: working,
          toolsForCall: forceNoTools ? const <Map<String, dynamic>>[] : tools,
          toolChoiceForCall: forceNoTools ? null : toolChoice,
          preferStreaming: true,
          trimStage: 'tool_loop_follow_call',
          isToolLoop: true,
        );
      } finally {
        followHeartbeatStarter?.cancel();
        followHeartbeatTicker?.cancel();
        followReq.stop();
      }
      working = _replaceImageMessagesWithPlaceholder(
        working,
        keepMostRecent: false,
        cid: cid,
        stage: 'tool_loop_follow_post_image',
        model: modelForBudget,
      );
      if (!forceNoTools && result.toolCalls.isEmpty) {
        final AIGatewayResult coerced = _maybeCoerceToolCallsFromText(
          result,
          tools,
        );
        if (coerced.toolCalls.isNotEmpty) {
          _emitProgress(
            emitEvent,
            _loc(
              '检测到模型以文本格式输出工具调用，已自动解析并继续执行。',
              'Detected text-form tool calls; parsed and continuing.',
            ),
          );
          result = coerced;
        }
      }
      _emitProgress(
        emitEvent,
        _loc(
          '模型已响应：tool_calls=${result.toolCalls.length}（${followReq.elapsedMilliseconds}ms）',
          'Model responded: tool_calls=${result.toolCalls.length} (${followReq.elapsedMilliseconds}ms)',
        ),
      );

      final bool shouldForceContinueSearch =
          tools.isNotEmpty &&
          hasRetrievalTools &&
          !forcedEmptySearchRetry &&
          forceToolFirstIfNoToolCalls &&
          !hadAnyRetrievalHit &&
          lastRetrievalCount == 0 &&
          result.toolCalls.isEmpty &&
          _contentLooksLikeHardNoResultsConclusion(result.content);
      if (shouldForceContinueSearch) {
        forcedEmptySearchRetry = true;
        final String suffix = lastRetrievalTool.isEmpty
            ? ''
            : '（$lastRetrievalTool count=0）';
        _emitProgress(
          emitEvent,
          _loc(
            '检索结果为空且模型准备直接下结论$suffix；触发继续检索重试…',
            'Empty search results and the model is about to conclude$suffix; forcing a continued-search retry…',
          ),
        );

        List<AIMessage> retryMessages = List<AIMessage>.from(working)
          ..add(
            AIMessage(
              role: 'user',
              content: _loc(
                '注意：上一次检索结果为空（count=0），不能据此直接断言“没有/未找到”。\n'
                    '在输出最终答复前，请按以下流程继续：\n'
                    '1) 至少再调用 2 次检索类工具（search_segments / search_screenshots_ocr / search_ai_image_meta），并更换关键词（拆词/同义词/英文）。\n'
                    '2) 若本次查询范围较大，请调整 start_local/end_local 覆盖不同时间段，或使用 offset/limit 分页获取更多结果；若工具返回 paging.prev/paging.next，也可使用它们继续。\n'
                    '3) 若多次检索仍为空，先给出“已覆盖范围/未覆盖范围/证据缺口”，仅在硬阻塞时允许询问 1 条关键线索。\n'
                    '确认后再给最终答复；不要臆造证据或 [evidence: ...]。',
                'Note: the last retrieval returned count=0, so you must not conclude “not found” yet.\n'
                    'Before answering, do ALL of the following:\n'
                    '1) Make at least 2 more retrieval calls (search_segments / search_screenshots_ocr / search_ai_image_meta) with alternative keywords (split words / synonyms / English).\n'
                    '2) If the overall range is large, adjust start_local/end_local to cover different windows or page via offset/limit; if the tool returns paging.prev/paging.next you may use them as well.\n'
                    '3) If still empty, report covered scope / uncovered scope / evidence gaps first; ask at most ONE key follow-up only on hard blockers.\n'
                    'Do not fabricate evidence or [evidence: ...].',
              ),
            ),
          );

        final Stopwatch retryReq = Stopwatch()..start();
        Timer? retryHeartbeatStarter;
        Timer? retryHeartbeatTicker;
        if (emitEvent != null) {
          retryHeartbeatStarter = Timer(const Duration(seconds: 12), () {
            retryHeartbeatTicker = Timer.periodic(const Duration(seconds: 10), (
              _,
            ) {
              final int secs = retryReq.elapsed.inSeconds;
              if (secs <= 0) return;
              _emitProgress(
                emitEvent,
                _loc(
                  '等待模型响应中… 已等待 ${secs}s',
                  'Waiting for model… ${secs}s elapsed',
                ),
              );
            });
          });
        }
        try {
          retryMessages = _replaceImageMessagesWithPlaceholder(
            retryMessages,
            keepMostRecent: true,
            cid: cid,
            stage: 'tool_loop_empty_retry_image',
            model: modelForBudget,
          );
          retryMessages = _enforceToolLoopPromptBudget(
            retryMessages,
            pinnedUser: pinnedUserMessage,
            maxPromptTokens: _toolLoopBudgetTokensForPrompt(
              budgets: budgets,
              toolsSchemaTokens: toolsSchemaTokens,
            ),
            emitEvent: emitEvent,
            cid: cid,
            stage: 'tool_loop_empty_retry_budget',
            model: modelForBudget,
          );
          result = await callModel(
            messages: retryMessages,
            toolsForCall: tools,
            toolChoiceForCall: toolChoice,
            preferStreaming: true,
            trimStage: 'tool_loop_empty_retry_call',
            isToolLoop: true,
          );
        } finally {
          retryHeartbeatStarter?.cancel();
          retryHeartbeatTicker?.cancel();
          retryReq.stop();
        }
        retryMessages = _replaceImageMessagesWithPlaceholder(
          retryMessages,
          keepMostRecent: false,
          cid: cid,
          stage: 'tool_loop_empty_retry_post_image',
          model: modelForBudget,
        );
        if (result.toolCalls.isEmpty) {
          result = _maybeCoerceToolCallsFromText(result, tools);
        }
        _emitProgress(
          emitEvent,
          _loc(
            '继续检索重试后模型已响应：tool_calls=${result.toolCalls.length}（${retryReq.elapsedMilliseconds}ms）',
            'Continued-search retry responded: tool_calls=${result.toolCalls.length} (${retryReq.elapsedMilliseconds}ms)',
          ),
        );
        working = List<AIMessage>.from(retryMessages);
      }

      final bool shouldForceAutoPagingRetry =
          tools.isNotEmpty &&
          hasRetrievalTools &&
          !forcedEmptySearchRetry &&
          forceToolFirstIfNoToolCalls &&
          result.toolCalls.isEmpty &&
          lastRetrievalHasPagingSignal &&
          _contentLooksLikeClarificationStop(result.content);
      if (shouldForceAutoPagingRetry) {
        forcedEmptySearchRetry = true;
        _emitProgress(
          emitEvent,
          _loc(
            '检测到可继续翻页但模型准备停机追问；触发自动翻页覆盖重试…',
            'Paging is available but model is stopping for clarification; forcing an auto-paging retry…',
          ),
        );

        List<AIMessage> retryMessages = List<AIMessage>.from(working)
          ..add(
            AIMessage(
              role: 'user',
              content: _loc(
                '当前检索结果仍可继续扩展（存在 paging/clamped 提示）。\n'
                    '请不要先向用户提问；先继续自动翻页覆盖范围并补充证据。\n'
                    '输出时请明确：已覆盖范围、未覆盖范围、下一步计划。\n'
                    '仅当出现硬阻塞（权限/数据源缺失/输入冲突）时，才允许询问 1 个关键问题。',
                'Current retrieval can still be expanded (paging/clamped hints present).\n'
                    'Do not ask the user first; continue auto-paging to expand coverage and gather evidence.\n'
                    'In your answer, state covered scope, uncovered scope, and next steps.\n'
                    'Only ask ONE key question on hard blockers (permission/data source/input conflict).',
              ),
            ),
          );

        final Stopwatch retryReq = Stopwatch()..start();
        Timer? retryHeartbeatStarter;
        Timer? retryHeartbeatTicker;
        if (emitEvent != null) {
          retryHeartbeatStarter = Timer(const Duration(seconds: 12), () {
            retryHeartbeatTicker = Timer.periodic(const Duration(seconds: 10), (
              _,
            ) {
              final int secs = retryReq.elapsed.inSeconds;
              if (secs <= 0) return;
              _emitProgress(
                emitEvent,
                _loc(
                  '等待模型响应中… 已等待 ${secs}s',
                  'Waiting for model… ${secs}s elapsed',
                ),
              );
            });
          });
        }
        try {
          retryMessages = _replaceImageMessagesWithPlaceholder(
            retryMessages,
            keepMostRecent: true,
            cid: cid,
            stage: 'tool_loop_auto_paging_retry_image',
            model: modelForBudget,
          );
          retryMessages = _enforceToolLoopPromptBudget(
            retryMessages,
            pinnedUser: pinnedUserMessage,
            maxPromptTokens: _toolLoopBudgetTokensForPrompt(
              budgets: budgets,
              toolsSchemaTokens: toolsSchemaTokens,
            ),
            emitEvent: emitEvent,
            cid: cid,
            stage: 'tool_loop_auto_paging_retry_budget',
            model: modelForBudget,
          );
          result = await callModel(
            messages: retryMessages,
            toolsForCall: tools,
            toolChoiceForCall: toolChoice,
            preferStreaming: true,
            trimStage: 'tool_loop_auto_paging_retry_call',
            isToolLoop: true,
          );
        } finally {
          retryHeartbeatStarter?.cancel();
          retryHeartbeatTicker?.cancel();
          retryReq.stop();
        }
        retryMessages = _replaceImageMessagesWithPlaceholder(
          retryMessages,
          keepMostRecent: false,
          cid: cid,
          stage: 'tool_loop_auto_paging_retry_post_image',
          model: modelForBudget,
        );
        if (result.toolCalls.isEmpty) {
          result = _maybeCoerceToolCallsFromText(result, tools);
        }
        _emitProgress(
          emitEvent,
          _loc(
            '自动翻页覆盖重试后模型已响应：tool_calls=${result.toolCalls.length}（${retryReq.elapsedMilliseconds}ms）',
            'Auto-paging retry responded: tool_calls=${result.toolCalls.length} (${retryReq.elapsedMilliseconds}ms)',
          ),
        );
        working = List<AIMessage>.from(retryMessages);
      }
    }

    if (!unlimitedIters && result.toolCalls.isNotEmpty) {
      _emitProgress(
        emitEvent,
        _loc(
          '达到最大迭代次数仍有 tool_calls，已中止。',
          'Max iterations reached while tool_calls remain; aborting.',
        ),
      );
      throw Exception('Tool loop exceeded max iterations ($maxToolIters)');
    }

    if (tools.isNotEmpty) {
      _emitProgress(
        emitEvent,
        _loc(
          '生成最终回答…（本次工具调用总次数：$totalToolCalls）',
          'Preparing final answer… (tool calls: $totalToolCalls)',
        ),
      );
    }

    String? uiJson = uiThinkingJsonProvider?.call();
    uiJson = (uiJson ?? '').trim().isNotEmpty ? uiJson!.trim() : null;
    final AIMessage assistant = AIMessage(
      role: 'assistant',
      content: result.content,
      reasoningContent: result.reasoning,
      reasoningDuration: result.reasoningDuration,
      uiThinkingJson: uiJson,
    );

    if (persistHistory) {
      // Persist best-effort without blocking the tool-loop completion (stream UI depends on it).
      unawaited(() async {
        try {
          await _persistConversation(
            cid: cid,
            history: history,
            userMessage: displayUserMessage,
            assistant: assistant,
            modelUsed: result.modelUsed,
            conversationTitle: displayUserMessage,
            toolSignatureDigests: signatureDigests,
            rawTurnTranscript: rawTurnTranscript,
            persistHistoryTail: persistHistoryTail,
          );
        } catch (_) {}
      }());
    }

    return assistant;
  }

  Future<AIMessage> sendMessageOneShot(
    String userMessage, {
    String context = 'chat',
    Duration? timeout,
  }) async {
    final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
      context: context,
    );
    final String systemPrompt = _systemPromptForLocale();
    final List<AIMessage> requestMessages = _composeMessages(
      systemMessage: systemPrompt,
      history: const <AIMessage>[],
      userMessage: userMessage,
      includeHistory: false,
    );

    final AIGatewayResult result = await _gateway.complete(
      endpoints: endpoints,
      messages: requestMessages,
      responseStartMarker: AIChatService.responseStartMarker,
      timeout: timeout,
      preferStreaming: true,
      logContext: context,
    );

    return AIMessage(
      role: 'assistant',
      content: result.content,
      reasoningContent: result.reasoning,
      reasoningDuration: result.reasoningDuration,
    );
  }

  Future<void> clearConversation() => _settings.clearChatHistory();

  Future<List<AIMessage>> getConversation() => _settings.getChatHistory();
}
