import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/models/screenshot_record.dart';

import 'ai_request_gateway.dart';
import 'ai_context_budgets.dart';
import 'ai_settings_service.dart';
import 'atomic_memory_service.dart';
import 'chat_context_service.dart';
import 'flutter_logger.dart';
import 'locale_service.dart';
import 'prompt_budget.dart';
import 'screenshot_database.dart';

export 'ai_request_gateway.dart'
    show InvalidResponseStartException, InvalidEndpointConfigurationException;

part 'ai_chat_service_core.dart';
part 'ai_chat_service_prompt_budget.dart';
part 'ai_chat_service_tool_loop_support.dart';
part 'ai_chat_service_tooling.dart';
part 'ai_chat_service_tool_exec.dart';
part 'ai_chat_service_send.dart';
part 'ai_chat_service_persistence.dart';

/// 基础流事件（content/reasoning），用于流式 UI 显示“思考内容”
class AIStreamEvent {
  AIStreamEvent(this.kind, this.data);

  final String kind; // 'content' | 'reasoning'
  final String data;
}

class AIStreamingSession {
  AIStreamingSession({required this.stream, required this.completed});

  final Stream<AIStreamEvent> stream;
  final Future<AIMessage> completed;
}

/// 统一 AI 对话服务，内部通过 AIRequestGateway 完成所有网络请求
class AIChatService {
  AIChatService._internal();

  static final AIChatService instance = AIChatService._internal();

  static List<Map<String, dynamic>> defaultChatTools() =>
      AIChatServiceToolingExt.defaultChatTools();

  // Keep chat history bounded by an approximate token budget (Codex-style).
  // This is in addition to the DB tail limit, and prevents a few very long
  // messages from bloating the prompt and degrading the tool loop.
  static const int maxHistoryPromptTokens = 6000;
  // Tool-loop prompt budget (approx tokens). Keep this conservative so the
  // provider doesn't silently drop earlier context (which often causes loops).
  static const int maxToolLoopPromptTokens = 24000;
  // Per tool message cap, mainly for very large JSON payloads (e.g. segment
  // detail). This is an approximate token budget (bytes/4).
  static const int maxToolMessageTokens = 12000;

  final AISettingsService _settings = AISettingsService.instance;
  final AIRequestGateway _gateway = AIRequestGateway.instance;
  final ChatContextService _chatContext = ChatContextService.instance;
  int _textToolCallSeq = 0;

  // Marker protocol is disabled. We accept plain text/JSON and parse as needed.
  static const String responseStartMarker = '';

  // To keep prompts bounded:
  // - UI context preloading uses a 7-day window (see AI settings page).
  // - OCR tools do NOT enforce a per-call time window cap; callers should constrain via
  //   start_local/end_local when needed and use limit/offset for paging.
  // - Semantic-index tools (segments AI results / ai_image_meta) can search a much wider window.
  static const int maxToolTimeSpanMs = 7 * 24 * 60 * 60 * 1000;
  static const int maxOcrToolTimeSpanMs =
      0; // 0 = unlimited (do NOT cap OCR tools)
  static const int maxSemanticToolTimeSpanMs = 365 * 24 * 60 * 60 * 1000;
}
