part of 'ai_chat_service.dart';

extension AIChatServicePersistenceExt on AIChatService {
  String _systemPromptForLocale({bool allowCharts = false}) {
    final Locale locale = _effectivePromptLocale();
    final String languagePolicy = lookupAppLocalizations(
      locale,
    ).aiSystemPromptLanguagePolicy.trim();
    final String timeContext = buildCurrentDateTimeSystemMessage(locale).trim();
    final String appMarkerContext = buildAppMarkerSystemMessage(locale).trim();
    final String chartProtocol = _chartMarkdownProtocolForLocale(locale).trim();
    final List<String> blocks = <String>[
      if (languagePolicy.isNotEmpty) languagePolicy,
      if (timeContext.isNotEmpty) timeContext,
      if (appMarkerContext.isNotEmpty) appMarkerContext,
      if (allowCharts && chartProtocol.isNotEmpty) chartProtocol,
    ];
    return blocks.join('\n\n');
  }

  String _chartMarkdownProtocolForLocale(Locale locale) {
    final String code = locale.languageCode.toLowerCase();
    if (code.startsWith('zh')) {
      return '''
在聊天回复中，只有在存在明确的数值趋势、对比或占比时，才允许输出图表。
图表必须且只能使用以下 Markdown 代码块协议：
```chart-v1
{"type":"line|bar|area|pie|scatter","title":"...","x":["..."],"series":[{"name":"...","data":[1,2,3]}],"y":{"label":"..."},"colors":["#RRGGBB"],"note":"..."}
```
规则：
- 禁止输出 HTML、JavaScript、iframe、ECharts option、Mermaid 或其他图表 DSL。
- 图表前后必须保留 1 到 2 句自然语言结论，不能只输出图表。
- line/bar/area/scatter 必须提供 x，且每个 series.data 长度必须与 x 一致。
- pie 只能有 1 个 series，且 x 作为切片标签。''';
    }
    if (code.startsWith('ja')) {
      return '''
チャット返信でグラフを出してよいのは、明確な数値の傾向・比較・構成比がある場合だけです。
グラフは必ず次の Markdown コードブロック形式のみを使ってください。
```chart-v1
{"type":"line|bar|area|pie|scatter","title":"...","x":["..."],"series":[{"name":"...","data":[1,2,3]}],"y":{"label":"..."},"colors":["#RRGGBB"],"note":"..."}
```
ルール:
- HTML、JavaScript、iframe、ECharts option、Mermaid、その他の図表 DSL を出力してはいけません。
- グラフの前後には必ず 1〜2 文の自然文による結論を入れ、グラフだけを出力してはいけません。
- line/bar/area/scatter は x が必須で、各 series.data の長さは x と一致させてください。
- pie は series を 1 つだけにし、x を各スライスのラベルとして使ってください。''';
    }
    if (code.startsWith('ko')) {
      return '''
채팅 답변에서 차트를 출력해도 되는 경우는 명확한 수치 추세, 비교, 비중이 있을 때뿐입니다.
차트는 반드시 아래 Markdown 코드 블록 형식만 사용하세요.
```chart-v1
{"type":"line|bar|area|pie|scatter","title":"...","x":["..."],"series":[{"name":"...","data":[1,2,3]}],"y":{"label":"..."},"colors":["#RRGGBB"],"note":"..."}
```
규칙:
- HTML, JavaScript, iframe, ECharts option, Mermaid, 기타 차트 DSL 을 출력하면 안 됩니다.
- 차트 앞이나 뒤에는 반드시 1~2문장의 자연어 결론을 포함해야 하며, 차트만 단독으로 출력하면 안 됩니다.
- line/bar/area/scatter 는 x 가 필수이며 각 series.data 길이는 x 와 같아야 합니다.
- pie 는 series 를 1개만 사용하고 x 를 각 조각의 라벨로 사용하세요.''';
    }
    return '''
In chat replies, charts are allowed only when there is clear numeric trend, comparison, or share data.
Charts must use this Markdown fence and nothing else:
```chart-v1
{"type":"line|bar|area|pie|scatter","title":"...","x":["..."],"series":[{"name":"...","data":[1,2,3]}],"y":{"label":"..."},"colors":["#RRGGBB"],"note":"..."}
```
Rules:
- Do not output HTML, JavaScript, iframe, ECharts option, Mermaid, or any other chart DSL.
- Keep 1 to 2 natural-language conclusion sentences before or after the chart; never output only the chart.
- line/bar/area/scatter require x, and every series.data length must match x.
- pie must have exactly 1 series, and x is the slice label list.''';
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
    List<AIMessage> rawTurnTranscript = const <AIMessage>[],
    bool persistHistory = true,
    bool persistHistoryTail = true,
    String? conversationTitle,
  }) async {
    if (!persistHistory) return;

    List<AIMessage>? mergedTail;
    bool didSaveTail = false;
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
          mergedTail = merged;
          didSaveTail = true;
        }
      } catch (_) {}
    }
    await _updateConversationModel(cid, modelUsed);

    final List<AIMessage> historyForContext = mergedTail ?? history;
    final String userTrim = userMessage.trim();
    int? userAtMs;
    int? assistantAtMs;
    if (userTrim.isNotEmpty && historyForContext.isNotEmpty) {
      try {
        int userIdx = -1;
        for (int i = historyForContext.length - 1; i >= 0; i--) {
          final AIMessage m = historyForContext[i];
          if (m.role == 'user' && m.content.trim() == userTrim) {
            userIdx = i;
            break;
          }
        }
        if (userIdx >= 0) {
          userAtMs =
              historyForContext[userIdx].createdAt.millisecondsSinceEpoch;
          for (int j = userIdx + 1; j < historyForContext.length; j++) {
            final String r = historyForContext[j].role;
            if (r == 'assistant') {
              assistantAtMs =
                  historyForContext[j].createdAt.millisecondsSinceEpoch;
              break;
            }
            if (r == 'user') break;
          }
        }
      } catch (_) {}
    }

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
          userCreatedAtMs: userAtMs,
          assistantCreatedAtMs: assistantAtMs,
        );
        if (toolSignatureDigests.isNotEmpty) {
          await _chatContext.mergeToolDigests(
            cid: cid,
            signatureDigests: toolSignatureDigests,
          );
        }
        final List<AIMessage> rawToAppend = <AIMessage>[
          AIMessage(role: 'user', content: userMessage),
          ...rawTurnTranscript,
          AIMessage(role: 'assistant', content: assistant.content),
        ];
        await _chatContext.appendRawTranscriptMessages(
          cid: cid,
          messages: rawToAppend,
        );
        _chatContext.scheduleAutoCompact(
          cid: cid,
          reason: toolSignatureDigests.isNotEmpty ? 'tool_loop' : 'turn',
        );
      } catch (_) {}
    } catch (_) {}

    if (history.isEmpty) {
      await _renameConversation(cid, conversationTitle ?? userMessage);
    }
    if (didSaveTail) {
      try {
        _settings.notifyContextChanged('chat:history');
      } catch (_) {}
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
    return '${text.substring(0, 30)}...';
  }
}
