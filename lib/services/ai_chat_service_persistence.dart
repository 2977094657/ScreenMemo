part of 'ai_chat_service.dart';

extension AIChatServicePersistenceExt on AIChatService {
  String _systemPromptForLocale() {
    final Locale locale = _effectivePromptLocale();
    return lookupAppLocalizations(locale).aiSystemPromptLanguagePolicy;
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

  Future<String> _buildWorkingMemoryContextMessage(String userMessage) async {
    try {
      final bool enabled = await _settings.getWorkingMemoryInjectionEnabled();
      if (!enabled) return '';
      final int edgeLimit = await _settings.getWorkingMemoryEdgeLimit();
      final int maxTokens = await _settings.getWorkingMemoryPromptTokens();

      final Map<String, dynamic> payload =
          await MemoryBridgeService.instance.buildWorkingMemory(
        query: userMessage.trim(),
        edgeLimit: edgeLimit,
        includeHistoryEdges: false,
      );
      final String raw =
          (payload['working_memory_markdown'] as String?)?.trim() ?? '';
      if (raw.isEmpty) return '';

      String text = raw;
      final int tokens = PromptBudget.approxTokensForText(text);
      if (tokens > maxTokens) {
        final int maxBytes =
            maxTokens * PromptBudget.approxBytesPerToken;
        text = PromptBudget.truncateTextByBytes(
          text: text,
          maxBytes: maxBytes,
          marker: '…working_memory truncated…',
        ).trim();
      }

      return [
        '<working_memory>',
        text,
        '</working_memory>',
      ].join('\n').trim();
    } catch (_) {
      return '';
    }
  }

  List<AIMessage> _composeMessages({
    required String systemMessage,
    required List<AIMessage> history,
    required String userMessage,
    Iterable<String> extraSystemMessages = const <String>[],
    bool includeHistory = true,
  }) {
    final List<AIMessage> messages = <AIMessage>[
      AIMessage(role: 'system', content: systemMessage),
      ...extraSystemMessages
          .where((msg) => msg.trim().isNotEmpty)
          .map((msg) => AIMessage(role: 'system', content: msg.trim())),
    ];
    if (includeHistory && history.isNotEmpty) {
      final List<AIMessage> trimmedHistory =
          PromptBudget.keepTailUnderTokenBudget(
            history,
            maxTokens: AIChatService.maxHistoryPromptTokens,
          );
      messages.addAll(
        trimmedHistory.map(
          (msg) => AIMessage(role: msg.role, content: msg.content),
        ),
      );
    }
    messages.add(AIMessage(role: 'user', content: userMessage));
    return messages;
  }

  Future<void> _persistConversation({
    required List<AIMessage> history,
    required String userMessage,
    required AIMessage assistant,
    required String modelUsed,
    required Map<String, Map<String, dynamic>> toolSignatureDigests,
    bool persistHistory = true,
    bool persistHistoryTail = true,
    String? conversationTitle,
  }) async {
    if (!persistHistory) return;

    final AIMessage user = AIMessage(role: 'user', content: userMessage);
    if (persistHistoryTail) {
      final List<AIMessage> newHistory = <AIMessage>[
        ...history,
        user,
        assistant,
      ];
      await _settings.saveChatHistoryActive(newHistory);
    }
    await _updateConversationModel(modelUsed);

    // Best-effort: ingest user chat into local memory backend (async, non-blocking).
      try {
        final String cid = await _settings.getActiveConversationCid();
        // Keep a separate append-only transcript + compacted memory for long chats.
        try {
          await _chatContext.seedFromChatHistoryIfEmpty(
          cid: cid,
          history: history,
        );
        await _chatContext.appendCompletedTurn(
          cid: cid,
          userMessage: userMessage,
          assistantMessage: assistant.content,
        );
        if (toolSignatureDigests.isNotEmpty) {
          await _chatContext.mergeToolDigests(
            cid: cid,
            signatureDigests: toolSignatureDigests,
          );
        }
        _chatContext.scheduleAutoCompact(
          cid: cid,
          reason: toolSignatureDigests.isNotEmpty ? 'tool_loop' : 'turn',
        );
      } catch (_) {}
      try {
        AtomicMemoryService.instance.scheduleExtractFromTurn(
          cid: cid,
          userMessage: userMessage,
        );
      } catch (_) {}
      unawaited(
        MemoryBridgeService.instance.ingestChatMessage(
          conversationId: cid,
          role: 'user',
          content: userMessage,
          createdAt: user.createdAt,
        ),
      );
    } catch (_) {}

    if (history.isEmpty) {
      await _renameConversation(conversationTitle ?? userMessage);
    }
  }

  Future<void> _updateConversationModel(String modelUsed) async {
    try {
      final String cid = await _settings.getActiveConversationCid();
      final ScreenshotDatabase db = ScreenshotDatabase.instance;
      await db.database.then(
        (storage) => storage.execute(
          'UPDATE ai_conversations SET model = ? WHERE cid = ?',
          <Object?>[modelUsed, cid],
        ),
      );
    } catch (_) {}
  }

  Future<void> _renameConversation(String titleSource) async {
    final String trimmed = titleSource.trim();
    if (trimmed.isEmpty) return;
    final String title = _truncateTitle(trimmed);
    try {
      final String cid = await _settings.getActiveConversationCid();
      // Do not override a non-empty title (e.g., UI already renamed by intent).
      final Map<String, dynamic>? row = await ScreenshotDatabase.instance
          .getAiConversationByCid(cid);
      final String existing = (row?['title'] as String?)?.trim() ?? '';
      if (existing.isNotEmpty) return;
      await _settings.renameConversation(cid, title);
    } catch (_) {}
  }

  String _truncateTitle(String text) {
    if (text.length <= 30) return text;
    return text.substring(0, 30) + '...';
  }
}
