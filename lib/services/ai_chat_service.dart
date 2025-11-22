import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import 'ai_request_gateway.dart';
import 'ai_settings_service.dart';
import 'flutter_logger.dart';
import 'locale_service.dart';
import 'screenshot_database.dart';

export 'ai_request_gateway.dart'
    show InvalidResponseStartException, InvalidEndpointConfigurationException;

/// 基础流事件（content/reasoning），用于流式 UI 显示“思考内容”
class AIStreamEvent {
  AIStreamEvent(this.kind, this.data);

  final String kind; // 'content' | 'reasoning'
  final String data;
}

class AIStreamingSession {
  AIStreamingSession({
    required this.stream,
    required this.completed,
  });

  final Stream<AIStreamEvent> stream;
  final Future<AIMessage> completed;
}

/// 统一 AI 对话服务，内部通过 AIRequestGateway 完成所有网络请求
class AIChatService {
  AIChatService._internal();

  static final AIChatService instance = AIChatService._internal();

  final AISettingsService _settings = AISettingsService.instance;
  final AIRequestGateway _gateway = AIRequestGateway.instance;

  static const String responseStartMarker = '<<<AI_RESPONSE_START>>>';
  static const String _responseStartInstruction =
      'Assistant protocol: Always begin your reply with the exact marker <<<AI_RESPONSE_START>>> on the first line, then output the actual answer starting on the next line. Never omit, rename, or move this marker.';

  Future<AIMessage> sendMessage(
    String userMessage, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      await FlutterLogger.nativeInfo(
        'AI',
        'sendMessage begin len=${userMessage.length}',
      );
    } catch (_) {}

    final List<AIEndpoint> endpoints =
        await _settings.getEndpointCandidates(context: 'chat');
    final List<AIMessage> history = await _settings.getChatHistory();
    final String systemPrompt = _systemPromptForLocale();
    final List<AIMessage> requestMessages = _composeMessages(
      systemMessage: systemPrompt,
      history: history,
      userMessage: userMessage,
    );

    final AIGatewayResult result = await _gateway.complete(
      endpoints: endpoints,
      messages: requestMessages,
      responseStartMarker: responseStartMarker,
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

    await _persistConversation(
      history: history,
      userMessage: userMessage,
      assistant: assistant,
      modelUsed: result.modelUsed,
    );

        return assistant;
  }

