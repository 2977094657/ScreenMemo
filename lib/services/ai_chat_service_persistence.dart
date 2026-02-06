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

  List<AIMessage> _composeMessages({
    required String systemMessage,
    required List<AIMessage> history,
    required String userMessage,
    Iterable<String> extraSystemMessages = const <String>[],
    bool includeHistory = true,
    int? historyMaxTokens,
  }) {
    final List<AIMessage> messages = <AIMessage>[
      AIMessage(role: 'system', content: systemMessage),
      ...extraSystemMessages
          .where((msg) => msg.trim().isNotEmpty)
          .map((msg) => AIMessage(role: 'system', content: msg.trim())),
    ];
    if (includeHistory && history.isNotEmpty) {
      final int maxTokens =
          (historyMaxTokens ?? AIChatService.maxHistoryPromptTokens).clamp(
            0,
            1 << 30,
          );
      final List<AIMessage> trimmedHistory =
          PromptBudget.keepTailUnderTokenBudget(history, maxTokens: maxTokens);
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
    required String cid,
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

    if (persistHistoryTail) {
      // Merge into the latest DB history to avoid duplicating the user message
      // and to preserve UI-persisted `uiThinkingJson` when the chat UI detaches.
      try {
        final Map<String, dynamic>? row = await ScreenshotDatabase.instance
            .getAiConversationByCid(cid);
        if (row != null) {
          final List<AIMessage> existing = await _settings.getChatHistoryByCid(
            cid,
          );
          final List<AIMessage> merged = mergeCompletedTurnIntoHistory(
            existingHistory: existing,
            userMessage: userMessage,
            assistantFinal: assistant,
          );
          await _settings.saveChatHistoryByCid(cid, merged);
          _settings.notifyContextChanged('chat:history');
        }
      } catch (_) {}
    }
    await _updateConversationModel(cid, modelUsed);

    // Best-effort: ingest user chat into local memory backend (async, non-blocking).
    try {
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
    } catch (_) {}

    if (history.isEmpty) {
      await _renameConversation(cid, conversationTitle ?? userMessage);
    }
  }

  Future<void> _updateConversationModel(String cid, String modelUsed) async {
    try {
      final ScreenshotDatabase db = ScreenshotDatabase.instance;
      await db.database.then(
        (storage) => storage.execute(
          'UPDATE ai_conversations SET model = ? WHERE cid = ?',
          <Object?>[modelUsed, cid],
        ),
      );
    } catch (_) {}
  }

  Future<void> _renameConversation(String cid, String titleSource) async {
    final String trimmed = titleSource.trim();
    if (trimmed.isEmpty) return;
    final String title = _truncateTitle(trimmed);
    try {
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
