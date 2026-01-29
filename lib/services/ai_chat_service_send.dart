part of 'ai_chat_service.dart';

extension AIChatServiceSendExt on AIChatService {
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
    final List<AIMessage> history = await _settings.getChatHistory();
    final String cid = await _settings.getActiveConversationCid();
    // Best-effort bootstrap: seed append-only transcript from existing tail.
    try {
      await _chatContext.seedFromChatHistoryIfEmpty(cid: cid, history: history);
    } catch (_) {}

    // Prefer using the append-only transcript for prompt history so context can
    // exceed the UI tail limit.
    List<AIMessage> requestHistory = history;
    try {
      final List<AIMessage> full = await _chatContext
          .loadRecentMessagesForPrompt(
            cid: cid,
            maxTokens: AIChatService.maxHistoryPromptTokens,
          );
      if (full.isNotEmpty) requestHistory = full;
    } catch (_) {}

    final String systemPrompt = _systemPromptForLocale();
    final List<String> extras = <String>[];
    try {
      final String ctxMsg = await _chatContext.buildSystemContextMessage(
        cid: cid,
      );
      if (ctxMsg.trim().isNotEmpty) extras.add(ctxMsg.trim());
    } catch (_) {}
    String amMsg = '';
    try {
      amMsg = await AtomicMemoryService.instance.buildAtomicMemoryContextMessage(
        cid: cid,
        query: userMessage.trim(),
      );
      if (amMsg.trim().isNotEmpty) extras.add(amMsg.trim());
    } catch (_) {}
    String wmMsg = '';
    try {
      wmMsg = await _buildWorkingMemoryContextMessage(userMessage);
      if (wmMsg.trim().isNotEmpty) extras.add(wmMsg.trim());
    } catch (_) {}
    final List<AIMessage> requestMessages = _composeMessages(
      systemMessage: systemPrompt,
      history: requestHistory,
      userMessage: userMessage,
      extraSystemMessages: extras,
    );
    try {
      unawaited(
        _chatContext.recordPromptTokens(
          cid: cid,
          tokensApprox: PromptBudget.approxTokensForMessagesJson(
            requestMessages,
          ),
        ),
      );
    } catch (_) {}
    try {
      final bool amEnabled = await _settings.getAtomicMemoryInjectionEnabled();
      final bool amAutoExtract = await _settings.getAtomicMemoryAutoExtractEnabled();
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
    try {
      final bool wmEnabled = await _settings.getWorkingMemoryInjectionEnabled();
      final int wmEdgeLimit = await _settings.getWorkingMemoryEdgeLimit();
      final int wmMaxTokens = await _settings.getWorkingMemoryPromptTokens();
      unawaited(
        _chatContext.logContextEvent(
          cid: cid,
          type: 'working_memory',
          payload: <String, dynamic>{
            'enabled': wmEnabled,
            'injected': wmMsg.trim().isNotEmpty,
            'wm_tokens': PromptBudget.approxTokensForText(wmMsg),
            'wm_truncated': wmMsg.contains('…working_memory truncated…'),
            'edge_limit': wmEdgeLimit,
            'max_tokens': wmMaxTokens,
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
          history: history,
          userMessage: userMessage,
          assistant: assistant,
          modelUsed: result.modelUsed,
          toolSignatureDigests: const <String, Map<String, dynamic>>{},
        );
      } catch (_) {}
    }());

    return assistant;
  }

  Future<AIStreamingSession> sendMessageStreamedV2(
    String userMessage, {
    Duration? timeout,
    String context = 'chat',
  }) async {
    try {
      await FlutterLogger.nativeInfo(
        'AI',
        'sendMessageStreamedV2 begin len=${userMessage.length}',
      );
    } catch (_) {}

    final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
      context: context,
    );
    final List<AIMessage> history = await _settings.getChatHistory();