  Future<AIStreamingSession> sendMessageStreamedV2(
    String userMessage, {
    Duration timeout = const Duration(seconds: 60),
    String context = 'chat',
  }) async {
    try {
      await FlutterLogger.nativeInfo(
        'AI',
        'sendMessageStreamedV2 begin len=${userMessage.length}',
      );
    } catch (_) {}

    final List<AIEndpoint> endpoints =
        await _settings.getEndpointCandidates(context: context);
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
    Duration timeout = const Duration(seconds: 60),
    bool includeHistory = false,
    List<String> extraSystemMessages = const <String>[],
    bool persistHistory = true,
    String context = 'chat',
  }) async {
    try {
      await FlutterLogger.nativeInfo(
        'AI',
        'sendMessageStreamedV2WithDisplayOverride begin displayLen=${displayUserMessage.length} actualLen=${actualUserMessage.length}',
      );
    } catch (_) {}

    final List<AIEndpoint> endpoints =
        await _settings.getEndpointCandidates(context: context);
    final List<AIMessage> history = await _settings.getChatHistory();

    return _startStreamingSession(
      userMessage: actualUserMessage,
      displayUserMessage: displayUserMessage,
      endpoints: endpoints,
      history: history,
      requestHistory: includeHistory
          ? history.where((msg) => msg.role != 'system').toList()
          : const <AIMessage>[],
      timeout: timeout,
      context: context,
      includeHistory: includeHistory,
      persistHistory: persistHistory,
      extraSystemMessages: extraSystemMessages,
    );
  }

  Future<AIStreamingSession> _startStreamingSession({
    required String userMessage,
    required String displayUserMessage,
    required List<AIEndpoint> endpoints,
    required List<AIMessage> history,
    List<AIMessage>? requestHistory,
    Duration timeout = const Duration(seconds: 60),
    String context = 'chat',
    bool includeHistory = true,
    bool persistHistory = true,
    List<String> extraSystemMessages = const <String>[],
  }) async {
    final List<AIMessage> effectiveHistory = includeHistory
        ? (requestHistory ?? history)
        : const <AIMessage>[];
    final String systemPrompt = _systemPromptForLocale();
    final List<AIMessage> requestMessages = _composeMessages(
      systemMessage: systemPrompt,
      history: effectiveHistory,
      userMessage: userMessage,
      extraSystemMessages: extraSystemMessages,
      includeHistory: includeHistory,
    );

    final AIGatewayStreamingSession gatewaySession = _gateway.startStreaming(
      endpoints: endpoints,
      messages: requestMessages,
      responseStartMarker: responseStartMarker,
      timeout: timeout,
      logContext: context,
    );

    final Stream<AIStreamEvent> stream = gatewaySession.stream.map(
      (AIGatewayEvent event) => AIStreamEvent(event.kind, event.data),
    );
    final Future<AIMessage> completed = gatewaySession.completed.then(
      (AIGatewayResult result) async {
        final AIMessage assistant = AIMessage(
          role: 'assistant',
          content: result.content,
          reasoningContent: result.reasoning,
          reasoningDuration: result.reasoningDuration,
        );

        if (persistHistory) {
          await _persistConversation(
            history: history,
            userMessage: displayUserMessage,
            assistant: assistant,
            modelUsed: result.modelUsed,
          );
        }

        return assistant;
      },
    );

    return AIStreamingSession(stream: stream, completed: completed);
  }

  Future<AIMessage> sendMessageWithDisplayOverride(
    String displayUserMessage,
    String actualUserMessage, {
    Duration timeout = const Duration(seconds: 60),
    bool includeHistory = false,
    List<String> extraSystemMessages = const <String>[],
  }) async {
    final List<AIEndpoint> endpoints =
        await _settings.getEndpointCandidates(context: 'chat');
    final List<AIMessage> history = await _settings.getChatHistory();
    final List<AIMessage> filteredHistory = includeHistory
        ? history.where((m) => m.role != 'system').toList()
        : const <AIMessage>[];
    final String systemPrompt = _systemPromptForLocale();
    final List<AIMessage> requestMessages = _composeMessages(
      systemMessage: systemPrompt,
      history: filteredHistory,
      userMessage: actualUserMessage,
      extraSystemMessages: extraSystemMessages,
      includeHistory: includeHistory,
    );

    final AIGatewayResult result = await _gateway.complete(
      endpoints: endpoints,
      messages: requestMessages,
      responseStartMarker: responseStartMarker,
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

    await _persistConversation(
      history: history,
      userMessage: displayUserMessage,
      assistant: assistant,
      modelUsed: result.modelUsed,
      conversationTitle: displayUserMessage,
    );

        return assistant;
  }

  Future<AIMessage> sendMessageOneShot(
    String userMessage, {
    String context = 'chat',
    Duration? timeout,
  }) async {
    final List<AIEndpoint> endpoints =
        await _settings.getEndpointCandidates(context: context);
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
      responseStartMarker: responseStartMarker,
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
  }) {
    final List<AIMessage> messages = <AIMessage>[
      AIMessage(role: 'system', content: systemMessage),
      AIMessage(role: 'system', content: _responseStartInstruction),
      ...extraSystemMessages
          .where((msg) => msg.trim().isNotEmpty)
          .map((msg) => AIMessage(role: 'system', content: msg.trim())),
    ];
    if (includeHistory && history.isNotEmpty) {
      messages.addAll(
        history.map(
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
    bool persistHistory = true,
    String? conversationTitle,
  }) async {
    if (!persistHistory) return;

    final List<AIMessage> newHistory = <AIMessage>[
      ...history,
      AIMessage(role: 'user', content: userMessage),
      assistant,
    ];
    await _settings.saveChatHistoryActive(newHistory);
    await _updateConversationModel(modelUsed);

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
      await _settings.renameConversation(cid, title);
    } catch (_) {}
  }

  String _truncateTitle(String text) {
    if (text.length <= 30) return text;
    return text.substring(0, 30) + '...';
  }
}
