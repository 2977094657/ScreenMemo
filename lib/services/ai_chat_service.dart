import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:screen_memo/models/screenshot_record.dart';

import 'ai_request_gateway.dart';
import 'ai_settings_service.dart';
import 'chat_context_service.dart';
import 'flutter_logger.dart';
import 'locale_service.dart';
import 'memory_bridge_service.dart';
import 'prompt_budget.dart';
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
  AIStreamingSession({required this.stream, required this.completed});

  final Stream<AIStreamEvent> stream;
  final Future<AIMessage> completed;
}

/// 统一 AI 对话服务，内部通过 AIRequestGateway 完成所有网络请求
class AIChatService {
  AIChatService._internal();

  static final AIChatService instance = AIChatService._internal();

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

  String _buildToolUsageInstruction(List<Map<String, dynamic>> tools) {
    final Set<String> names = _extractToolNames(tools);
    final StringBuffer sb = StringBuffer();
    sb.writeln(
      _loc(
        '已启用工具调用。需要时可调用工具；不要编造工具结果。',
        'Tool calling is enabled. You MAY call tools when needed; do NOT fabricate tool results.',
      ),
    );
    sb.writeln(_loc('可用工具：', 'Available tools:'));
    for (final t in tools) {
      final fn = t['function'];
      if (fn is! Map) continue;
      final String name = (fn['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final String desc = (fn['description'] as String?)?.trim() ?? '';
      sb.writeln(desc.isEmpty ? '- $name' : '- $name: $desc');
    }
    sb.writeln(_loc('规则：', 'Rules:'));
    sb.writeln(
      _loc(
        '- 避免重复调用：不要在同一任务中反复用“相同参数”调用同一个工具；如需更多信息，必须改变参数（关键词/分页 paging/offset/时间窗）。',
        '- Avoid repetition: do NOT repeatedly call the same tool with the SAME arguments in the same task. If you need more information, you MUST change parameters (keywords / paging / offset / time window).',
      ),
    );
    sb.writeln(
      _loc(
        '- 回答若涉及用户本地记录（聊天/转账/截图内容等），请在关键结论处附上证据引用 [evidence: X]（X 必须是工具返回或上下文提供的截图 filename）。禁止编造证据。',
        '- If your answer relies on the user’s local records (chats/transfers/screenshot contents), attach evidence references [evidence: X] for key claims (X must be a screenshot filename from tool outputs or provided context). Do not fabricate evidence.',
      ),
    );
    final bool hasRetrievalTools =
        names.contains('search_segments') ||
        names.contains('search_screenshots_ocr') ||
        names.contains('search_ai_image_meta');
    if (hasRetrievalTools) {
      sb.writeln(
        _loc(
          '- 对于“查找/定位用户历史记录”的问题，优先调用检索类工具，不要猜。',
          '- For lookup tasks (find/identify something in the user history), prefer calling retrieval tools first. Do not guess.',
        ),
      );
      sb.writeln(
        _loc(
          '- 时间字段：调用工具时使用 start_local/end_local；工具返回也会包含 *_local。请直接使用这些本地时间字符串，不要自己换算/推导 epoch 毫秒。',
          '- Time fields: when calling tools use start_local/end_local; tool outputs include *_local. Use these local datetime strings directly; do NOT manually convert/derive epoch milliseconds.',
        ),
      );
      if (names.contains('search_ai_image_meta')) {
        sb.writeln(
          _loc(
            '- 若 OCR 检索为空或缺失，可尝试使用 search_ai_image_meta。',
            '- If OCR search yields nothing (or OCR is missing), try search_ai_image_meta.',
          ),
        );
      }
      sb.writeln(
        _loc(
          '- 若检索工具返回 count=0，不要立刻下“未找到”的结论；请更换关键词/工具或使用 paging 继续检索。',
          '- If a search tool returns count=0, do NOT immediately conclude “not found”. Try more searches (different keywords/tools + paging) before answering.',
        ),
      );
      sb.writeln(
        _loc(
          '- 进展护栏：如果多次检索都没有带来“新信息”（反复 count=0 / 反复相同结论），请停止继续调用工具，改为基于现有结果给出最佳努力答复，并明确不确定之处（避免陷入循环）。',
          '- Progress guard: if repeated searches are not yielding NEW information (repeated count=0 / same conclusion), STOP calling tools and answer best-effort with clear uncertainty (avoid tool-calling loops).',
        ),
      );
      sb.writeln(
        _loc(
          '- 统计/次数类问题：优先使用工具返回的 total_count/has_more（例如 search_screenshots_ocr）；不要为了“统计”而把时间窗硬拆成多次调用（除非 has_more=true 且你需要分页查看更多样例）。',
          '- Count/how-many questions: prefer tool-provided total_count/has_more (e.g. search_screenshots_ocr). Do NOT split time windows just to count (unless has_more=true and you need to page for more examples).',
        ),
      );
    }
    if (names.contains('search_memory_graph')) {
      sb.writeln(
        _loc(
          '- 若问题需要“长期记忆/用户画像/关系链”类信息，可调用 search_memory_graph 再回答。',
          '- For questions about long-term memory / user profile / relationship chains, consider calling search_memory_graph before answering.',
        ),
      );
    }
    if (names.contains('get_images')) {
      sb.writeln(
        _loc(
          '- 优先使用文本工具；只有确实需要像素级确认时才调用 get_images。',
          '- Prefer text tools first; call get_images ONLY when pixel-level confirmation is necessary.',
        ),
      );
      sb.writeln(
        _loc(
          '- get_images 限制：单次最多 15 张，总 payload <= 10MB。',
          '- get_images limits: at most 15 images per call, total image payload <= 10MB.',
        ),
      );
    }
    return sb.toString().trim();
  }

  bool _isZhLocale() =>
      _effectivePromptLocale().languageCode.toLowerCase().startsWith('zh');

  String _loc(String zh, String en) => _isZhLocale() ? zh : en;

  String _oneLine(String text) =>
      text.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();

  String _clipLine(String text, {int maxLen = 180}) {
    final String t = _oneLine(text);
    if (t.length <= maxLen) return t;
    return t.substring(0, maxLen) + '…';
  }

  bool _contentLooksLikeItReferencesEvidence(String content) {
    final String t = content.trim();
    if (t.isEmpty) return false;
    final String low = t.toLowerCase();
    if (low.contains('<function_calls') || low.contains('<invoke')) return true;
    return false;
  }

  bool _contentLooksLikeHardNoResultsConclusion(String content) {
    final String t = content.trim();
    if (t.isEmpty) return false;

    // If it already asks the user for confirmation/details, do not treat it as
    // a hard conclusion.
    final String low = t.toLowerCase();
    final bool asksUser =
        t.contains('?') ||
        t.contains('？') ||
        t.contains('请确认') ||
        t.contains('请问') ||
        t.contains('能否') ||
        t.contains('是否') ||
        low.contains('are you sure') ||
        low.contains('could you') ||
        low.contains('can you') ||
        low.contains('please confirm');
    if (asksUser) return false;

    if (low.contains('no data for the specified date/time window')) return true;

    // English common “not found” conclusions
    if (RegExp(
      r"\b(no data|not found|did not find|didn't find|unable to find|cannot find)\b",
    ).hasMatch(low)) {
      return true;
    }

    // Chinese common “not found” conclusions
    const List<String> zh = <String>[
      '没有找到',
      '未找到',
      '找不到',
      '没有搜到',
      '未搜到',
      '没有查询到',
      '未查询到',
      '未能找到',
      '没有匹配',
      '无匹配',
      '没有相关',
      '暂无相关',
      '没有相关记录',
      '没有找到相关',
      '没有关于',
      '未发现',
      '没有发现',
      '无记录',
      '没有记录',
      '未检索到',
    ];
    for (final String k in zh) {
      if (t.contains(k)) return true;
    }
    return false;
  }

  Set<String> _extractToolNames(List<Map<String, dynamic>> tools) {
    final Set<String> out = <String>{};
    for (final t in tools) {
      final fn = t['function'];
      if (fn is Map) {
        final String name = (fn['name'] as String?)?.trim() ?? '';
        if (name.isNotEmpty) out.add(name);
      }
    }
    return out;
  }

  bool _apiContentHasImageParts(Object? apiContent) {
    if (apiContent is! List) return false;
    for (final p in apiContent) {
      if (p is Map) {
        final String type = (p['type'] ?? '').toString();
        if (type == 'image_url') return true;
      }
    }
    return false;
  }

  List<Object?> _sanitizeApiContentForTokenEstimate(Object? apiContent) {
    if (apiContent is! List) return const <Object?>[];
    final List<Object?> out = <Object?>[];
    for (final p in apiContent) {
      if (p is! Map) {
        out.add(p);
        continue;
      }
      final String type = (p['type'] ?? '').toString();
      if (type == 'image_url') {
        out.add(<String, Object?>{
          'type': 'image_url',
          'image_url': const <String, Object?>{'url': '<image>'},
        });
        continue;
      }
      if (type == 'text') {
        out.add(<String, Object?>{
          'type': 'text',
          'text': (p['text'] ?? '').toString(),
        });
        continue;
      }
      out.add(<String, Object?>{'type': type});
    }
    return out;
  }

  int _approxTokensForToolLoopMessage(AIMessage message) {
    // Token estimation here must NOT count base64 image payloads as tokens.
    // Otherwise the tool loop will think it is “over budget” immediately after
    // a get_images call and start trimming / looping.
    try {
      final Map<String, dynamic> json = message.toJson();
      final Object? c = json['content'];
      if (c is List) {
        json['content'] = _sanitizeApiContentForTokenEstimate(c);
      }
      return PromptBudget.approxTokensForText(jsonEncode(json));
    } catch (_) {
      final String fallback = message.apiContent == null
          ? message.content
          : (_apiContentHasImageParts(message.apiContent)
                ? '<image parts omitted>'
                : '<structured content>');
      return PromptBudget.approxTokensForText('${message.role}\n$fallback');
    }
  }

  int _approxTokensForToolLoopMessages(List<AIMessage> messages) {
    int total = 0;
    for (final m in messages) {
      total += _approxTokensForToolLoopMessage(m);
    }
    return total;
  }

  String _imageMessagePlaceholderText(AIMessage message) {
    final Object? api = message.apiContent;
    if (api is! List) {
      return _loc(
        '（历史图片已省略，以控制上下文大小；如需再次分析请重新调用 get_images。）',
        '(Previous images omitted to keep context small; call get_images again if needed.)',
      );
    }
    final List<String> names = <String>[];
    for (final p in api) {
      if (p is! Map) continue;
      if ((p['type'] ?? '').toString() != 'text') continue;
      final String t = (p['text'] ?? '').toString();
      if (t.startsWith('Filename: ')) {
        final String name = t.substring('Filename: '.length).trim();
        if (name.isNotEmpty) names.add(name);
      }
    }
    if (names.isEmpty) {
      return _loc(
        '（历史图片已省略，以控制上下文大小；如需再次分析请重新调用 get_images。）',
        '(Previous images omitted to keep context small; call get_images again if needed.)',
      );
    }
    const int maxNames = 10;
    final List<String> head = names.take(maxNames).toList();
    final int more = names.length - head.length;
    final String suffix = more > 0 ? ' +$more' : '';
    return _loc(
      '（已在上一轮提供图片：${head.join(", ")}$suffix；为避免重复上传，本轮起仅保留文件名。如需再次查看像素请重新调用 get_images。）',
      '(Images were provided earlier: ${head.join(", ")}$suffix; to avoid re-upload, only filenames are kept. Call get_images again if you need pixels.)',
    );
  }

  /// Replace (some) multimodal image messages with a compact placeholder so we
  /// don't re-upload base64 images on every follow-up call inside the tool loop.
  List<AIMessage> _replaceImageMessagesWithPlaceholder(
    List<AIMessage> messages, {
    required bool keepMostRecent,
  }) {
    int lastIdx = -1;
    for (int i = messages.length - 1; i >= 0; i--) {
      final AIMessage m = messages[i];
      if (m.role == 'user' && _apiContentHasImageParts(m.apiContent)) {
        lastIdx = i;
        break;
      }
    }
    if (lastIdx < 0) return messages;

    bool changed = false;
    final List<AIMessage> out = List<AIMessage>.from(messages);
    for (int i = 0; i < out.length; i++) {
      if (keepMostRecent && i == lastIdx) continue;
      final AIMessage m = out[i];
      if (m.role != 'user' || !_apiContentHasImageParts(m.apiContent)) continue;
      changed = true;
      out[i] = AIMessage(
        role: 'user',
        content: _imageMessagePlaceholderText(m),
        createdAt: m.createdAt,
      );
    }
    return changed ? out : messages;
  }

  String _compactToolContentForPrompt(String content) {
    if (content.trim().isEmpty) return content;
    final int maxBytes =
        maxToolMessageTokens * PromptBudget.approxBytesPerToken;

    if (PromptBudget.utf8Bytes(content) <= maxBytes) return content;

    // Best-effort: keep it JSON-ish if possible by trimming large lists/strings.
    try {
      final dynamic root = jsonDecode(content);
      dynamic compact(dynamic v, int depth) {
        if (depth > 6) return '…omitted…';
        if (v is String) {
          const int maxStringBytes = 12 * 1024;
          if (PromptBudget.utf8Bytes(v) <= maxStringBytes) return v;
          return PromptBudget.truncateTextByBytes(
            text: v,
            maxBytes: maxStringBytes,
            marker: '…truncated…',
          );
        }
        if (v is List) {
          const int maxList = 30;
          if (v.length <= maxList) {
            return v.map((e) => compact(e, depth + 1)).toList(growable: false);
          }
          const int head = 20;
          const int tail = 5;
          final int omitted = v.length - head - tail;
          final List<dynamic> out = <dynamic>[];
          out.addAll(
            v.take(head).map((e) => compact(e, depth + 1)),
          );
          out.add('…omitted $omitted items…');
          out.addAll(
            v.skip(v.length - tail).map((e) => compact(e, depth + 1)),
          );
          return out;
        }
        if (v is Map) {
          final Map<String, dynamic> out = <String, dynamic>{};
          for (final e in v.entries) {
            out[e.key.toString()] = compact(e.value, depth + 1);
          }
          return out;
        }
        return v;
      }

      final String encoded = jsonEncode(compact(root, 0));
      if (PromptBudget.utf8Bytes(encoded) <= maxBytes) return encoded;
      return PromptBudget.truncateTextByBytes(
        text: encoded,
        maxBytes: maxBytes,
        marker: '…truncated…',
      );
    } catch (_) {
      return PromptBudget.truncateTextByBytes(
        text: content,
        maxBytes: maxBytes,
        marker: '…truncated…',
      );
    }
  }

  List<AIMessage> _compactToolMessagesForPrompt(List<AIMessage> toolMsgs) {
    bool changed = false;
    final List<AIMessage> out = <AIMessage>[];
    for (final m in toolMsgs) {
      if (m.role == 'tool') {
        final String compacted = _compactToolContentForPrompt(m.content);
        if (compacted != m.content) changed = true;
        out.add(
          AIMessage(
            role: 'tool',
            content: compacted,
            toolCallId: m.toolCallId,
            createdAt: m.createdAt,
          ),
        );
      } else {
        out.add(m);
      }
    }
    return changed ? out : toolMsgs;
  }

  int _findToolLoopPinnedUserIndex(List<AIMessage> messages, AIMessage pinned) {
    final int byId = messages.indexWhere((m) => identical(m, pinned));
    if (byId >= 0) return byId;
    // Fallback: best-effort keep the last user message as the task prompt.
    final int idx = messages.lastIndexWhere((m) => m.role == 'user');
    return idx >= 0 ? idx : 0;
  }

  int _findOldestToolChunkStartAfter(List<AIMessage> messages, int afterIdx) {
    for (int i = afterIdx + 1; i < messages.length; i++) {
      final AIMessage m = messages[i];
      if (m.role == 'assistant' && (m.toolCalls?.isNotEmpty ?? false)) {
        return i;
      }
    }
    return -1;
  }

  int _findToolChunkEnd(List<AIMessage> messages, int chunkStart) {
    for (int i = chunkStart + 1; i < messages.length; i++) {
      if (messages[i].role == 'assistant') return i;
    }
    return messages.length;
  }

  /// Enforce a Codex-style prompt budget for the *tool loop transcript* (system
  /// + task prompt + tool call/results + internal guard rails).
  ///
  /// This prevents provider-side truncation (which often looks like “the model
  /// forgot tool results and keeps searching again”), while preserving tool call
  /// protocol invariants by removing whole tool-call chunks.
  List<AIMessage> _enforceToolLoopPromptBudget(
    List<AIMessage> messages, {
    required AIMessage pinnedUser,
    required void Function(AIStreamEvent event)? emitEvent,
  }) {
    int totalTokens = _approxTokensForToolLoopMessages(messages);
    if (totalTokens <= maxToolLoopPromptTokens) return messages;

    final int before = totalTokens;
    int droppedHistory = 0;
    int droppedChunks = 0;

    List<AIMessage> working = List<AIMessage>.from(messages);

    while (true) {
      totalTokens = _approxTokensForToolLoopMessages(working);
      if (totalTokens <= maxToolLoopPromptTokens) break;

      int sysEnd = 0;
      while (sysEnd < working.length && working[sysEnd].role == 'system') {
        sysEnd += 1;
      }

      final int pinnedIdx = _findToolLoopPinnedUserIndex(working, pinnedUser);

      // 1) Drop oldest history messages first (between system prefix and pinned user).
      if (pinnedIdx > sysEnd) {
        working.removeAt(sysEnd);
        droppedHistory += 1;
        continue;
      }

      // 2) Drop the oldest completed tool-call chunk after the pinned user.
      final int chunkStart = _findOldestToolChunkStartAfter(working, pinnedIdx);
      if (chunkStart >= 0) {
        final int chunkEnd = _findToolChunkEnd(working, chunkStart);
        if (chunkEnd > chunkStart) {
          working.removeRange(chunkStart, chunkEnd);
          droppedChunks += 1;
          continue;
        }
      }

      // 3) Nothing left to drop safely.
      break;
    }

    // As a last resort, truncate the oldest kept non-system message content.
    totalTokens = _approxTokensForToolLoopMessages(working);
    if (totalTokens > maxToolLoopPromptTokens) {
      int sysEnd = 0;
      while (sysEnd < working.length && working[sysEnd].role == 'system') {
        sysEnd += 1;
      }
      if (sysEnd < working.length) {
        final AIMessage m = working[sysEnd];
        final int maxBytes = (maxToolLoopPromptTokens *
                PromptBudget.approxBytesPerToken *
                0.6)
            .floor();
        final String truncated = PromptBudget.truncateTextByBytes(
          text: m.content,
          maxBytes: maxBytes,
          marker: '…truncated…',
        );
        working[sysEnd] = AIMessage(
          role: m.role,
          content: truncated,
          createdAt: m.createdAt,
          toolCalls: m.toolCalls,
          toolCallId: m.toolCallId,
          apiContent: m.apiContent,
        );
      }
    }

    final int after = _approxTokensForToolLoopMessages(working);
    _emitProgress(
      emitEvent,
      _loc(
        '上下文超出预算：已裁剪 history=$droppedHistory 组、tool_chunks=$droppedChunks 组，tokens≈$before → $after。',
        'Context over budget: trimmed history=$droppedHistory, tool_chunks=$droppedChunks, tokens≈$before → $after.',
      ),
    );
    return working;
  }

  AIGatewayResult _maybeCoerceToolCallsFromText(
    AIGatewayResult result,
    List<Map<String, dynamic>> tools,
  ) {
    if (result.toolCalls.isNotEmpty) return result;
    final String content = result.content;
    if (content.isEmpty) return result;

    final Set<String> allowedTools = _extractToolNames(tools);
    if (allowedTools.isEmpty) return result;

    final ({List<AIToolCall> calls, String cleaned}) parsed =
        _tryParseTextToolCalls(content, allowedTools);
    if (parsed.calls.isEmpty) return result;

    return AIGatewayResult(
      content: parsed.cleaned,
      modelUsed: result.modelUsed,
      toolCalls: parsed.calls,
      reasoning: result.reasoning,
      reasoningDuration: result.reasoningDuration,
    );
  }

  ({List<AIToolCall> calls, String cleaned}) _tryParseTextToolCalls(
    String content,
    Set<String> allowedTools,
  ) {
    // Some models (or provider adapters) output tool calls in plain text using
    // XML-like wrappers, but they may omit closing tags. We try to salvage
    // those tool calls and keep only the user-visible prose.
    String scan = content;
    String cleanedCandidate = content;
    bool hasWrapper = false;

    final RegExp wrapperOpenRe = RegExp(
      r'<function_calls\b[^>]*>',
      caseSensitive: false,
    );
    final RegExp wrapperCloseRe = RegExp(
      r'</function_calls\s*>',
      caseSensitive: false,
    );
    final RegExpMatch? wrapperOpen = wrapperOpenRe.firstMatch(content);
    if (wrapperOpen != null) {
      hasWrapper = true;
      final int start = wrapperOpen.start;
      int end = content.length;
      final RegExpMatch? wrapperClose = wrapperCloseRe.firstMatch(
        content.substring(wrapperOpen.end),
      );
      if (wrapperClose != null) {
        end = wrapperOpen.end + wrapperClose.end;
      }
      scan = content.substring(start, end);
      cleanedCandidate = (content.substring(0, start) + content.substring(end))
          .trim();
    }

    final RegExp invokeOpenRe = RegExp(
      r'<invoke\b[^>]*>',
      caseSensitive: false,
    );
    final RegExp invokeCloseRe = RegExp(r'</invoke\s*>', caseSensitive: false);
    final List<RegExpMatch> invokeOpens = invokeOpenRe
        .allMatches(scan)
        .toList();
    if (invokeOpens.isEmpty) {
      return (calls: const <AIToolCall>[], cleaned: content);
    }

    final List<({int start, int end, String block})> invokeBlocks =
        <({int start, int end, String block})>[];
    for (int i = 0; i < invokeOpens.length; i++) {
      final RegExpMatch om = invokeOpens[i];
      final int start = om.start;
      final int nextStart = (i + 1 < invokeOpens.length)
          ? invokeOpens[i + 1].start
          : scan.length;

      int end = nextStart;
      final RegExpMatch? close = invokeCloseRe.firstMatch(
        scan.substring(om.end),
      );
      if (close != null) {
        final int closeStartAbs = om.end + close.start;
        final int closeEndAbs = om.end + close.end;
        if (closeStartAbs <= nextStart) {
          end = closeEndAbs;
        }
      }

      if (end <= start) continue;
      final String block = scan.substring(start, end);
      invokeBlocks.add((start: start, end: end, block: block));
    }
    if (invokeBlocks.isEmpty) {
      return (calls: const <AIToolCall>[], cleaned: content);
    }

    final List<AIToolCall> out = <AIToolCall>[];
    for (final b in invokeBlocks) {
      final String block = b.block;
      if (block.trim().isEmpty) continue;

      String name = '';
      final RegExp nameRe = RegExp(
        r'''\bname\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      );
      final RegExpMatch? nameM = nameRe.firstMatch(block);
      if (nameM != null) name = (nameM.group(1) ?? '').trim();
      if (name.isEmpty) {
        final RegExp toolRe = RegExp(
          r'''\btool\s*=\s*["']([^"']+)["']''',
          caseSensitive: false,
        );
        final RegExpMatch? toolM = toolRe.firstMatch(block);
        if (toolM != null) name = (toolM.group(1) ?? '').trim();
      }
      if (name.isEmpty || !allowedTools.contains(name)) continue;

      final Map<String, dynamic> args = <String, dynamic>{};

      // 1) Normal form: <parameter name="x">value</parameter>
      final RegExp paramRe = RegExp(
        r'''<parameter\b[^>]*\bname\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</parameter>''',
        caseSensitive: false,
      );
      for (final pm in paramRe.allMatches(block)) {
        final String key = (pm.group(1) ?? '').trim();
        if (key.isEmpty) continue;
        final String raw = (pm.group(2) ?? '').trim();
        final dynamic value = _parseLooseValue(raw);
        if (!args.containsKey(key)) {
          args[key] = value;
          continue;
        }
        final existing = args[key];
        if (existing is List) {
          existing.add(value);
        } else {
          args[key] = <dynamic>[existing, value];
        }
      }

      // 2) Tolerate missing </parameter>: <parameter name="x">value\n
      if (args.isEmpty) {
        final RegExp paramOpenRe = RegExp(
          r'''<parameter\b[^>]*\bname\s*=\s*["']([^"']+)["'][^>]*>''',
          caseSensitive: false,
        );
        final List<RegExpMatch> opens = paramOpenRe.allMatches(block).toList();
        for (int i = 0; i < opens.length; i++) {
          final RegExpMatch pm = opens[i];
          final String key = (pm.group(1) ?? '').trim();
          if (key.isEmpty) continue;
          if (args.containsKey(key)) continue;

          int valueEnd = block.length;
          if (i + 1 < opens.length) {
            valueEnd = opens[i + 1].start;
          }
          final RegExpMatch? close = RegExp(
            r'</parameter\s*>',
            caseSensitive: false,
          ).firstMatch(block.substring(pm.end, valueEnd));
          if (close != null) {
            valueEnd = pm.end + close.start;
          }
          final String raw = block.substring(pm.end, valueEnd).trim();
          if (raw.isEmpty) continue;
          args[key] = _parseLooseValue(raw);
        }
      }

      // 3) Fallback: some models dump a raw JSON object as "arguments".
      if (args.isEmpty) {
        final int firstBrace = block.indexOf('{');
        final int lastBrace = block.lastIndexOf('}');
        if (firstBrace >= 0 && lastBrace > firstBrace) {
          final String raw = block.substring(firstBrace, lastBrace + 1).trim();
          try {
            final dynamic v = jsonDecode(raw);
            if (v is Map) {
              args.addAll(Map<String, dynamic>.from(v as Map));
            }
          } catch (_) {}
        }
      }

      out.add(
        AIToolCall(
          id: 'toolu_text_${++_textToolCallSeq}',
          name: name,
          argumentsJson: jsonEncode(args),
        ),
      );
    }
    if (out.isEmpty) {
      return (calls: const <AIToolCall>[], cleaned: content);
    }

    String cleaned = content;
    if (hasWrapper) {
      cleaned = cleanedCandidate;
    } else {
      // Remove the detected <invoke ...> blocks from the visible content.
      final List<({int start, int end})> ranges =
          invokeBlocks.map((b) => (start: b.start, end: b.end)).toList()
            ..sort((a, b) => b.start.compareTo(a.start));
      String t = content;
      for (final r in ranges) {
        if (r.start < 0 || r.end > t.length || r.end <= r.start) continue;
        t = t.substring(0, r.start) + t.substring(r.end);
      }
      cleaned = t.trim();
    }

    return (calls: out, cleaned: cleaned);
  }

  dynamic _parseLooseValue(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return '';
    final int? i = int.tryParse(t);
    if (i != null) return i;
    final double? d = double.tryParse(t);
    if (d != null) return d;
    final String lower = t.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
    if ((t.startsWith('{') && t.endsWith('}')) ||
        (t.startsWith('[') && t.endsWith(']'))) {
      try {
        return jsonDecode(t);
      } catch (_) {}
    }
    return t;
  }

  void _emitProgress(
    void Function(AIStreamEvent event)? emitEvent,
    String message, {
    bool bullet = true,
  }) {
    if (emitEvent == null) return;
    final String prefix = bullet ? '- ' : '';
    final String line = message.endsWith('\n') ? message : '$message\n';
    emitEvent(AIStreamEvent('reasoning', prefix + line));
  }

  ({
    int startMs,
    int endMs,
    bool clampedToGuard,
    bool guardApplied,
    bool clampedToMaxSpan,
  })
  _resolveToolTimeRange({
    required int defaultStartMs,
    required int defaultEndMs,
    int? startMs,
    int? endMs,
    int? guardStartMs,
    int? guardEndMs,
    int maxSpanMs = AIChatService.maxToolTimeSpanMs,
  }) {
    final bool hasGuard =
        (guardStartMs != null &&
        guardEndMs != null &&
        guardStartMs > 0 &&
        guardEndMs >= guardStartMs);
    final bool hasStartArg = (startMs != null && startMs > 0);
    final bool hasEndArg = (endMs != null && endMs > 0);
    int s = (startMs != null && startMs > 0)
        ? startMs
        : (hasGuard ? guardStartMs! : defaultStartMs);
    int e = (endMs != null && endMs > 0)
        ? endMs
        : (hasGuard ? guardEndMs! : defaultEndMs);

    if (s > e) {
      final int tmp = s;
      s = e;
      e = tmp;
    }

    bool clamped = false;
    if (hasGuard) {
      final int gs = guardStartMs!;
      final int ge = guardEndMs!;
      final int beforeS = s;
      final int beforeE = e;
      if (s < gs) s = gs;
      if (e > ge) e = ge;
      if (s > e) {
        s = gs;
        e = ge;
      }
      clamped = (s != beforeS) || (e != beforeE);
    }

    bool clampedToMaxSpan = false;
    if (maxSpanMs > 0) {
      final int span = e - s;
      if (span > maxSpanMs) {
        clampedToMaxSpan = true;
        // Prefer preserving explicit boundary: if only start_ms is given, keep it; otherwise keep end_ms.
        if (hasStartArg && !hasEndArg) {
          e = s + maxSpanMs;
        } else {
          s = e - maxSpanMs;
        }
        if (hasGuard) {
          final int gs = guardStartMs!;
          final int ge = guardEndMs!;
          if (s < gs) s = gs;
          if (e > ge) e = ge;
          if (s > e) {
            s = gs;
            e = ge;
          }
        }
      }
    }
    return (
      startMs: s,
      endMs: e,
      clampedToGuard: clamped,
      guardApplied: hasGuard,
      clampedToMaxSpan: clampedToMaxSpan,
    );
  }

  String _formatLocalDateTimeForTool(int epochMs) {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _formatLocalRangeForTool(int startMs, int endMs) {
    return '${_formatLocalDateTimeForTool(startMs)}–${_formatLocalDateTimeForTool(endMs)}';
  }

  Map<String, dynamic> _buildWeeklyPagingHint({
    required int servedStartMs,
    required int servedEndMs,
    int maxSpanMs = AIChatService.maxToolTimeSpanMs,
    int? guardStartMs,
    int? guardEndMs,
  }) {
    final int? gs = (guardStartMs != null && guardStartMs > 0)
        ? guardStartMs
        : null;
    final int? ge = (guardEndMs != null && guardEndMs > 0) ? guardEndMs : null;

    final Map<String, dynamic> out = <String, dynamic>{
      'max_span_ms': maxSpanMs,
      'max_span_days': (maxSpanMs / const Duration(days: 1).inMilliseconds)
          .round(),
      'served': <String, String>{
        'start_local': _formatLocalDateTimeForTool(servedStartMs),
        'end_local': _formatLocalDateTimeForTool(servedEndMs),
      },
    };

    // Previous week window: [servedStart-1-maxSpan, servedStart-1]
    final int prevEnd0 = servedStartMs - 1;
    if (prevEnd0 > 0 && (gs == null || prevEnd0 >= gs)) {
      int prevEnd = prevEnd0;
      int prevStart = prevEnd - maxSpanMs;
      if (gs != null && prevStart < gs) prevStart = gs;
      if (prevStart > prevEnd) prevStart = prevEnd;
      out['prev'] = <String, String>{
        'start_local': _formatLocalDateTimeForTool(prevStart),
        'end_local': _formatLocalDateTimeForTool(prevEnd),
      };
    }

    // Next week window: [servedEnd+1, servedEnd+1+maxSpan]
    final int nextStart0 = servedEndMs + 1;
    if (nextStart0 > 0 && (ge == null || nextStart0 <= ge)) {
      int nextStart = nextStart0;
      int nextEnd = nextStart + maxSpanMs;
      if (ge != null && nextEnd > ge) nextEnd = ge;
      if (nextStart > nextEnd) nextStart = nextEnd;
      out['next'] = <String, String>{
        'start_local': _formatLocalDateTimeForTool(nextStart),
        'end_local': _formatLocalDateTimeForTool(nextEnd),
      };
    }

    return out;
  }

  bool _shouldOfferWeeklyPagingHint({
    int? guardStartMs,
    int? guardEndMs,
    int maxSpanMs = AIChatService.maxToolTimeSpanMs,
  }) {
    if (guardStartMs == null || guardEndMs == null) return false;
    if (guardStartMs <= 0 || guardEndMs <= 0) return false;
    return (guardEndMs - guardStartMs).abs() > maxSpanMs;
  }

  String _summarizeToolMessages(List<AIMessage> toolMsgs) {
    if (toolMsgs.isEmpty) return '';
    final Map<String, dynamic> obj = _safeJsonObject(toolMsgs.first.content);
    final String tool = (obj['tool'] as String?)?.trim() ?? '';
    final Object? error = obj['error'];
    if (error != null) return 'error=$error';
    if (tool == 'get_images') {
      final Map<String, dynamic>? stats = (obj['stats'] is Map)
          ? (obj['stats'] as Map).cast<String, dynamic>()
          : null;
      final int provided =
          _toInt(stats?['provided_count']) ?? _toInt(obj['provided']) ?? 0;
      final int missing = (obj['missing'] is List)
          ? (obj['missing'] as List).length
          : 0;
      final int skipped = (obj['skipped'] is List)
          ? (obj['skipped'] as List).length
          : 0;
      return 'provided=$provided missing=$missing skipped=$skipped';
    }
    if (tool == 'get_segment_result') {
      final int sid = _toInt(obj['segment_id']) ?? 0;
      return sid > 0 ? 'segment_id=$sid' : '';
    }
    if (tool == 'get_segment_samples') {
      final int sid = _toInt(obj['segment_id']) ?? 0;
      final int count = _toInt(obj['count']) ?? 0;
      return sid > 0 ? 'segment_id=$sid count=$count' : 'count=$count';
    }
    final int count = _toInt(obj['count']) ?? -1;
    if (count >= 0) {
      final int? total = _toInt(obj['total_count']);
      if (total != null && total >= 0 && total != count) {
        return 'count=$count total=$total';
      }
      return 'count=$count';
    }
    return tool.isEmpty ? '' : 'ok';
  }

  static List<Map<String, dynamic>>
  defaultChatTools() => <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'get_images',
        'description':
            'Load local screenshot images by evidence filename (basename) so the model can visually inspect them. Use ONLY when the provided text context is insufficient.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'filenames': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{'type': 'string'},
              'description':
                  'Evidence filenames like 20251014_093112_AppA.png. Must be basenames from the provided evidence list. Request at most 15 per call, total image payload <= 10MB.',
            },
            'reason': <String, dynamic>{
              'type': 'string',
              'description': 'Why you need to see these images.',
            },
          },
          'required': <String>['filenames'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'search_segments',
        'description':
            'List/search local segments (动态) by local date/time range and optional keyword (+ optional app filter). Use start_local/end_local as human-readable local date/time strings (YYYY-MM-DD or YYYY-MM-DD HH:mm). The app will convert them to epoch ms internally. Do NOT provide epoch milliseconds. List mode is capped to 7 days per call; AI mode is capped to 365 days per call (larger windows will be clamped with paging hints). OCR mode has no per-call time limit; use start_local/end_local to constrain when needed.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'query': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional keyword. If omitted, list segments in the time range.',
            },
            'start_local': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional local start datetime. Format: YYYY-MM-DD or YYYY-MM-DD HH:mm. Example: "2025-07-02" or "2025-07-02 09:30".',
            },
            'end_local': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional local end datetime. Format: YYYY-MM-DD or YYYY-MM-DD HH:mm. Example: "2025-07-02" or "2025-07-02 18:00".',
            },
            'app_package_name': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional app package filter (e.g., tv.danmaku.bili).',
            },
            'mode': <String, dynamic>{
              'type': 'string',
              'description': 'Optional search mode: auto | ai | ocr.',
            },
            'only_no_summary': <String, dynamic>{
              'type': 'boolean',
              'description':
                  'If true, only return segments without AI summary/result.',
            },
            'limit': <String, dynamic>{
              'type': 'integer',
              'description': 'Max results (1-50).',
            },
            'offset': <String, dynamic>{
              'type': 'integer',
              'description': 'Offset for pagination (>=0).',
            },
            'per_segment_samples': <String, dynamic>{
              'type': 'integer',
              'description':
                  'For OCR mode: max matched sample filenames per segment (1-15).',
            },
          },
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'get_segment_result',
        'description':
            'Fetch a segment AI result by segment_id, including structured_json/output_text/categories and the segment time range.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'segment_id': <String, dynamic>{
              'type': 'integer',
              'description': 'Segment id.',
            },
            'max_chars': <String, dynamic>{
              'type': 'integer',
              'description':
                  'Optional max chars to return for long text fields.',
            },
          },
          'required': <String>['segment_id'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'get_segment_samples',
        'description':
            'List screenshot samples for a segment (file basenames + capture times). Use this to decide which images to request via get_images.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'segment_id': <String, dynamic>{
              'type': 'integer',
              'description': 'Segment id.',
            },
            'limit': <String, dynamic>{
              'type': 'integer',
              'description': 'Max samples to return (1-60).',
            },
          },
          'required': <String>['segment_id'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'search_screenshots_ocr',
        'description':
            'Search screenshots by OCR text within a local date/time range (+ optional app filter). Use start_local/end_local as human-readable local date/time strings (YYYY-MM-DD or YYYY-MM-DD HH:mm). The app will convert them to epoch ms internally. Do NOT provide epoch milliseconds. No per-call time limit; use start_local/end_local to constrain when needed. Returns screenshot file basenames + capture times + app info + total_count (matches in range) + has_more (for pagination).',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'query': <String, dynamic>{
              'type': 'string',
              'description': 'OCR query.',
            },
            'start_local': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional local start datetime. Format: YYYY-MM-DD or YYYY-MM-DD HH:mm. Example: "2025-07-02".',
            },
            'end_local': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional local end datetime. Format: YYYY-MM-DD or YYYY-MM-DD HH:mm. Example: "2025-07-10".',
            },
            'app_package_name': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional app package filter (restrict OCR search to that app).',
            },
            'limit': <String, dynamic>{
              'type': 'integer',
              'description': 'Max results (1-50).',
            },
            'offset': <String, dynamic>{
              'type': 'integer',
              'description': 'Offset for pagination (>=0).',
            },
          },
          'required': <String>['query'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'search_ai_image_meta',
        'description':
            'Search AI-generated per-image tags/descriptions (ai_image_meta) within a local date/time range (max 365 days per call; larger windows will be clamped with paging hints). Use start_local/end_local as human-readable local date/time strings (YYYY-MM-DD or YYYY-MM-DD HH:mm). The app will convert them to epoch ms internally. Do NOT provide epoch milliseconds. Useful when OCR is missing or insufficient.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'query': <String, dynamic>{
              'type': 'string',
              'description': 'Keyword query for tags/description.',
            },
            'start_local': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional local start datetime. Format: YYYY-MM-DD or YYYY-MM-DD HH:mm. Example: "2025-07-02".',
            },
            'end_local': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional local end datetime. Format: YYYY-MM-DD or YYYY-MM-DD HH:mm. Example: "2025-07-10".',
            },
            'app_package_name': <String, dynamic>{
              'type': 'string',
              'description':
                  'Optional app package filter (e.g., com.tencent.mm).',
            },
            'include_nsfw': <String, dynamic>{
              'type': 'boolean',
              'description': 'Whether to include NSFW results (default false).',
            },
            'limit': <String, dynamic>{
              'type': 'integer',
              'description': 'Max results (1-50).',
            },
            'offset': <String, dynamic>{
              'type': 'integer',
              'description': 'Offset for pagination (>=0).',
            },
          },
          'required': <String>['query'],
        },
      },
    },
    <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': 'search_memory_graph',
        'description':
            'Search local temporal memory graph (entities/edges/evidence). Use this to answer relationship-chain questions like “who did I work with at which company” or “how is this project related to that meeting”.',
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'query': <String, dynamic>{
              'type': 'string',
              'description':
                  'Natural language query or an entity key (e.g., person:user).',
            },
            'depth': <String, dynamic>{
              'type': 'integer',
              'description': 'Neighborhood expansion depth (1-4).',
            },
            'limit': <String, dynamic>{
              'type': 'integer',
              'description': 'Max edges to return (10-200).',
            },
            'include_history': <String, dynamic>{
              'type': 'boolean',
              'description': 'Whether to include historical (ended) edges.',
            },
          },
          'required': <String>['query'],
        },
      },
    },
  ];

  static List<Map<String, dynamic>> defaultMemoryTools() {
    final List<Map<String, dynamic>> all = defaultChatTools();
    return all
        .where((t) {
          final fn = t['function'];
          if (fn is Map) {
            final String name = (fn['name'] as String?)?.trim() ?? '';
            return name == 'search_memory_graph';
          }
          return false;
        })
        .toList(growable: false);
  }

  String _detectImageMimeByExt(String path) {
    final String p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }

  bool _looksLikeBasename(String name) {
    final String t = name.trim();
    if (t.isEmpty) return false;
    if (t.contains('/') || t.contains('\\')) return false;
    if (t.length > 200) return false;
    return true;
  }

  int? _toInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  String? _toTrimmedStringOrNull(Object? v) {
    if (v == null) return null;
    final String s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  int? _parseLocalDateTimeToEpochMs(Object? raw, {required bool isEnd}) {
    final String? t0 = _toTrimmedStringOrNull(raw);
    if (t0 == null) return null;

    // Date-only: YYYY-MM-DD (treat as start-of-day / end-of-day in local time)
    final Match? mDate = RegExp(
      r'^([12]\d{3})-(\d{1,2})-(\d{1,2})$',
    ).firstMatch(t0);
    if (mDate != null) {
      final int year = int.tryParse(mDate.group(1) ?? '') ?? 0;
      final int month = int.tryParse(mDate.group(2) ?? '') ?? 0;
      final int day = int.tryParse(mDate.group(3) ?? '') ?? 0;
      if (year <= 0 || month <= 0 || day <= 0) return null;
      final DateTime dt = isEnd
          ? DateTime(year, month, day, 23, 59, 59, 999, 0)
          : DateTime(year, month, day, 0, 0, 0, 0, 0);
      if (dt.year != year || dt.month != month || dt.day != day) return null;
      return dt.millisecondsSinceEpoch;
    }

    // Date + time: YYYY-MM-DD HH:mm[:ss] (local time)
    final Match? mDateTime = RegExp(
      r'^([12]\d{3})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$',
    ).firstMatch(t0);
    if (mDateTime != null) {
      final int year = int.tryParse(mDateTime.group(1) ?? '') ?? 0;
      final int month = int.tryParse(mDateTime.group(2) ?? '') ?? 0;
      final int day = int.tryParse(mDateTime.group(3) ?? '') ?? 0;
      final int hour = int.tryParse(mDateTime.group(4) ?? '') ?? -1;
      final int minute = int.tryParse(mDateTime.group(5) ?? '') ?? -1;
      final int second = int.tryParse(mDateTime.group(6) ?? '') ?? 0;
      if (year <= 0 || month <= 0 || day <= 0) return null;
      if (hour < 0 || hour > 23) return null;
      if (minute < 0 || minute > 59) return null;
      if (second < 0 || second > 59) return null;
      final DateTime dt = DateTime(
        year,
        month,
        day,
        hour,
        minute,
        second,
        0,
        0,
      );
      if (dt.year != year || dt.month != month || dt.day != day) return null;
      if (dt.hour != hour || dt.minute != minute || dt.second != second) {
        return null;
      }
      return dt.millisecondsSinceEpoch;
    }

    // ISO-8601 fallback: allow offsets (will be parsed into UTC), or local if no zone is provided.
    DateTime? dt = DateTime.tryParse(t0);
    if (dt == null && t0.contains(' ') && !t0.contains('T')) {
      dt = DateTime.tryParse(t0.replaceFirst(' ', 'T'));
    }
    return dt?.millisecondsSinceEpoch;
  }

  bool _toBool(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final String s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return false;
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }

  String _basename(String path) {
    final int idx1 = path.lastIndexOf('/');
    final int idx2 = path.lastIndexOf('\\');
    final int idx = idx1 > idx2 ? idx1 : idx2;
    return idx >= 0 ? path.substring(idx + 1) : path;
  }

  String _clipText(String text, int maxChars) {
    if (maxChars <= 0) return '';
    final String t = text.trim();
    if (t.isEmpty) return '';
    return t.length <= maxChars ? t : (t.substring(0, maxChars) + '…');
  }

  String _extractSegmentSummary(
    Map<String, dynamic> row, {
    int maxChars = 420,
  }) {
    final String sj = (row['structured_json'] as String?)?.trim() ?? '';
    if (sj.isNotEmpty) {
      try {
        final dynamic v = jsonDecode(sj);
        if (v is Map) {
          final Map<String, dynamic> m = Map<String, dynamic>.from(v as Map);
          final String s1 = (m['overall_summary'] as String?)?.trim() ?? '';
          if (s1.isNotEmpty) return _clipText(s1, maxChars);
          final String s2 = (m['summary'] as String?)?.trim() ?? '';
          if (s2.isNotEmpty) return _clipText(s2, maxChars);
          final String s3 = (m['notification_brief'] as String?)?.trim() ?? '';
          if (s3.isNotEmpty) return _clipText(s3, maxChars);
        }
      } catch (_) {}
    }
    final String ot = (row['output_text'] as String?)?.trim() ?? '';
    if (ot.isNotEmpty) return _clipText(ot, maxChars);
    final String cat = (row['categories'] as String?)?.trim() ?? '';
    if (cat.isNotEmpty) return _clipText(cat, maxChars);
    return '';
  }

  Map<String, dynamic> _safeJsonObject(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return <String, dynamic>{};
    try {
      final dynamic v = jsonDecode(t);
      if (v is Map) return Map<String, dynamic>.from(v as Map);
    } catch (_) {}
    return <String, dynamic>{};
  }

  Object? _sortJsonForSignature(Object? v) {
    if (v is Map) {
      final Map<dynamic, dynamic> raw = Map<dynamic, dynamic>.from(v as Map);
      final List<String> keys = raw.keys.map((k) => k.toString()).toList()
        ..sort();
      final Map<String, Object?> out = <String, Object?>{};
      for (final String k in keys) {
        out[k] = _sortJsonForSignature(raw[k]);
      }
      return out;
    }
    if (v is List) {
      return v.map((e) => _sortJsonForSignature(e)).toList();
    }
    return v;
  }

  int _normalizeStartMs(Map<String, dynamic> args) {
    final int? ms =
        _parseLocalDateTimeToEpochMs(args['start_local'], isEnd: false) ??
        _toInt(args['start_ms']);
    return ms ?? 0;
  }

  int _normalizeEndMs(Map<String, dynamic> args) {
    final int? ms =
        _parseLocalDateTimeToEpochMs(args['end_local'], isEnd: true) ??
        _toInt(args['end_ms']);
    return ms ?? 0;
  }

  String _toolCallSignature(AIToolCall call) {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final Map<String, dynamic> sig = <String, dynamic>{'tool': call.name};
    int msToMin(int ms) => ms <= 0 ? 0 : (ms ~/ 60000);

    switch (call.name) {
      case 'search_screenshots_ocr':
        sig['query'] = (args['query'] as String?)?.trim() ?? '';
        final String app = (args['app_package_name'] as String?)?.trim() ?? '';
        if (app.isNotEmpty) sig['app_package_name'] = app;
        sig['start_min'] = msToMin(_normalizeStartMs(args));
        sig['end_min'] = msToMin(_normalizeEndMs(args));
        sig['limit'] = (_toInt(args['limit']) ?? 20).clamp(1, 50);
        sig['offset'] = (_toInt(args['offset']) ?? 0).clamp(0, 1 << 30);
        break;
      case 'search_segments':
        sig['query'] = (args['query'] as String?)?.trim() ?? '';
        final String app = (args['app_package_name'] as String?)?.trim() ?? '';
        if (app.isNotEmpty) sig['app_package_name'] = app;
        String mode = (args['mode'] as String?)?.trim().toLowerCase() ?? '';
        if (mode.isEmpty) mode = 'auto';
        if (mode != 'auto' && mode != 'ai' && mode != 'ocr') mode = 'auto';
        sig['mode'] = mode;
        sig['only_no_summary'] = _toBool(args['only_no_summary']);
        sig['start_min'] = msToMin(_normalizeStartMs(args));
        sig['end_min'] = msToMin(_normalizeEndMs(args));
        sig['limit'] = (_toInt(args['limit']) ?? 10).clamp(1, 50);
        sig['offset'] = (_toInt(args['offset']) ?? 0).clamp(0, 1 << 30);
        break;
      case 'search_ai_image_meta':
        sig['query'] = (args['query'] as String?)?.trim() ?? '';
        final String app = (args['app_package_name'] as String?)?.trim() ?? '';
        if (app.isNotEmpty) sig['app_package_name'] = app;
        sig['include_nsfw'] = _toBool(args['include_nsfw']);
        sig['start_min'] = msToMin(_normalizeStartMs(args));
        sig['end_min'] = msToMin(_normalizeEndMs(args));
        sig['limit'] = (_toInt(args['limit']) ?? 20).clamp(1, 50);
        sig['offset'] = (_toInt(args['offset']) ?? 0).clamp(0, 1 << 30);
        break;
      case 'search_memory_graph':
        sig['query'] = (args['query'] as String?)?.trim() ?? '';
        sig['depth'] = (_toInt(args['depth']) ?? 2).clamp(1, 6);
        sig['limit'] = (_toInt(args['limit']) ?? 80).clamp(10, 200);
        final Object? includeRaw = args.containsKey('include_history')
            ? args['include_history']
            : (args.containsKey('includeHistory')
                  ? args['includeHistory']
                  : null);
        sig['include_history'] = includeRaw == null
            ? true
            : _toBool(includeRaw);
        break;
      case 'get_segment_result':
        sig['segment_id'] = _toInt(args['segment_id']) ?? 0;
        break;
      case 'get_segment_samples':
        sig['segment_id'] = _toInt(args['segment_id']) ?? 0;
        sig['limit'] = (_toInt(args['limit']) ?? 10).clamp(1, 50);
        break;
      case 'get_images':
        final dynamic raw = args['filenames'];
        final List<String> names = <String>[];
        if (raw is List) {
          for (final v in raw) {
            final String n = v?.toString().trim() ?? '';
            if (_looksLikeBasename(n)) names.add(n);
          }
        } else if (raw is String) {
          final String n = raw.trim();
          if (_looksLikeBasename(n)) names.add(n);
        }
        final List<String> uniq = <String>{...names}.toList()..sort();
        sig['filenames'] = uniq;
        break;
      default:
        sig['args'] = _sortJsonForSignature(args);
        break;
    }

    return jsonEncode(_sortJsonForSignature(sig));
  }

  Map<String, dynamic> _toolPayloadDigest(Map<String, dynamic> payload) {
    final Map<String, dynamic> out = <String, dynamic>{};
    const List<String> keep = <String>[
      'tool',
      'query',
      'mode',
      'app_package_name',
      'start_local',
      'end_local',
      'limit',
      'offset',
      'count',
      'warnings',
      'paging',
      'segment_id',
      'provided',
      'missing',
      'skipped',
      'stats',
    ];
    for (final String k in keep) {
      if (payload.containsKey(k)) out[k] = payload[k];
    }
    return out;
  }

  Future<List<AIMessage>> _executeGetImagesTool(AIToolCall call) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final dynamic raw = args['filenames'];
    final List<String> names = <String>[];
    if (raw is List) {
      for (final v in raw) {
        final String n = v?.toString().trim() ?? '';
        if (_looksLikeBasename(n)) names.add(n);
      }
    } else if (raw is String) {
      final String n = raw.trim();
      if (_looksLikeBasename(n)) names.add(n);
    }
    final List<String> uniq = <String>{...names}.toList();
    const int maxImages = 15;
    final List<String> limited = uniq.take(maxImages).toList();

    final Map<String, String> nameToPath = limited.isEmpty
        ? const <String, String>{}
        : await ScreenshotDatabase.instance.findPathsByBasenames(
            limited.toSet(),
          );

    final List<Map<String, dynamic>> found = <Map<String, dynamic>>[];
    final List<String> missing = <String>[];
    final List<Map<String, dynamic>> skipped = <Map<String, dynamic>>[];
    final List<Map<String, Object?>> parts = <Map<String, Object?>>[
      <String, Object?>{
        'type': 'text',
        'text':
            'The following images are provided from the user device. Each image is preceded by its filename.',
      },
    ];

    int totalRawBytes = 0;
    int totalPayloadBytes = 0;
    const int maxTotalPayloadBytes = 10 * 1024 * 1024;

    int _estimateDataUrlBytes(int rawBytes, String mime) {
      final int b64Len = ((rawBytes + 2) ~/ 3) * 4;
      final int prefixLen = ('data:$mime;base64,').length;
      return prefixLen + b64Len;
    }

    for (final String name in limited) {
      final String? path = nameToPath[name];
      if (path == null || path.trim().isEmpty) {
        missing.add(name);
        continue;
      }
      try {
        final File f = File(path);
        if (!await f.exists()) {
          missing.add(name);
          continue;
        }
        final String mime = _detectImageMimeByExt(path);
        final int rawLen = await f.length();
        final int estimatedPayloadBytes = _estimateDataUrlBytes(rawLen, mime);
        if (totalPayloadBytes + estimatedPayloadBytes > maxTotalPayloadBytes) {
          skipped.add(<String, dynamic>{
            'filename': name,
            'reason': 'exceeds_total_payload_limit',
            'raw_bytes': rawLen,
            'estimated_payload_bytes': estimatedPayloadBytes,
          });
          continue;
        }

        final List<int> bytes = await f.readAsBytes();
        final String b64 = base64Encode(bytes);
        final String dataUrl = 'data:$mime;base64,$b64';
        final int actualPayloadBytes = dataUrl.length;
        if (totalPayloadBytes + actualPayloadBytes > maxTotalPayloadBytes) {
          skipped.add(<String, dynamic>{
            'filename': name,
            'reason': 'exceeds_total_payload_limit',
            'raw_bytes': bytes.length,
            'payload_bytes': actualPayloadBytes,
          });
          continue;
        }

        totalRawBytes += bytes.length;
        totalPayloadBytes += actualPayloadBytes;
        found.add(<String, dynamic>{
          'filename': name,
          'bytes': bytes.length,
          'mime': mime,
        });
        parts.add(<String, Object?>{'type': 'text', 'text': 'Filename: $name'});
        parts.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{'url': dataUrl},
        });
      } catch (_) {
        missing.add(name);
      }
    }

    final AIMessage toolResult = AIMessage(
      role: 'tool',
      content: jsonEncode(<String, dynamic>{
        'tool': 'get_images',
        'requested': limited,
        'provided': found.map((e) => e['filename']).toList(),
        'missing': missing,
        'skipped': skipped,
        'limits': <String, dynamic>{
          'max_images': maxImages,
          'max_total_payload_bytes': maxTotalPayloadBytes,
        },
        'stats': <String, dynamic>{
          'provided_count': found.length,
          'provided_raw_bytes': totalRawBytes,
          'provided_payload_bytes': totalPayloadBytes,
        },
        'note':
            'Images are attached in the next user message as image_url parts.',
      }),
      toolCallId: call.id,
    );

    final AIMessage userImages = AIMessage(
      role: 'user',
      content: '',
      apiContent: parts,
    );

    return <AIMessage>[toolResult, userImages];
  }

  Future<List<AIMessage>> _executeListSegmentsTool(
    AIToolCall call, {
    int? toolStartMs,
    int? toolEndMs,
  }) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final int now = DateTime.now().millisecondsSinceEpoch;

    final bool onlyNoSummary = _toBool(args['only_no_summary']);
    final String appPackageName =
        (args['app_package_name'] as String?)?.trim() ?? '';
    final int? reqStartMs =
        _parseLocalDateTimeToEpochMs(args['start_local'], isEnd: false) ??
        _toInt(args['start_ms']);
    final int? reqEndMs =
        _parseLocalDateTimeToEpochMs(args['end_local'], isEnd: true) ??
        _toInt(args['end_ms']);
    final bool requestedTooWide =
        (reqStartMs != null &&
        reqEndMs != null &&
        reqStartMs > 0 &&
        reqEndMs > 0 &&
        (reqEndMs - reqStartMs).abs() > AIChatService.maxToolTimeSpanMs);

    int limit = (_toInt(args['limit']) ?? 20).clamp(1, 50);
    int offset = (_toInt(args['offset']) ?? 0);
    if (offset < 0) offset = 0;

    const int defaultSpanMs = 14 * 24 * 60 * 60 * 1000;
    final range = _resolveToolTimeRange(
      defaultStartMs: now - defaultSpanMs,
      defaultEndMs: now,
      startMs: reqStartMs,
      endMs: reqEndMs,
      guardStartMs: toolStartMs,
      guardEndMs: toolEndMs,
    );
    final int s = range.startMs;
    final int e = range.endMs;
    final List<String> warnings = <String>[];
    if (requestedTooWide && range.clampedToMaxSpan) {
      final String servedLocal = _formatLocalRangeForTool(s, e);
      warnings.add(
        _loc(
          '警告：本次工具调用的时间范围超过 7 天，已自动裁剪为 7 天窗口（仅返回 $servedLocal）。如需继续，请使用 paging.prev / paging.next 分页再次调用。',
          'Warning: requested time range exceeds 7 days; clamped to a 7-day window (returned $servedLocal only). Use paging.prev/paging.next to page and call again.',
        ),
      );
    }

    final List<Map<String, dynamic>> rows = await ScreenshotDatabase.instance
        .listSegmentsEx(
          limit: limit,
          offset: offset,
          onlyNoSummary: onlyNoSummary,
          startMillis: s,
          endMillis: e,
          appPackageName: appPackageName,
        );

    final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    for (final r in rows) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(r);
      final int sid = (row['id'] as int?) ?? 0;
      final int st = (row['start_time'] as int?) ?? 0;
      final int et = (row['end_time'] as int?) ?? 0;
      final String disp =
          (row['app_packages_display'] as String?)?.trim() ??
          (row['app_packages'] as String?)?.trim() ??
          '';
      final List<String> apps = disp.isEmpty
          ? <String>[]
          : disp
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList();
      final String? stLocal = st > 0 ? _formatLocalDateTimeForTool(st) : null;
      final String? etLocal = et > 0 ? _formatLocalDateTimeForTool(et) : null;
      results.add(<String, dynamic>{
        'segment_id': sid,
        'start_local': stLocal,
        'end_local': etLocal,
        'apps': apps,
        'has_summary': (row['has_summary'] as int?) ?? 0,
        'sample_count': row['sample_count'],
        'preview': _extractSegmentSummary(row),
      });
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'list_segments',
          if (appPackageName.isNotEmpty) 'app_package_name': appPackageName,
          'start_local': _formatLocalDateTimeForTool(s),
          'end_local': _formatLocalDateTimeForTool(e),
          'time_span_limit': <String, dynamic>{
            'max_span_ms': AIChatService.maxToolTimeSpanMs,
            'max_span_days':
                (AIChatService.maxToolTimeSpanMs /
                        const Duration(days: 1).inMilliseconds)
                    .round(),
            'clamped': range.clampedToMaxSpan,
          },
          if (requestedTooWide)
            'requested_range': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(reqStartMs),
              'end_local': _formatLocalDateTimeForTool(reqEndMs),
            },
          if ((requestedTooWide && range.clampedToMaxSpan) ||
              _shouldOfferWeeklyPagingHint(
                guardStartMs: toolStartMs,
                guardEndMs: toolEndMs,
              ))
            'paging': _buildWeeklyPagingHint(
              servedStartMs: s,
              servedEndMs: e,
              guardStartMs: toolStartMs,
              guardEndMs: toolEndMs,
            ),
          if (warnings.isNotEmpty) 'warnings': warnings,
          if (range.guardApplied)
            'time_guard': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(toolStartMs!),
              'end_local': _formatLocalDateTimeForTool(toolEndMs!),
              'clamped': range.clampedToGuard,
            },
          'only_no_summary': onlyNoSummary,
          'limit': limit,
          'offset': offset,
          'count': results.length,
          'results': results,
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeSearchSegmentsTool(
    AIToolCall call, {
    int? toolStartMs,
    int? toolEndMs,
  }) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final String query = (args['query'] as String?)?.trim() ?? '';
    final String appPackageName =
        (args['app_package_name'] as String?)?.trim() ?? '';
    final bool onlyNoSummary = _toBool(args['only_no_summary']);
    final int? reqStartMs =
        _parseLocalDateTimeToEpochMs(args['start_local'], isEnd: false) ??
        _toInt(args['start_ms']);
    final int? reqEndMs =
        _parseLocalDateTimeToEpochMs(args['end_local'], isEnd: true) ??
        _toInt(args['end_ms']);

    String mode = (args['mode'] as String?)?.trim().toLowerCase() ?? '';
    if (mode.isEmpty) mode = 'auto';
    if (mode != 'auto' && mode != 'ai' && mode != 'ocr') mode = 'auto';

    final int maxSpanMs = query.isEmpty
        ? AIChatService.maxToolTimeSpanMs
        : (mode == 'ocr'
              ? AIChatService.maxOcrToolTimeSpanMs
              : AIChatService.maxSemanticToolTimeSpanMs);
    final bool requestedTooWide =
        maxSpanMs > 0 &&
        (reqStartMs != null &&
            reqEndMs != null &&
            reqStartMs > 0 &&
            reqEndMs > 0 &&
            (reqEndMs - reqStartMs).abs() > maxSpanMs);

    // If query is omitted, behave like "list segments in time range".
    if (query.isEmpty) {
      final List<AIMessage> msgs = await _executeListSegmentsTool(
        call,
        toolStartMs: toolStartMs,
        toolEndMs: toolEndMs,
      );
      if (msgs.isEmpty) return msgs;
      final Map<String, dynamic> payload = _safeJsonObject(msgs.first.content);
      payload['tool'] = 'search_segments';
      payload['mode'] = 'list';
      payload['query'] = '';
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(payload),
          toolCallId: call.id,
        ),
      ];
    }

    // If the caller explicitly wants "only no summary", OCR is the only meaningful mode.
    if (onlyNoSummary && mode != 'ocr') mode = 'ocr';

    if (mode == 'ocr') {
      final List<AIMessage> msgs = await _executeSearchSegmentsOcrTool(
        call,
        toolStartMs: toolStartMs,
        toolEndMs: toolEndMs,
      );
      if (msgs.isEmpty) return msgs;
      final Map<String, dynamic> payload = _safeJsonObject(msgs.first.content);
      payload['tool'] = 'search_segments';
      payload['mode'] = 'ocr';
      payload['query'] = query;
      payload['only_no_summary'] = onlyNoSummary;
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(payload),
          toolCallId: call.id,
        ),
      ];
    }

    int limit = (_toInt(args['limit']) ?? 10).clamp(1, 50);
    int offset = (_toInt(args['offset']) ?? 0);
    if (offset < 0) offset = 0;

    // For semantic segment search, default to a much wider window.
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int defaultStart = now - const Duration(days: 365).inMilliseconds;
    final range = _resolveToolTimeRange(
      defaultStartMs: defaultStart,
      defaultEndMs: now,
      startMs: reqStartMs,
      endMs: reqEndMs,
      guardStartMs: toolStartMs,
      guardEndMs: toolEndMs,
      maxSpanMs: maxSpanMs,
    );
    final int s = range.startMs;
    final int e = range.endMs;
    final List<String> warnings = <String>[];
    if (requestedTooWide && range.clampedToMaxSpan) {
      final int maxSpanDays =
          (maxSpanMs / const Duration(days: 1).inMilliseconds).round();
      final String servedLocal = _formatLocalRangeForTool(s, e);
      warnings.add(
        _loc(
          '警告：本次工具调用的时间范围超过 $maxSpanDays 天，已自动裁剪为 $maxSpanDays 天窗口（仅返回 $servedLocal）。如需继续，请使用 paging.prev / paging.next 分页再次调用。',
          'Warning: requested time range exceeds $maxSpanDays days; clamped to a $maxSpanDays-day window (returned $servedLocal only). Use paging.prev/paging.next to page and call again.',
        ),
      );
    }

    final String requestedAppPackageName = appPackageName;
    String effectiveAppPackageName = appPackageName;
    bool appFilterRelaxed = false;
    List<Map<String, dynamic>> rows = await ScreenshotDatabase.instance
        .searchSegmentsByText(
          query,
          limit: limit,
          offset: offset,
          startMillis: s,
          endMillis: e,
          appPackageName: effectiveAppPackageName.isEmpty
              ? null
              : effectiveAppPackageName,
        );
    if (rows.isEmpty && requestedAppPackageName.isNotEmpty) {
      rows = await ScreenshotDatabase.instance.searchSegmentsByText(
        query,
        limit: limit,
        offset: offset,
        startMillis: s,
        endMillis: e,
        appPackageName: null,
      );
      if (rows.isNotEmpty) {
        appFilterRelaxed = true;
        effectiveAppPackageName = '';
      }
    }

    final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    for (final r in rows) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(r);
      final int sid = (row['id'] as int?) ?? (row['segment_id'] as int?) ?? 0;
      final int st = (row['start_time'] as int?) ?? 0;
      final int et = (row['end_time'] as int?) ?? 0;
      final String disp =
          (row['app_packages_display'] as String?)?.trim() ??
          (row['app_packages'] as String?)?.trim() ??
          '';
      final List<String> apps = disp.isEmpty
          ? <String>[]
          : disp
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList();

      final String ot = (row['output_text'] as String?)?.trim() ?? '';
      final String sj = (row['structured_json'] as String?)?.trim() ?? '';
      final bool otEmpty = ot.isEmpty || ot.toLowerCase() == 'null';
      final bool sjEmpty = sj.isEmpty || sj.toLowerCase() == 'null';
      final int hasSummary = (otEmpty && sjEmpty) ? 0 : 1;
      final String? stLocal = st > 0 ? _formatLocalDateTimeForTool(st) : null;
      final String? etLocal = et > 0 ? _formatLocalDateTimeForTool(et) : null;

      results.add(<String, dynamic>{
        'segment_id': sid,
        'start_local': stLocal,
        'end_local': etLocal,
        'apps': apps,
        'has_summary': hasSummary,
        'sample_count': row['sample_count'],
        'preview': _extractSegmentSummary(row),
        'match_sources': <String>['ai'],
      });
    }

    // auto: fallback to OCR when AI-result search yields nothing.
    final bool canOcrFallback =
        (AIChatService.maxOcrToolTimeSpanMs <= 0) ||
        (e - s).abs() <= AIChatService.maxOcrToolTimeSpanMs;
    if (mode == 'auto' && results.isEmpty && canOcrFallback) {
      final List<AIMessage> msgs = await _executeSearchSegmentsOcrTool(
        call,
        toolStartMs: toolStartMs,
        toolEndMs: toolEndMs,
      );
      if (msgs.isEmpty) return msgs;
      final Map<String, dynamic> payload = _safeJsonObject(msgs.first.content);
      payload['tool'] = 'search_segments';
      payload['mode'] = 'ocr_fallback';
      payload['query'] = query;
      payload['only_no_summary'] = onlyNoSummary;
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(payload),
          toolCallId: call.id,
        ),
      ];
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'search_segments',
          'mode': mode == 'ai' ? 'ai' : 'auto_ai',
          'query': query,
          if (effectiveAppPackageName.isNotEmpty)
            'app_package_name': effectiveAppPackageName,
          if (appFilterRelaxed)
            'requested_app_package_name': requestedAppPackageName,
          if (appFilterRelaxed) 'app_filter_relaxed': true,
          'start_local': _formatLocalDateTimeForTool(s),
          'end_local': _formatLocalDateTimeForTool(e),
          'time_span_limit': <String, dynamic>{
            'max_span_ms': maxSpanMs,
            'max_span_days':
                (maxSpanMs / const Duration(days: 1).inMilliseconds).round(),
            'clamped': range.clampedToMaxSpan,
          },
          if (requestedTooWide)
            'requested_range': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(reqStartMs),
              'end_local': _formatLocalDateTimeForTool(reqEndMs),
            },
          if ((requestedTooWide && range.clampedToMaxSpan) ||
              _shouldOfferWeeklyPagingHint(
                guardStartMs: toolStartMs,
                guardEndMs: toolEndMs,
                maxSpanMs: maxSpanMs,
              ))
            'paging': _buildWeeklyPagingHint(
              servedStartMs: s,
              servedEndMs: e,
              maxSpanMs: maxSpanMs,
              guardStartMs: toolStartMs,
              guardEndMs: toolEndMs,
            ),
          if (warnings.isNotEmpty) 'warnings': warnings,
          if (range.guardApplied)
            'time_guard': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(toolStartMs!),
              'end_local': _formatLocalDateTimeForTool(toolEndMs!),
              'clamped': range.clampedToGuard,
            },
          'only_no_summary': onlyNoSummary,
          'limit': limit,
          'offset': offset,
          'count': results.length,
          'results': results,
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeSearchSegmentsOcrTool(
    AIToolCall call, {
    int? toolStartMs,
    int? toolEndMs,
  }) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final String query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'search_segments_ocr',
            'error': 'missing_query',
          }),
          toolCallId: call.id,
        ),
      ];
    }
    final String appPackageName =
        (args['app_package_name'] as String?)?.trim() ?? '';
    final String requestedAppPackageName = appPackageName;
    String effectiveAppPackageName = appPackageName;
    bool appFilterRelaxed = false;
    final bool onlyNoSummary = _toBool(args['only_no_summary']);
    final int? reqStartMs =
        _parseLocalDateTimeToEpochMs(args['start_local'], isEnd: false) ??
        _toInt(args['start_ms']);
    final int? reqEndMs =
        _parseLocalDateTimeToEpochMs(args['end_local'], isEnd: true) ??
        _toInt(args['end_ms']);

    final int now = DateTime.now().millisecondsSinceEpoch;
    final int defaultStart = now - const Duration(days: 30).inMilliseconds;
    final range0 = _resolveToolTimeRange(
      defaultStartMs: defaultStart,
      defaultEndMs: now,
      startMs: reqStartMs,
      endMs: reqEndMs,
      guardStartMs: toolStartMs,
      guardEndMs: toolEndMs,
      maxSpanMs: AIChatService.maxOcrToolTimeSpanMs,
    );
    int s = range0.startMs;
    int e = range0.endMs;
    int limit = (_toInt(args['limit']) ?? 10).clamp(1, 20);
    int offset = (_toInt(args['offset']) ?? 0);
    if (offset < 0) offset = 0;
    int perSeg = (_toInt(args['per_segment_samples']) ?? 6).clamp(1, 15);

    // Fetch more screenshots than segments to improve segment coverage.
    final int desiredSegs = offset + limit;
    final int shotFetch = (desiredSegs * 30).clamp(120, 600);

    List<ScreenshotRecord> shots;
    try {
      shots = effectiveAppPackageName.isNotEmpty
          ? await ScreenshotDatabase.instance.searchScreenshotsByOcrForApp(
              effectiveAppPackageName,
              query,
              limit: shotFetch,
              offset: 0,
              startMillis: s,
              endMillis: e,
            )
          : await ScreenshotDatabase.instance.searchScreenshotsByOcr(
              query,
              limit: shotFetch,
              offset: 0,
              startMillis: s,
              endMillis: e,
            );
      if (shots.isEmpty && requestedAppPackageName.isNotEmpty) {
        final List<ScreenshotRecord> fallbackShots = await ScreenshotDatabase
            .instance
            .searchScreenshotsByOcr(
              query,
              limit: shotFetch,
              offset: 0,
              startMillis: s,
              endMillis: e,
            );
        if (fallbackShots.isNotEmpty) {
          shots = fallbackShots;
          appFilterRelaxed = true;
          effectiveAppPackageName = '';
        }
      }
    } catch (err) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'search_segments_ocr',
            'query': query,
            if (requestedAppPackageName.isNotEmpty)
              'app_package_name': requestedAppPackageName,
            'start_local': _formatLocalDateTimeForTool(s),
            'end_local': _formatLocalDateTimeForTool(e),
            if (range0.guardApplied)
              'time_guard': <String, dynamic>{
                'start_local': _formatLocalDateTimeForTool(toolStartMs!),
                'end_local': _formatLocalDateTimeForTool(toolEndMs!),
                'clamped': range0.clampedToGuard,
              },
            'error': 'ocr_search_failed',
            'details': err.toString(),
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final List<ScreenshotRecord> normalizedShots = shots
        .where((r) => r.filePath.trim().isNotEmpty)
        .toList(growable: false);

    // Map screenshot file_path -> segment_id via segment_samples in main DB.
    final db = await ScreenshotDatabase.instance.database;
    final List<String> paths = normalizedShots
        .map((r) => r.filePath.trim())
        .toSet()
        .toList(growable: false);
    final Map<String, Map<String, dynamic>> pathToSample =
        <String, Map<String, dynamic>>{};
    const int chunkSize = 400;
    for (int i = 0; i < paths.length; i += chunkSize) {
      final int end = (i + chunkSize) > paths.length
          ? paths.length
          : (i + chunkSize);
      final List<String> chunk = paths.sublist(i, end);
      if (chunk.isEmpty) continue;
      final String placeholders = List.filled(chunk.length, '?').join(',');
      final List<Map<String, Object?>> rows = await db.query(
        'segment_samples',
        columns: <String>[
          'segment_id',
          'file_path',
          'capture_time',
          'app_package_name',
          'app_name',
        ],
        where: 'file_path IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final r in rows) {
        final String fp = (r['file_path'] as String?)?.trim() ?? '';
        if (fp.isEmpty) continue;
        pathToSample[fp] = Map<String, dynamic>.from(r);
      }
    }

    final Map<int, List<Map<String, dynamic>>> segToMatches =
        <int, List<Map<String, dynamic>>>{};
    final List<Map<String, dynamic>> unmapped = <Map<String, dynamic>>[];
    Map<String, dynamic> sanitizeOcrMatch(Map<String, dynamic> m) {
      final Map<String, dynamic> out = <String, dynamic>{...m};
      out.remove('capture_ms');
      return out;
    }

    for (final ScreenshotRecord r in normalizedShots) {
      final String fp = r.filePath.trim();
      final Map<String, dynamic>? sample = pathToSample[fp];
      final int sid = (sample?['segment_id'] as int?) ?? 0;
      final int captureMs = r.captureTime.millisecondsSinceEpoch;
      final Map<String, dynamic> match = <String, dynamic>{
        'filename': _basename(fp),
        'capture_ms': captureMs,
        'capture_local': _formatLocalDateTimeForTool(captureMs),
        'app_package_name': r.appPackageName,
        'app_name': r.appName,
        'segment_id': sid > 0 ? sid : null,
      };
      if (sid <= 0) {
        unmapped.add(match);
        continue;
      }
      final List<Map<String, dynamic>> list = segToMatches.putIfAbsent(
        sid,
        () => <Map<String, dynamic>>[],
      );
      list.add(match);
    }

    final List<int> segIds = segToMatches.keys.toList()..sort();
    final Map<int, Map<String, dynamic>> segMeta =
        <int, Map<String, dynamic>>{};
    const String noSummaryCond =
        "r.segment_id IS NULL OR ((r.output_text IS NULL OR LOWER(TRIM(r.output_text)) IN ('','null')) AND (r.structured_json IS NULL OR LOWER(TRIM(r.structured_json)) IN ('','null')))";
    const int segChunkSize = 300;
    for (int i = 0; i < segIds.length; i += segChunkSize) {
      final int end = (i + segChunkSize) > segIds.length
          ? segIds.length
          : (i + segChunkSize);
      final List<int> chunk = segIds.sublist(i, end);
      if (chunk.isEmpty) continue;
      final String placeholders = List.filled(chunk.length, '?').join(',');
      final String sql =
          '''
        SELECT
          s.id,
          s.start_time,
          s.end_time,
          s.status,
          s.app_packages,
          COALESCE(
            NULLIF(TRIM(s.app_packages), ''),
            (SELECT GROUP_CONCAT(DISTINCT ss.app_package_name) FROM segment_samples ss WHERE ss.segment_id = s.id)
          ) AS app_packages_display,
          (SELECT COUNT(*) FROM segment_samples ss WHERE ss.segment_id = s.id) AS sample_count,
          r.output_text,
          r.structured_json,
          r.categories,
          CASE WHEN $noSummaryCond THEN 0 ELSE 1 END AS has_summary
        FROM segments s
        LEFT JOIN segment_results r ON r.segment_id = s.id
        WHERE s.id IN ($placeholders)
          AND s.merged_into_id IS NULL
      ''';
      final List<Map<String, Object?>> rows = await db.rawQuery(sql, chunk);
      for (final r in rows) {
        final int sid = (r['id'] as int?) ?? 0;
        if (sid <= 0) continue;
        segMeta[sid] = Map<String, dynamic>.from(r);
      }
    }

    final List<Map<String, dynamic>> ranked = <Map<String, dynamic>>[];
    for (final MapEntry<int, List<Map<String, dynamic>>> entry
        in segToMatches.entries) {
      final int sid = entry.key;
      final List<Map<String, dynamic>> matches = entry.value;
      int last = 0;
      for (final m in matches) {
        final int t = (m['capture_ms'] as int?) ?? 0;
        if (t > last) last = t;
      }
      ranked.add(<String, dynamic>{
        'segment_id': sid,
        'last_match_time': last,
        'match_count': matches.length,
      });
    }
    ranked.sort((a, b) {
      final int ta = (a['last_match_time'] as int?) ?? 0;
      final int tb = (b['last_match_time'] as int?) ?? 0;
      if (tb != ta) return tb.compareTo(ta);
      final int ca = (a['match_count'] as int?) ?? 0;
      final int cb = (b['match_count'] as int?) ?? 0;
      if (cb != ca) return cb.compareTo(ca);
      final int ida = (a['segment_id'] as int?) ?? 0;
      final int idb = (b['segment_id'] as int?) ?? 0;
      return idb.compareTo(ida);
    });

    final List<int> orderedSegIds = ranked
        .map((e) => (e['segment_id'] as int?) ?? 0)
        .where((e) => e > 0)
        .toList(growable: false);
    final List<int> filteredSegIds = onlyNoSummary
        ? orderedSegIds
              .where((sid) => (segMeta[sid]?['has_summary'] as int?) == 0)
              .toList(growable: false)
        : orderedSegIds;
    final List<int> pageSegIds = filteredSegIds
        .skip(offset)
        .take(limit)
        .toList(growable: false);

    final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    for (final int sid in pageSegIds) {
      final Map<String, dynamic>? meta = segMeta[sid];
      final int st = (meta?['start_time'] as int?) ?? 0;
      final int et = (meta?['end_time'] as int?) ?? 0;
      final String disp =
          (meta?['app_packages_display'] as String?)?.trim() ??
          (meta?['app_packages'] as String?)?.trim() ??
          '';
      final List<String> apps = disp.isEmpty
          ? <String>[]
          : disp
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList();

      final List<Map<String, dynamic>> matches =
          List<Map<String, dynamic>>.from(segToMatches[sid] ?? const []);
      matches.sort((a, b) {
        final int ta = (a['capture_ms'] as int?) ?? 0;
        final int tb = (b['capture_ms'] as int?) ?? 0;
        return tb.compareTo(ta);
      });
      final String? stLocal = st > 0 ? _formatLocalDateTimeForTool(st) : null;
      final String? etLocal = et > 0 ? _formatLocalDateTimeForTool(et) : null;

      results.add(<String, dynamic>{
        'segment_id': sid,
        'start_local': stLocal,
        'end_local': etLocal,
        'apps': apps,
        'has_summary': (meta?['has_summary'] as int?) ?? 0,
        'sample_count': meta?['sample_count'],
        'preview': meta == null ? '' : _extractSegmentSummary(meta),
        'match_count': matches.length,
        'matched_samples': matches.take(perSeg).map(sanitizeOcrMatch).toList(),
        'match_sources': <String>['ocr'],
      });
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'search_segments_ocr',
          'query': query,
          if (effectiveAppPackageName.isNotEmpty)
            'app_package_name': effectiveAppPackageName,
          if (appFilterRelaxed)
            'requested_app_package_name': requestedAppPackageName,
          if (appFilterRelaxed) 'app_filter_relaxed': true,
          'start_local': _formatLocalDateTimeForTool(s),
          'end_local': _formatLocalDateTimeForTool(e),
          if (range0.guardApplied)
            'time_guard': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(toolStartMs!),
              'end_local': _formatLocalDateTimeForTool(toolEndMs!),
              'clamped': range0.clampedToGuard,
            },
          'limit': limit,
          'offset': offset,
          'only_no_summary': onlyNoSummary,
          'per_segment_samples': perSeg,
          'fetched_screenshots': normalizedShots.length,
          'segments_total': ranked.length,
          'segments_total_filtered': filteredSegIds.length,
          'count': results.length,
          'results': results,
          // Keep a small list for the model to request images if needed.
          'unmapped_samples_preview': unmapped
              .take(20)
              .map(sanitizeOcrMatch)
              .toList(growable: false),
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeGetSegmentResultTool(AIToolCall call) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final int sid = _toInt(args['segment_id']) ?? 0;
    final int maxChars = (_toInt(args['max_chars']) ?? 12000).clamp(800, 40000);
    if (sid <= 0) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'get_segment_result',
            'error': 'invalid_segment_id',
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final Map<String, dynamic>? segRow = await (() async {
      try {
        final db = await ScreenshotDatabase.instance.database;
        final rows = await db.query(
          'segments',
          where: 'id = ?',
          whereArgs: <Object?>[sid],
          limit: 1,
        );
        if (rows.isEmpty) return null;
        return Map<String, dynamic>.from(rows.first);
      } catch (_) {
        return null;
      }
    })();

    final Map<String, dynamic>? seg = segRow == null
        ? null
        : <String, dynamic>{...segRow};
    if (seg != null) {
      final int st = (seg['start_time'] as int?) ?? 0;
      final int et = (seg['end_time'] as int?) ?? 0;
      seg.remove('start_time');
      seg.remove('end_time');
      seg['start_local'] = st > 0 ? _formatLocalDateTimeForTool(st) : null;
      seg['end_local'] = et > 0 ? _formatLocalDateTimeForTool(et) : null;
    }

    final Map<String, dynamic>? res = await ScreenshotDatabase.instance
        .getSegmentResult(sid);
    final Map<String, dynamic> out = <String, dynamic>{
      'tool': 'get_segment_result',
      'segment_id': sid,
      'segment': seg,
      'result': res == null
          ? null
          : <String, dynamic>{
              'ai_provider': res['ai_provider'],
              'ai_model': res['ai_model'],
              'categories': res['categories'],
              'created_at': res['created_at'],
              'output_text': _clipText(
                (res['output_text'] as String?) ?? '',
                maxChars,
              ),
              'structured_json': _clipText(
                (res['structured_json'] as String?) ?? '',
                maxChars,
              ),
            },
    };

    return <AIMessage>[
      AIMessage(role: 'tool', content: jsonEncode(out), toolCallId: call.id),
    ];
  }

  Future<List<AIMessage>> _executeGetSegmentSamplesTool(AIToolCall call) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final int sid = _toInt(args['segment_id']) ?? 0;
    int limit = (_toInt(args['limit']) ?? 24).clamp(1, 60);
    if (sid <= 0) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'get_segment_samples',
            'error': 'invalid_segment_id',
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final List<Map<String, dynamic>> rows = await ScreenshotDatabase.instance
        .listSegmentSamples(sid);
    final List<Map<String, dynamic>> samples = <Map<String, dynamic>>[];
    for (final r in rows.take(limit)) {
      final Map<String, dynamic> m = Map<String, dynamic>.from(r);
      final String fp = (m['file_path'] as String?) ?? '';
      final int captureMs = (m['capture_time'] as int?) ?? 0;
      samples.add(<String, dynamic>{
        'sample_id': m['id'],
        'capture_local': captureMs > 0
            ? _formatLocalDateTimeForTool(captureMs)
            : null,
        'app_package_name': m['app_package_name'],
        'app_name': m['app_name'],
        'position_index': m['position_index'],
        'filename': fp.isEmpty ? '' : _basename(fp),
      });
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'get_segment_samples',
          'segment_id': sid,
          'limit': limit,
          'count': samples.length,
          'samples': samples,
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeSearchScreenshotsOcrTool(
    AIToolCall call, {
    int? toolStartMs,
    int? toolEndMs,
  }) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final String query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'search_screenshots_ocr',
            'error': 'missing_query',
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final String appPackageName =
        (args['app_package_name'] as String?)?.trim() ?? '';
    final int? reqStartMs =
        _parseLocalDateTimeToEpochMs(args['start_local'], isEnd: false) ??
        _toInt(args['start_ms']);
    final int? reqEndMs =
        _parseLocalDateTimeToEpochMs(args['end_local'], isEnd: true) ??
        _toInt(args['end_ms']);

    final int now = DateTime.now().millisecondsSinceEpoch;
    final int defaultStart = now - const Duration(days: 30).inMilliseconds;
    final range0 = _resolveToolTimeRange(
      defaultStartMs: defaultStart,
      defaultEndMs: now,
      startMs: reqStartMs,
      endMs: reqEndMs,
      guardStartMs: toolStartMs,
      guardEndMs: toolEndMs,
      maxSpanMs: AIChatService.maxOcrToolTimeSpanMs,
    );
    int s = range0.startMs;
    int e = range0.endMs;
    int limit = (_toInt(args['limit']) ?? 20).clamp(1, 50);
    int offset = (_toInt(args['offset']) ?? 0);
    if (offset < 0) offset = 0;

    final String requestedAppPackageName = appPackageName;
    String effectiveAppPackageName = appPackageName;
    bool appFilterRelaxed = false;
    List<ScreenshotRecord> rows = effectiveAppPackageName.isNotEmpty
        ? await ScreenshotDatabase.instance.searchScreenshotsByOcrForApp(
            effectiveAppPackageName,
            query,
            limit: limit,
            offset: offset,
            startMillis: s,
            endMillis: e,
          )
        : await ScreenshotDatabase.instance.searchScreenshotsByOcr(
            query,
            limit: limit,
            offset: offset,
            startMillis: s,
            endMillis: e,
          );
    if (rows.isEmpty && requestedAppPackageName.isNotEmpty) {
      rows = await ScreenshotDatabase.instance.searchScreenshotsByOcr(
        query,
        limit: limit,
        offset: offset,
        startMillis: s,
        endMillis: e,
      );
      if (rows.isNotEmpty) {
        appFilterRelaxed = true;
        effectiveAppPackageName = '';
      }
    }

    final List<Map<String, dynamic>> results = rows.map((r) {
      final String fp = r.filePath;
      final int captureMs = r.captureTime.millisecondsSinceEpoch;
      return <String, dynamic>{
        'id': r.id,
        'app_package_name': r.appPackageName,
        'app_name': r.appName,
        'capture_local': _formatLocalDateTimeForTool(captureMs),
        'filename': fp.isEmpty ? '' : _basename(fp),
        'file_size': r.fileSize,
      };
    }).toList();

    int? totalCount;
    bool hasMore = false;
    try {
      // Fast path: if we didn't fill the page, treat returned results as the full set.
      // Otherwise compute the true total to support “how many …” questions without
      // forcing the model to split time windows.
      if (offset <= 0 && results.length < limit) {
        totalCount = results.length;
      } else {
        totalCount = effectiveAppPackageName.isNotEmpty
            ? await ScreenshotDatabase.instance.countScreenshotsByOcrForApp(
                effectiveAppPackageName,
                query,
                startMillis: s,
                endMillis: e,
              )
            : await ScreenshotDatabase.instance.countScreenshotsByOcr(
                query,
                startMillis: s,
                endMillis: e,
              );
      }
      if (totalCount != null) {
        hasMore = (offset + results.length) < totalCount;
      }
    } catch (_) {
      // Best-effort: total_count is optional; do not fail the tool if counting fails.
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'search_screenshots_ocr',
          'query': query,
          if (effectiveAppPackageName.isNotEmpty)
            'app_package_name': effectiveAppPackageName,
          if (appFilterRelaxed)
            'requested_app_package_name': requestedAppPackageName,
          if (appFilterRelaxed) 'app_filter_relaxed': true,
          'start_local': _formatLocalDateTimeForTool(s),
          'end_local': _formatLocalDateTimeForTool(e),
          if (range0.guardApplied)
            'time_guard': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(toolStartMs!),
              'end_local': _formatLocalDateTimeForTool(toolEndMs!),
              'clamped': range0.clampedToGuard,
            },
          'limit': limit,
          'offset': offset,
          'count': results.length,
          if (totalCount != null) 'total_count': totalCount,
          if (totalCount != null) 'has_more': hasMore,
          'results': results,
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeSearchAiImageMetaTool(
    AIToolCall call, {
    int? toolStartMs,
    int? toolEndMs,
  }) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final String query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'search_ai_image_meta',
            'error': 'missing_query',
          }),
          toolCallId: call.id,
        ),
      ];
    }

    final String appPackageName =
        (args['app_package_name'] as String?)?.trim() ?? '';
    final bool includeNsfw = _toBool(args['include_nsfw']);

    final int? reqStartMs =
        _parseLocalDateTimeToEpochMs(args['start_local'], isEnd: false) ??
        _toInt(args['start_ms']);
    final int? reqEndMs =
        _parseLocalDateTimeToEpochMs(args['end_local'], isEnd: true) ??
        _toInt(args['end_ms']);
    final int maxSpanMs = AIChatService.maxSemanticToolTimeSpanMs;
    final bool requestedTooWide =
        (reqStartMs != null &&
        reqEndMs != null &&
        reqStartMs > 0 &&
        reqEndMs > 0 &&
        (reqEndMs - reqStartMs).abs() > maxSpanMs);

    final int now = DateTime.now().millisecondsSinceEpoch;
    final int defaultStart = now - const Duration(days: 365).inMilliseconds;
    final range0 = _resolveToolTimeRange(
      defaultStartMs: defaultStart,
      defaultEndMs: now,
      startMs: reqStartMs,
      endMs: reqEndMs,
      guardStartMs: toolStartMs,
      guardEndMs: toolEndMs,
      maxSpanMs: maxSpanMs,
    );
    final int s = range0.startMs;
    final int e = range0.endMs;
    final List<String> warnings = <String>[];
    if (requestedTooWide && range0.clampedToMaxSpan) {
      final int maxSpanDays =
          (maxSpanMs / const Duration(days: 1).inMilliseconds).round();
      final String servedLocal = _formatLocalRangeForTool(s, e);
      warnings.add(
        _loc(
          '警告：本次工具调用的时间范围超过 $maxSpanDays 天，已自动裁剪为 $maxSpanDays 天窗口（仅返回 $servedLocal）。如需继续，请使用 paging.prev / paging.next 分页再次调用。',
          'Warning: requested time range exceeds $maxSpanDays days; clamped to a $maxSpanDays-day window (returned $servedLocal only). Use paging.prev/paging.next to page and call again.',
        ),
      );
    }

    int limit = (_toInt(args['limit']) ?? 20).clamp(1, 50);
    int offset = (_toInt(args['offset']) ?? 0);
    if (offset < 0) offset = 0;

    final String requestedAppPackageName = appPackageName;
    String effectiveAppPackageName = appPackageName;
    bool appFilterRelaxed = false;
    List<Map<String, dynamic>> rows = await ScreenshotDatabase.instance
        .searchAiImageMetaByText(
          query,
          limit: limit,
          offset: offset,
          startMillis: s,
          endMillis: e,
          includeNsfw: includeNsfw,
          appPackageName: effectiveAppPackageName.isEmpty
              ? null
              : effectiveAppPackageName,
        );
    if (rows.isEmpty && requestedAppPackageName.isNotEmpty) {
      rows = await ScreenshotDatabase.instance.searchAiImageMetaByText(
        query,
        limit: limit,
        offset: offset,
        startMillis: s,
        endMillis: e,
        includeNsfw: includeNsfw,
        appPackageName: null,
      );
      if (rows.isNotEmpty) {
        appFilterRelaxed = true;
        effectiveAppPackageName = '';
      }
    }

    List<String> parseTags(Object? raw) {
      if (raw == null) return <String>[];
      final String t = raw.toString().trim();
      if (t.isEmpty) return <String>[];
      try {
        final dynamic v = jsonDecode(t);
        if (v is List) {
          return v
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList();
        }
      } catch (_) {}
      return t
          .split(RegExp(r'[，,;；\s]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    }

    final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    for (final r in rows) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(r);
      final String fp = (row['file_path'] as String?)?.trim() ?? '';
      final String filename = fp.isEmpty ? '' : _basename(fp);
      final int captureMs = (row['capture_time'] as int?) ?? 0;
      results.add(<String, dynamic>{
        'filename': filename,
        'capture_local': captureMs > 0
            ? _formatLocalDateTimeForTool(captureMs)
            : null,
        'segment_id': row['segment_id'],
        'app_package_name': row['app_package_name'],
        'app_name': row['app_name'],
        'tags': parseTags(row['tags_json']),
        'description': _clipText((row['description'] as String?) ?? '', 1200),
        'description_range': row['description_range'],
        'nsfw': row['nsfw'],
        'lang': row['lang'],
      });
    }

    return <AIMessage>[
      AIMessage(
        role: 'tool',
        content: jsonEncode(<String, dynamic>{
          'tool': 'search_ai_image_meta',
          'query': query,
          if (effectiveAppPackageName.isNotEmpty)
            'app_package_name': effectiveAppPackageName,
          if (appFilterRelaxed)
            'requested_app_package_name': requestedAppPackageName,
          if (appFilterRelaxed) 'app_filter_relaxed': true,
          'include_nsfw': includeNsfw,
          'start_local': _formatLocalDateTimeForTool(s),
          'end_local': _formatLocalDateTimeForTool(e),
          'time_span_limit': <String, dynamic>{
            'max_span_ms': maxSpanMs,
            'max_span_days':
                (maxSpanMs / const Duration(days: 1).inMilliseconds).round(),
            'clamped': range0.clampedToMaxSpan,
          },
          if (requestedTooWide)
            'requested_range': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(reqStartMs),
              'end_local': _formatLocalDateTimeForTool(reqEndMs),
            },
          if ((requestedTooWide && range0.clampedToMaxSpan) ||
              _shouldOfferWeeklyPagingHint(
                guardStartMs: toolStartMs,
                guardEndMs: toolEndMs,
                maxSpanMs: maxSpanMs,
              ))
            'paging': _buildWeeklyPagingHint(
              servedStartMs: s,
              servedEndMs: e,
              maxSpanMs: maxSpanMs,
              guardStartMs: toolStartMs,
              guardEndMs: toolEndMs,
            ),
          if (warnings.isNotEmpty) 'warnings': warnings,
          if (range0.guardApplied)
            'time_guard': <String, dynamic>{
              'start_local': _formatLocalDateTimeForTool(toolStartMs!),
              'end_local': _formatLocalDateTimeForTool(toolEndMs!),
              'clamped': range0.clampedToGuard,
            },
          'limit': limit,
          'offset': offset,
          'count': results.length,
          'results': results,
        }),
        toolCallId: call.id,
      ),
    ];
  }

  Future<List<AIMessage>> _executeSearchMemoryGraphTool(AIToolCall call) async {
    final Map<String, dynamic> args = _safeJsonObject(call.argumentsJson);
    final String query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'search_memory_graph',
            'error': 'missing_query',
          }),
          toolCallId: call.id,
        ),
      ];
    }

    int depth = _toInt(args['depth']) ?? 2;
    if (depth < 1) depth = 1;
    if (depth > 4) depth = 4;
    int limit = _toInt(args['limit']) ?? 80;
    if (limit < 10) limit = 10;
    if (limit > 200) limit = 200;
    final Object? includeRaw = args.containsKey('include_history')
        ? args['include_history']
        : (args.containsKey('includeHistory') ? args['includeHistory'] : null);
    final bool includeHistory = includeRaw == null ? true : _toBool(includeRaw);

    try {
      final Map<String, dynamic> rawPayload = await MemoryBridgeService.instance
          .searchMemoryGraph(
            query: query,
            depth: depth,
            limit: limit,
            includeHistory: includeHistory,
          );
      final Map<String, dynamic> payload = <String, dynamic>{...rawPayload};
      payload['tool'] = 'search_memory_graph';
      payload.putIfAbsent('query', () => query);
      payload.putIfAbsent('depth', () => depth);
      payload.putIfAbsent('limit', () => limit);
      payload.putIfAbsent('include_history', () => includeHistory);
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(payload),
          toolCallId: call.id,
        ),
      ];
    } catch (err) {
      return <AIMessage>[
        AIMessage(
          role: 'tool',
          content: jsonEncode(<String, dynamic>{
            'tool': 'search_memory_graph',
            'error': 'graph_search_failed',
            'message': err.toString(),
          }),
          toolCallId: call.id,
        ),
      ];
    }
  }

  Future<List<AIMessage>> _executeToolCall(
    AIToolCall call, {
    int? toolStartMs,
    int? toolEndMs,
  }) async {
    switch (call.name) {
      case 'get_images':
        return _executeGetImagesTool(call);
      case 'search_segments':
        return _executeSearchSegmentsTool(
          call,
          toolStartMs: toolStartMs,
          toolEndMs: toolEndMs,
        );
      case 'get_segment_result':
        return _executeGetSegmentResultTool(call);
      case 'get_segment_samples':
        return _executeGetSegmentSamplesTool(call);
      case 'search_screenshots_ocr':
        return _executeSearchScreenshotsOcrTool(
          call,
          toolStartMs: toolStartMs,
          toolEndMs: toolEndMs,
        );
      case 'search_ai_image_meta':
        return _executeSearchAiImageMetaTool(
          call,
          toolStartMs: toolStartMs,
          toolEndMs: toolEndMs,
        );
      case 'search_memory_graph':
        return _executeSearchMemoryGraphTool(call);
      default:
        return <AIMessage>[
          AIMessage(
            role: 'tool',
            content: jsonEncode(<String, dynamic>{
              'error': 'unknown_tool',
              'tool': call.name,
            }),
            toolCallId: call.id,
          ),
        ];
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
      final List<AIMessage> full = await _chatContext.loadRecentMessagesForPrompt(
        cid: cid,
        maxTokens: maxHistoryPromptTokens,
      );
      if (full.isNotEmpty) requestHistory = full;
    } catch (_) {}

    final String systemPrompt = _systemPromptForLocale();
    final List<String> extras = <String>[];
    try {
      final String ctxMsg =
          await _chatContext.buildSystemContextMessage(cid: cid);
      if (ctxMsg.trim().isNotEmpty) extras.add(ctxMsg.trim());
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
          tokensApprox: PromptBudget.approxTokensForMessagesJson(requestMessages),
        ),
      );
    } catch (_) {}

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
        final List<AIMessage> full = await _chatContext.loadRecentMessagesForPrompt(
          cid: cid,
          maxTokens: maxHistoryPromptTokens,
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
    if (context == 'chat' && persistHistory) {
      try {
        final String ctxMsg =
            await _chatContext.buildSystemContextMessage(cid: cid);
        if (ctxMsg.trim().isNotEmpty) effectiveExtras.add(ctxMsg.trim());
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
            tokensApprox:
                PromptBudget.approxTokensForMessagesJson(requestMessages),
          ),
        );
      } catch (_) {}
    }

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
        final List<AIMessage> full = await _chatContext.loadRecentMessagesForPrompt(
          cid: cid,
          maxTokens: maxHistoryPromptTokens,
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
    if (tools.isNotEmpty) effectiveExtras.add(_buildToolUsageInstruction(tools));
    if (context == 'chat' && persistHistory) {
      try {
        final String ctxMsg =
            await _chatContext.buildSystemContextMessage(cid: cid);
        if (ctxMsg.trim().isNotEmpty) effectiveExtras.add(ctxMsg.trim());
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
            tokensApprox:
                PromptBudget.approxTokensForMessagesJson(requestMessages),
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
          responseStartMarker: responseStartMarker,
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
        responseStartMarker: responseStartMarker,
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
    // 若担心模型陷入循环，只能使用“无进展/重复参数”的护栏（例如去重、强提示、临时禁用 tools）
    // 来打断重复，而不是用固定轮次截断（否则会破坏跨月/跨年检索等长任务）。
    final bool unlimitedIters = maxToolIters <= 0;
    int iters = 0;
    int totalToolCalls = 0;
    bool forcedEmptySearchRetry = false;
    bool hadAnyRetrievalHit = false;
    String lastRetrievalTool = '';
    int lastRetrievalCount = -1;
    final Set<String> seenToolSignatures = <String>{};
    final Map<String, Map<String, dynamic>> signatureDigests =
        <String, Map<String, dynamic>>{};
    int consecutiveDuplicateBatches = 0;
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

      // Execute each tool call and append tool + follow-up user messages
      int idxInBatch = 0;
      bool executedAnyNew = false;
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
        if (seenToolSignatures.contains(signature)) {
          final Map<String, dynamic>? prev = signatureDigests[signature];
          _emitProgress(
            emitEvent,
            _loc(
              '检测到重复工具调用参数，已跳过执行：${call.name}',
              'Detected duplicate tool call args; skipping: ${call.name}',
            ),
          );
          working.add(
            AIMessage(
              role: 'tool',
              content: jsonEncode(<String, dynamic>{
                'tool': call.name,
                'warning': 'duplicate_tool_call_skipped',
                if (prev != null && prev.isNotEmpty)
                  'previous_result_digest': prev,
                'message': _loc(
                  '已跳过与之前完全相同参数的工具调用；请基于已有工具结果继续推理/统计并回答。'
                      '如需更多信息，请更换关键词、调整时间窗或使用 paging/offset 获取新的结果。',
                  'Skipped an identical tool call; use the existing tool outputs to reason/count and answer. '
                      'If you still need more information, change keywords, adjust time window, or use paging/offset to fetch NEW results.',
                ),
              }),
              toolCallId: call.id,
            ),
          );
          continue;
        }
        seenToolSignatures.add(signature);
        executedAnyNew = true;

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
      }

      if (!executedAnyNew) {
        consecutiveDuplicateBatches += 1;
        working.add(
          AIMessage(
            role: 'user',
            content: _loc(
              '你正在重复调用完全相同参数的工具，这不会带来新信息。\n'
                  '请不要再重复同参数调用；请基于已返回的工具结果汇总/统计并给出最终回答。\n'
                  '如果仍需检索：必须更换关键词，或使用 paging.prev/paging.next 翻页，或调整 offset/limit 获取“新的”结果。',
              'You are repeating identical tool calls; this will not produce new information.\n'
                  'Do NOT repeat the same-argument calls again; summarize/count based on the tool outputs already returned, then answer.\n'
                  'If you still need to search: change keywords, or page via paging.prev/paging.next, or adjust offset/limit to fetch NEW results.',
            ),
          ),
        );
      } else {
        consecutiveDuplicateBatches = 0;
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
      final bool forceNoTools = (consecutiveDuplicateBatches >= 2 ||
              shouldForceNoProgressStop) &&
          result.toolCalls.isNotEmpty;
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
      ...extraSystemMessages
          .where((msg) => msg.trim().isNotEmpty)
          .map((msg) => AIMessage(role: 'system', content: msg.trim())),
    ];
    if (includeHistory && history.isNotEmpty) {
      final List<AIMessage> trimmedHistory =
          PromptBudget.keepTailUnderTokenBudget(
            history,
            maxTokens: maxHistoryPromptTokens,
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
    String? conversationTitle,
  }) async {
    if (!persistHistory) return;

    final AIMessage user = AIMessage(role: 'user', content: userMessage);
    final List<AIMessage> newHistory = <AIMessage>[...history, user, assistant];
    await _settings.saveChatHistoryActive(newHistory);
    await _updateConversationModel(modelUsed);

    // Best-effort: ingest user chat into local memory backend (async, non-blocking).
    try {
      final String cid = await _settings.getActiveConversationCid();
      // Keep a separate append-only transcript + compacted memory for long chats.
      try {
        await _chatContext.seedFromChatHistoryIfEmpty(cid: cid, history: history);
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
      await _settings.renameConversation(cid, title);
    } catch (_) {}
  }

  String _truncateTitle(String text) {
    if (text.length <= 30) return text;
    return text.substring(0, 30) + '...';
  }
}