    return _startStreamingSession(
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
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Object? toolChoice,
    int maxToolIters =
        0, // 0 = unlimited (HARD RULE: do NOT introduce a fixed cap)
    int? toolStartMs,
    int? toolEndMs,
    bool forceToolFirstIfNoToolCalls = false,
  }) async {
    if (tools.isNotEmpty) {
      // 工具调用采用 tool-loop。模型侧请求支持流式增量输出（content/reasoning），
      // 同时在 tool-loop 过程中持续输出“当前在做什么”的进度事件。
      final StreamController<AIStreamEvent> controller =
          StreamController<AIStreamEvent>();

      bool sawContent = false;
      bool sawModelReasoning = false;
      void emitSafe(AIStreamEvent evt) {
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
            toolStartMs: toolStartMs,
            toolEndMs: toolEndMs,
            forceToolFirstIfNoToolCalls: forceToolFirstIfNoToolCalls,
            emitEvent: emitSafe,
          );
      // ignore: discarded_futures
      completed
          .then((AIMessage message) {
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
    final List<AIMessage> history = await _settings.getChatHistory();

    return _startStreamingSession(
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
    final String cid = await _settings.getActiveConversationCid();

    // Best-effort bootstrap: seed append-only transcript from existing tail.
    try {
      await _chatContext.seedFromChatHistoryIfEmpty(cid: cid, history: history);
    } catch (_) {}

    List<AIMessage> effectiveHistory = const <AIMessage>[];
    if (includeHistory) {
      // Prefer append-only transcript for prompt history.
      try {
        final List<AIMessage> full = await _chatContext
            .loadRecentMessagesForPrompt(
              cid: cid,
              maxTokens: AIChatService.maxHistoryPromptTokens,
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

    final List<String> effectiveExtras = <String>[];
    String amMsg = '';
    String wmMsg = '';
    if (context == 'chat' && persistHistory) {
      try {
        final String ctxMsg = await _chatContext.buildSystemContextMessage(
          cid: cid,
        );
        if (ctxMsg.trim().isNotEmpty) effectiveExtras.add(ctxMsg.trim());
      } catch (_) {}
      try {
        amMsg = await AtomicMemoryService.instance.buildAtomicMemoryContextMessage(
          cid: cid,
          query: userMessage.trim(),
        );
        if (amMsg.trim().isNotEmpty) effectiveExtras.add(amMsg.trim());
      } catch (_) {}
      try {
        wmMsg = await _buildWorkingMemoryContextMessage(userMessage);
        if (wmMsg.trim().isNotEmpty) effectiveExtras.add(wmMsg.trim());
      } catch (_) {}
    }
    effectiveExtras.addAll(extraSystemMessages);
    final String systemPrompt = _systemPromptForLocale();
    final List<AIMessage> requestMessages = _composeMessages(
      systemMessage: systemPrompt,
      history: effectiveHistory,
      userMessage: userMessage,
      extraSystemMessages: effectiveExtras,
      includeHistory: includeHistory,
    );
    if (context == 'chat' && persistHistory) {
      try {
        unawaited(
          _chatContext.recordPromptTokens(
            cid: cid,
            tokensApprox: PromptBudget.approxTokensForMessagesJson(
              requestMessages,
            ),
          ),
        );
      } catch (_) {}
      try {
        final bool amEnabled = await _settings.getAtomicMemoryInjectionEnabled();
        final bool amAutoExtract = await _settings.getAtomicMemoryAutoExtractEnabled();
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
      try {
        final bool wmEnabled = await _settings.getWorkingMemoryInjectionEnabled();
        final int wmEdgeLimit = await _settings.getWorkingMemoryEdgeLimit();
        final int wmMaxTokens = await _settings.getWorkingMemoryPromptTokens();
        unawaited(
          _chatContext.logContextEvent(
            cid: cid,
            type: 'working_memory',
            payload: <String, dynamic>{
              'enabled': wmEnabled,
              'injected': wmMsg.trim().isNotEmpty,
              'wm_tokens': PromptBudget.approxTokensForText(wmMsg),
              'wm_truncated': wmMsg.contains('…working_memory truncated…'),
              'edge_limit': wmEdgeLimit,
              'max_tokens': wmMaxTokens,
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
              history: history,
              userMessage: displayUserMessage,
              assistant: assistant,
              modelUsed: result.modelUsed,
              toolSignatureDigests: const <String, Map<String, dynamic>>{},
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
    int? toolStartMs,
    int? toolEndMs,
    bool forceToolFirstIfNoToolCalls = false,
    void Function(AIStreamEvent event)? emitEvent,
  }) async {
    if (tools.isNotEmpty) {
      _emitProgress(emitEvent, _loc('准备 agent loop…', 'Preparing agent loop…'));
    }
    final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
      context: context,
    );
    final List<AIMessage> history = await _settings.getChatHistory();
    final String cid = await _settings.getActiveConversationCid();
    // Best-effort bootstrap: seed append-only transcript from existing tail.
    try {
      await _chatContext.seedFromChatHistoryIfEmpty(cid: cid, history: history);
    } catch (_) {}

    List<AIMessage> filteredHistory = const <AIMessage>[];
    if (includeHistory) {
      // Prefer append-only transcript for prompt history.
      try {
        final List<AIMessage> full = await _chatContext
            .loadRecentMessagesForPrompt(
              cid: cid,
              maxTokens: AIChatService.maxHistoryPromptTokens,
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
    final String systemPrompt = _systemPromptForLocale();
    final List<String> effectiveExtras = <String>[];
    if (tools.isNotEmpty)
      effectiveExtras.add(_buildToolUsageInstruction(tools));
    String amMsg = '';
    String wmMsg = '';
    if (context == 'chat' && persistHistory) {
      try {
        final String ctxMsg = await _chatContext.buildSystemContextMessage(
          cid: cid,
        );
        if (ctxMsg.trim().isNotEmpty) effectiveExtras.add(ctxMsg.trim());
      } catch (_) {}
      try {
        amMsg = await AtomicMemoryService.instance.buildAtomicMemoryContextMessage(
          cid: cid,
          query: actualUserMessage.trim(),
        );
        if (amMsg.trim().isNotEmpty) effectiveExtras.add(amMsg.trim());
      } catch (_) {}
      try {
        wmMsg = await _buildWorkingMemoryContextMessage(actualUserMessage);
        if (wmMsg.trim().isNotEmpty) effectiveExtras.add(wmMsg.trim());
      } catch (_) {}
    }
    effectiveExtras.addAll(extraSystemMessages);
    final List<AIMessage> requestMessages = _composeMessages(
      systemMessage: systemPrompt,
      history: filteredHistory,
      userMessage: actualUserMessage,
      extraSystemMessages: effectiveExtras,
      includeHistory: includeHistory,
    );
    if (context == 'chat' && persistHistory) {
      try {
        unawaited(
          _chatContext.recordPromptTokens(
            cid: cid,
            tokensApprox: PromptBudget.approxTokensForMessagesJson(
              requestMessages,
            ),
          ),
        );
      } catch (_) {}
      try {
        final bool amEnabled = await _settings.getAtomicMemoryInjectionEnabled();
        final bool amAutoExtract = await _settings.getAtomicMemoryAutoExtractEnabled();
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
      try {
        final bool wmEnabled = await _settings.getWorkingMemoryInjectionEnabled();
        final int wmEdgeLimit = await _settings.getWorkingMemoryEdgeLimit();
        final int wmMaxTokens = await _settings.getWorkingMemoryPromptTokens();
        unawaited(
          _chatContext.logContextEvent(
            cid: cid,
            type: 'working_memory',
            payload: <String, dynamic>{
              'enabled': wmEnabled,
              'injected': wmMsg.trim().isNotEmpty,
              'wm_tokens': PromptBudget.approxTokensForText(wmMsg),
              'wm_truncated': wmMsg.contains('…working_memory truncated…'),
              'edge_limit': wmEdgeLimit,
              'max_tokens': wmMaxTokens,
              'tool_loop': tools.isNotEmpty,
            },
          ),
        );
      } catch (_) {}
    }
    final AIMessage pinnedUserMessage = requestMessages.isNotEmpty
        ? requestMessages.last
        : AIMessage(role: 'user', content: actualUserMessage);
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
    }) async {
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
        return await completed;
      }
      return await _gateway.complete(
        endpoints: endpoints,
        messages: messages,
        responseStartMarker: AIChatService.responseStartMarker,
        timeout: timeout,
        preferStreaming: preferStreaming,
        logContext: context,
        tools: toolsForCall,
        toolChoice: toolChoiceForCall,
      );
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
      );
      working = _enforceToolLoopPromptBudget(
        working,
        pinnedUser: pinnedUserMessage,
        emitEvent: emitEvent,
      );
      result = await callModel(
        messages: working,
        toolsForCall: tools,
        toolChoiceForCall: toolChoice,
        preferStreaming: true,
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
        );
        retryMessages = _enforceToolLoopPromptBudget(
          retryMessages,
          pinnedUser: pinnedUserMessage,
          emitEvent: emitEvent,
        );
        result = await callModel(
          messages: retryMessages,
          toolsForCall: tools,
          toolChoiceForCall: toolChoice,
          preferStreaming: true,
        );
      } finally {
        retryHeartbeatStarter?.cancel();
        retryHeartbeatTicker?.cancel();
        retryReq.stop();
      }
      retryMessages = _replaceImageMessagesWithPlaceholder(
        retryMessages,
        keepMostRecent: false,
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
      working.add(
        AIMessage(
          role: 'assistant',
          content: result.content,
          toolCalls: result.toolCalls
              .map((e) => e.toOpenAIToolCallJson())
              .toList(),
        ),
      );

      final List<Map<String, dynamic>> uiTools = await Future.wait(
        result.toolCalls.map((c) async {
          final Map<String, dynamic> args = _safeJsonObject(c.argumentsJson);
          final List<String> appNames = _normalizeAppNamesArg(args);
          final List<String> appPkgs = await _resolveAppPackagesFromArgs(args);
          return <String, dynamic>{
            'call_id': c.id,
            'tool_name': c.name,
            'label': _toolCallUiLabel(c),
            if (appNames.isNotEmpty) 'app_names': appNames,
            if (appPkgs.isNotEmpty) 'app_package_names': appPkgs,
          };
        }).toList(growable: false),
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
            '运行工具 #$totalToolCalls（本轮 $idxInBatch/${result.toolCalls.length}）：${call.name}$argsSuffix',
            'Run tool #$totalToolCalls (batch $idxInBatch/${result.toolCalls.length}): ${call.name}$argsSuffix',
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
        );
        toolSw.stop();
        working.addAll(toolMsgs);
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
            '完成工具 #$totalToolCalls：${call.name}${summarySuffix}（${toolSw.elapsedMilliseconds}ms）',
            'Finished tool #$totalToolCalls: ${call.name}${summarySuffix} (${toolSw.elapsedMilliseconds}ms)',
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
                  '2) 向用户提出 2–4 个最关键的澄清问题（例如对方昵称/平台/更精确时间段/关键词/事件细节），以便下一轮检索更有针对性。\n'
                  '禁止编造证据或臆造 [evidence: ...]。',
              'Progress guard: repeated searches are yielding no new information (multiple count=0).\n'
                  'Stop calling tools (avoid loops). Instead:\n'
                  '1) Give a best-effort answer from what you have, clearly stating what lacks evidence.\n'
                  '2) Ask the user 2–4 high-signal clarification questions (nickname/platform/time window/keywords/details) so the next search can succeed.\n'
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
        );
        working = _enforceToolLoopPromptBudget(
          working,
          pinnedUser: pinnedUserMessage,
          emitEvent: emitEvent,
        );
        result = await callModel(
          messages: working,
          toolsForCall: forceNoTools ? const <Map<String, dynamic>>[] : tools,
          toolChoiceForCall: forceNoTools ? null : toolChoice,
          preferStreaming: true,
        );
      } finally {
        followHeartbeatStarter?.cancel();
        followHeartbeatTicker?.cancel();
        followReq.stop();
      }
      working = _replaceImageMessagesWithPlaceholder(
        working,
        keepMostRecent: false,
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
                    '3) 若多次检索仍为空，请不要给“很失望”的结论；先向用户确认：是否确定平台/关键词/时间范围无误，并询问可补充的线索（UP 主名/视频标题词/头像/栏目名等）。\n'
                    '确认后再给最终答复；不要臆造证据或 [evidence: ...]。',
                'Note: the last retrieval returned count=0, so you must not conclude “not found” yet.\n'
                    'Before answering, do ALL of the following:\n'
                    '1) Make at least 2 more retrieval calls (search_segments / search_screenshots_ocr / search_ai_image_meta) with alternative keywords (split words / synonyms / English).\n'
                    '2) If the overall range is large, adjust start_local/end_local to cover different windows or page via offset/limit; if the tool returns paging.prev/paging.next you may use them as well.\n'
                    '3) If results are still empty, ask the user to confirm assumptions (platform/keywords/time range) and request more clues instead of giving a flat negative conclusion.\n'
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
          );
          retryMessages = _enforceToolLoopPromptBudget(
            retryMessages,
            pinnedUser: pinnedUserMessage,
            emitEvent: emitEvent,
          );
          result = await callModel(
            messages: retryMessages,
            toolsForCall: tools,
            toolChoiceForCall: toolChoice,
            preferStreaming: true,
          );
        } finally {
          retryHeartbeatStarter?.cancel();
          retryHeartbeatTicker?.cancel();
          retryReq.stop();
        }
        retryMessages = _replaceImageMessagesWithPlaceholder(
          retryMessages,
          keepMostRecent: false,
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

    final AIMessage assistant = AIMessage(
      role: 'assistant',
      content: result.content,
      reasoningContent: result.reasoning,
      reasoningDuration: result.reasoningDuration,
    );

    if (persistHistory) {
      // Persist best-effort without blocking the tool-loop completion (stream UI depends on it).
      unawaited(() async {
        try {
          await _persistConversation(
            history: history,
            userMessage: displayUserMessage,
            assistant: assistant,
            modelUsed: result.modelUsed,
            conversationTitle: displayUserMessage,
            toolSignatureDigests: signatureDigests,
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
