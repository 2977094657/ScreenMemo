part of 'ai_chat_service.dart';

extension AIChatServiceCoreExt on AIChatService {
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
        '- 允许重复调用同一工具的相同参数（例如刷新/确认）；若多次结果无变化，可再尝试更换关键词/分页 paging/offset/时间窗。',
        '- You MAY repeat the same tool call with the same arguments (e.g., refresh/confirm). If results do not change, try different keywords / paging / offset / time window.',
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
      sb.writeln(
        _loc(
          '- 相对时间默认解析：按自然时间段理解并先执行检索，不要先反问用户。',
          '- Relative time defaults: interpret as calendar periods and run retrieval first; do not ask the user first.',
        ),
      );
      sb.writeln(
        _loc(
          '- 大范围检索若返回 paging.prev/paging.next 或 clamped 提示，优先自动翻页继续覆盖；仅在硬阻塞时才向用户提 1 个关键问题。',
          '- For wide-range retrieval, if tools return paging.prev/paging.next or clamped hints, auto-page first to expand coverage; ask at most ONE key question only on hard blockers.',
        ),
      );
      sb.writeln(
        _loc(
          '- 非硬阻塞场景不要把选择题/确认题直接抛给用户；先给已覆盖范围、未覆盖范围与下一步计划。',
          '- In non-blocking scenarios, avoid pushing choice/confirmation questions to the user; first provide covered scope, uncovered scope, and next steps.',
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
    final String low = t.toLowerCase();

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

  bool _contentLooksLikeClarificationStop(String content) {
    final String t = content.trim();
    if (t.isEmpty) return false;
    final String low = t.toLowerCase();

    final bool asks =
        t.contains('?') ||
        t.contains('？') ||
        t.contains('请确认') ||
        t.contains('请问') ||
        t.contains('能否') ||
        t.contains('是否') ||
        t.contains('先确认') ||
        t.contains('你选') ||
        t.contains('你回复') ||
        t.contains('还需要确认') ||
        t.contains('补充') ||
        low.contains('please confirm') ||
        low.contains('could you') ||
        low.contains('can you') ||
        low.contains('which one') ||
        low.contains('do you mean') ||
        low.contains('need to confirm') ||
        low.contains('please provide');
    if (!asks) return false;

    final bool hasCoverageOrExecution =
        t.contains('已覆盖') ||
        t.contains('未覆盖') ||
        t.contains('继续翻页') ||
        t.contains('paging.prev') ||
        t.contains('paging.next') ||
        t.contains('下一步') ||
        low.contains('covered') ||
        low.contains('uncovered') ||
        low.contains('paging.prev') ||
        low.contains('paging.next') ||
        low.contains('next step');

    // Clarification-heavy response with no concrete execution/coverage signal.
    return !hasCoverageOrExecution;
  }

  bool debugContentLooksLikeHardNoResultsConclusion(String content) {
    return _contentLooksLikeHardNoResultsConclusion(content);
  }

  bool debugContentLooksLikeClarificationStop(String content) {
    return _contentLooksLikeClarificationStop(content);
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
}
