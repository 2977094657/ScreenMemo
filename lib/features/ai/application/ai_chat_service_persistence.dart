part of 'ai_chat_service.dart';

extension AIChatServicePersistenceExt on AIChatService {
  String get _generatedImageContextNote =>
      'Previous generated images from this conversation are attached for context.';

  String _systemPromptForLocale({bool allowCharts = false}) {
    final Locale locale = _effectivePromptLocale();
    final String languagePolicy = lookupAppLocalizations(
      locale,
    ).aiSystemPromptLanguagePolicy.trim();
    final String chartProtocol = _chartMarkdownProtocolForLocale(locale).trim();
    final String appMarkerContext = buildAppMarkerSystemMessage(locale).trim();
    final String timeContext = buildCurrentDateTimeSystemMessage(locale).trim();
    final List<String> blocks = <String>[
      if (languagePolicy.isNotEmpty) languagePolicy,
      if (allowCharts && chartProtocol.isNotEmpty) chartProtocol,
      if (appMarkerContext.isNotEmpty) appMarkerContext,
      if (timeContext.isNotEmpty) timeContext,
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

  String _mimeForGeneratedImagePath(String path) {
    final String ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'png':
        return 'image/png';
      default:
        return 'image/png';
    }
  }

  List<String> _generatedImageFilenamesFromMessages(
    Iterable<AIMessage> messages, {
    int limit = 8,
  }) {
    if (limit <= 0) return const <String>[];
    final RegExp markerPattern = RegExp(
      r'\[\s*generated-image\s*:\s*([^\]\s]+)\s*\]',
      caseSensitive: false,
    );
    final List<String> names = <String>[];
    final Set<String> seen = <String>{};
    for (final AIMessage message in messages) {
      for (final RegExpMatch match in markerPattern.allMatches(
        message.content,
      )) {
        final String name = (match.group(1) ?? '').trim();
        if (name.isEmpty) continue;
        if (!seen.add(name)) continue;
        names.add(name);
      }
    }
    if (names.length <= limit) return names;
    return names.sublist(names.length - limit);
  }

  Future<List<Map<String, Object?>>> _generatedImagePartsForMessages(
    Iterable<AIMessage> messages, {
    int limit = 8,
  }) async {
    final List<String> names = _generatedImageFilenamesFromMessages(
      messages,
      limit: limit,
    );
    if (names.isEmpty) return const <Map<String, Object?>>[];
    final Map<String, String> paths = await ScreenshotDatabase.instance
        .findAiGeneratedImagePathsByFilenames(names.toSet());
    final List<Map<String, Object?>> parts = <Map<String, Object?>>[];
    for (final String name in names) {
      final String path = (paths[name] ?? '').trim();
      if (path.isEmpty) continue;
      try {
        final File file = File(path);
        if (!await file.exists()) continue;
        final Uint8List bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        final String mime = _mimeForGeneratedImagePath(path);
        parts.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{
            'url': 'data:$mime;base64,${base64Encode(bytes)}',
          },
        });
      } catch (_) {}
      if (parts.length >= limit) break;
    }
    return parts;
  }

  Future<Object?> _withGeneratedImageContextFromMessages(
    Object? userApiContent,
    String userMessage,
    Iterable<AIMessage> messages,
  ) async {
    final List<Map<String, Object?>> imageParts =
        await _generatedImagePartsForMessages(messages);
    if (imageParts.isEmpty) return userApiContent;
    bool hasGeneratedImageContextNote(Object? apiContent) {
      if (apiContent is! List) return false;
      for (final Object? item in apiContent) {
        if (item is! Map) continue;
        if ((item['type'] ?? '').toString() != 'text') continue;
        if ((item['text'] ?? '').toString().contains(
          _generatedImageContextNote,
        )) {
          return true;
        }
      }
      return false;
    }

    String? imageUrlForPart(Object? item) {
      if (item is! Map) return null;
      if ((item['type'] ?? '').toString() != 'image_url') return null;
      final Object? rawImageUrl = item['image_url'];
      if (rawImageUrl is! Map) return null;
      final String url = (rawImageUrl['url'] ?? '').toString().trim();
      return url.isEmpty ? null : url;
    }

    final bool alreadyHasContextNote = hasGeneratedImageContextNote(
      userApiContent,
    );

    if (userApiContent is List) {
      final List<Object?> out = <Object?>[];
      bool inserted = false;
      final Set<String> existingImageUrls = <String>{};
      for (final Object? item in userApiContent) {
        final String? url = imageUrlForPart(item);
        if (url != null) existingImageUrls.add(url);
        if (item is Map) {
          final Map<String, Object?> map = Map<String, Object?>.from(item);
          if (!alreadyHasContextNote &&
              !inserted &&
              (map['type'] ?? '').toString() == 'text') {
            map['text'] =
                '${(map['text'] ?? '').toString()}\n\n$_generatedImageContextNote';
            inserted = true;
          }
          out.add(map);
        } else {
          out.add(item);
        }
      }
      if (!alreadyHasContextNote && !inserted) {
        out.insert(0, <String, Object?>{
          'type': 'text',
          'text': '$userMessage\n\n$_generatedImageContextNote',
        });
      }
      for (final Map<String, Object?> part in imageParts) {
        final String? url = imageUrlForPart(part);
        if (url != null && !existingImageUrls.add(url)) continue;
        out.add(part);
      }
      return out;
    }
    return <Map<String, Object?>>[
      <String, Object?>{
        'type': 'text',
        'text': '$userMessage\n\n$_generatedImageContextNote',
      },
      ...imageParts,
    ];
  }

  String _stripComposerImageMarkersForPrompt(String text) {
    return text
        .replaceAll(
          RegExp(
            r'^[ \t]*\[\[composer-image:[^|\]]+(?:\|[^\]]*)?\]\][ \t]*$',
            multiLine: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  List<AIMessage> _composeMessages({
    required String systemMessage,
    required List<AIMessage> history,
    required String userMessage,
    Object? userApiContent,
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
          (msg) => AIMessage(
            role: msg.role,
            content: msg.role == 'user'
                ? _stripComposerImageMarkersForPrompt(msg.content)
                : msg.content,
            reasoningContent: msg.reasoningContent,
            reasoningDuration: msg.reasoningDuration,
            apiContent: msg.apiContent,
            toolCalls: msg.toolCalls,
            toolCallId: msg.toolCallId,
          ),
        ),
      );
    }
    messages.add(
      AIMessage(role: 'user', content: userMessage, apiContent: userApiContent),
    );
    return messages;
  }

  Future<void> _persistConversation({
    required String cid,
    required List<AIMessage> history,
    required String userMessage,
    String? localUserMessageForHistory,
    int? userCreatedAtMs,
    required AIMessage assistant,
    required String modelUsed,
    required Map<String, Map<String, dynamic>> toolSignatureDigests,
    Object? userApiContent,
    List<AIMessage> rawTurnTranscript = const <AIMessage>[],
    bool persistHistory = true,
    bool persistHistoryTail = true,
    String? conversationTitle,
  }) async {
    if (!persistHistory) return;
    final String localUserMessage =
        (localUserMessageForHistory ?? '').trim().isNotEmpty
        ? localUserMessageForHistory!.trim()
        : userMessage.trim();
    int? turnCreatedAtMs = userCreatedAtMs;
    for (int i = history.length - 1; i >= 0; i--) {
      if ((turnCreatedAtMs ?? 0) > 0) break;
      final AIMessage m = history[i];
      if (m.role == 'user' &&
          _stripComposerImageMarkersForPrompt(m.content) ==
              userMessage.trim()) {
        turnCreatedAtMs = m.createdAt.millisecondsSinceEpoch;
        break;
      }
    }
    if (_isConversationPersistenceBlockedOrStale(
      cid: cid,
      createdAtMs: turnCreatedAtMs,
    )) {
      return;
    }

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
          if (_isConversationPersistenceBlockedOrStale(
            cid: cid,
            createdAtMs: turnCreatedAtMs,
          )) {
            return;
          }
          final List<AIMessage> merged = mergeCompletedTurnIntoHistory(
            existingHistory: existing,
            userMessage: localUserMessage,
            assistantFinal: assistant,
          );
          await _settings.saveChatHistoryByCid(cid, merged);
          mergedTail = merged;
          didSaveTail = true;
        }
      } catch (_) {}
    }
    await _updateConversationModel(cid, modelUsed);
    if (_isConversationPersistenceBlockedOrStale(
      cid: cid,
      createdAtMs: turnCreatedAtMs,
    )) {
      return;
    }

    final List<AIMessage> historyForContext = mergedTail ?? history;
    final String userTrim = userMessage.trim();
    int? userAtMs;
    int? assistantAtMs;
    if (userTrim.isNotEmpty && historyForContext.isNotEmpty) {
      try {
        int userIdx = -1;
        for (int i = historyForContext.length - 1; i >= 0; i--) {
          final AIMessage m = historyForContext[i];
          if (m.role == 'user' &&
              _stripComposerImageMarkersForPrompt(m.content) == userTrim) {
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
      if (_isConversationPersistenceBlockedOrStale(
        cid: cid,
        createdAtMs: turnCreatedAtMs,
      )) {
        return;
      }
      // Keep a separate append-only transcript + compacted memory for long chats.
      try {
        await _chatContext.seedFromChatHistoryIfEmpty(
          cid: cid,
          history: history,
        );
        await _chatContext.appendCompletedTurn(
          cid: cid,
          userMessage: localUserMessage,
          assistantMessage: assistant.content,
          userCreatedAtMs: userAtMs,
          assistantCreatedAtMs: assistantAtMs,
        );
        if (_isConversationPersistenceBlockedOrStale(
          cid: cid,
          createdAtMs: turnCreatedAtMs,
        )) {
          return;
        }
        if (toolSignatureDigests.isNotEmpty) {
          await _chatContext.mergeToolDigests(
            cid: cid,
            signatureDigests: toolSignatureDigests,
          );
        }
        if (_isConversationPersistenceBlockedOrStale(
          cid: cid,
          createdAtMs: turnCreatedAtMs,
        )) {
          return;
        }
        final List<AIMessage> rawToAppend = <AIMessage>[
          AIMessage(
            role: 'user',
            content: localUserMessage,
            apiContent: userApiContent,
          ),
          ...rawTurnTranscript,
          AIMessage(
            role: 'assistant',
            content: assistant.content,
            reasoningContent: assistant.reasoningContent,
            reasoningDuration: assistant.reasoningDuration,
          ),
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
