part of '../ai_settings_page.dart';

extension _AISettingsPageStateSendMessageExt on _AISettingsPageState {
  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      UINotifier.error(
        context,
        AppLocalizations.of(context).messageCannotBeEmpty,
      );
      return;
    }
    _setState(() {
      _sending = true;
    });
    try {
      // 先本地追加用户消息，提升即时反馈
      _setState(() {
        _messages = List<AIMessage>.from(_messages)
          ..add(AIMessage(role: 'user', content: text));
      });
      _inputController.clear();
      _scheduleAutoScroll();

      if (_streamEnabled) {
        // 追加一个空的助手消息作为占位，并进入"思考中"可视化状态
        final int assistantIdx = _messages.length;
        QueryContextPack? ctxPackForRewrite;
        final DateTime createdAt = DateTime.now();
        _setState(() {
          _inStreaming = true;
          _thinkingText = '';
          _showThinkingContent = false; // 默认折叠
          // 使用当前时刻作为占位消息的 createdAt，用于正确计算思考耗时
          _messages = List<AIMessage>.from(_messages)
            ..add(
              AIMessage(role: 'assistant', content: '', createdAt: createdAt),
            );
          _currentAssistantIndex = assistantIdx;
          _reasoningByIndex[assistantIdx] = '';
          _reasoningDurationByIndex.remove(assistantIdx);

          final _ThinkingBlock first = _ThinkingBlock(createdAt: createdAt);
          first.events.add(
            _ThinkingEvent(
              type: _ThinkingEventType.intent,
              title: _isZhLocale() ? '分析查询意图' : 'Analyze intent',
              icon: Icons.search_outlined,
              active: true,
            ),
          );
          _thinkingBlocksByIndex[assistantIdx] = <_ThinkingBlock>[first];
          _contentSegmentsByIndex[assistantIdx] = <String>[];
          _nextContentStartsNewSegmentByIndex[assistantIdx] = true;
        });
        _markInFlightHistoryDirty();
        _startDots();
        _scheduleAutoScroll();
        _scheduleReasoningPreviewScroll();
        _appendAgentLog(
          _isZhLocale() ? '开始处理本次请求' : 'Start handling request',
          bullet: false,
        );

        // 阶段 1/4：意图分析
        try {
          await FlutterLogger.nativeInfo(
            'ChatFlow',
            'phase1 intent begin text="${text.length > 200 ? (text.substring(0, 200) + '…') : text}"',
          );
          _setState(() {
            final lastIdx = _messages.length - 1;
            final last = _messages[lastIdx];
            if (last.role == 'assistant') {
              _messages[lastIdx] = AIMessage(
                role: 'assistant',
                content: '1/4 分析用户意图…',
                createdAt: last.createdAt,
              );
            }
          });
          _appendAgentLog(
            _isZhLocale() ? '阶段 1/4：意图分析' : 'Phase 1/4: intent analysis',
            bullet: false,
          );

          IntentResult? intent;
          String userQuestionForFinal = text;
          bool localOnlyResponse = false;
          String localAssistantText = '';
          AIStreamingSession? session;
          late QueryContextPack ctxPack;
          bool reuse = false;

          // 0) 如果处于澄清流程且用户选择取消，则结束本次查找
          if (_clarifyState != null && _isCancelMessage(text)) {
            _appendAgentLog(
              _isZhLocale()
                  ? '检测到取消指令：本次查找结束（不发起网络请求）'
                  : 'Cancel detected: stop (no network request)',
            );
            _clarifyState = null;
            localOnlyResponse = true;
            localAssistantText = _isZhLocale()
                ? '好的，已取消本次查找。你可以随时再问我。'
                : 'Ok, canceled. You can ask again anytime.';
          }

          // 1) 若正在等待“候选选择”，优先处理用户选择（回复序号）
          final _ClarifyState? clarify0 = _clarifyState;
          if (!localOnlyResponse &&
              clarify0 != null &&
              clarify0.stage == _ClarifyStage.pickCandidate) {
            _appendAgentLog(
              _isZhLocale()
                  ? '澄清流程：解析候选选择…'
                  : 'Clarification: parsing candidate selection…',
            );
            final int? pick = _parsePickIndex(text, clarify0.candidates.length);
            if (pick != null) {
              final _ProbeCandidate c = clarify0.candidates[pick - 1];
              _appendAgentLog(
                _isZhLocale()
                    ? '已选择候选 #$pick，定位时间窗…'
                    : 'Picked candidate #$pick, using its time window…',
              );
              String tzReadable() {
                final Duration off = DateTime.now().timeZoneOffset;
                final int mins = off.inMinutes;
                final String sign = mins >= 0 ? '+' : '-';
                final int abs = mins.abs();
                final String hh = (abs ~/ 60).toString().padLeft(2, '0');
                final String mm = (abs % 60).toString().padLeft(2, '0');
                return 'UTC$sign$hh:$mm';
              }

              intent = IntentResult(
                intent: 'pick_candidate',
                intentSummary: _isZhLocale() ? '根据候选定位' : 'Locate by candidate',
                startMs: c.startMs,
                endMs: c.endMs,
                timezone: tzReadable(),
                apps: const <String>[],
                sqlFill: const <String, dynamic>{},
                skipContext: false,
                contextAction: 'refresh',
              );
              userQuestionForFinal = _composeFinalUserQuestionFromClarify(
                clarify0,
              );
              _clarifyState = null;
            } else {
              // 不是序号：视为“都不是/补充线索”，直接根据新线索再跑一次探测检索
              if (!_isCancelMessage(text)) {
                clarify0.supplements.add(text);
              }
              final String probeQ = _clipOneLine(
                _composeFinalUserQuestionFromClarify(clarify0),
                80,
              );
              _appendAgentLog(
                _isZhLocale()
                    ? '未识别到序号：基于补充线索做一次探测检索…'
                    : 'No pick index: probing candidates from supplemental hints…',
              );
              final Stopwatch swProbe = Stopwatch()..start();
              final List<_ProbeCandidate> cands = await _probeCandidates(
                query: probeQ.isEmpty ? _clipOneLine(text, 80) : probeQ,
                state: clarify0,
                limit: 6,
              );
              swProbe.stop();
              _appendAgentLog(
                _isZhLocale()
                    ? '探测检索完成：候选 ${cands.length}（${swProbe.elapsedMilliseconds}ms）'
                    : 'Probe done: ${cands.length} candidates (${swProbe.elapsedMilliseconds}ms)',
              );
              clarify0.candidates
                ..clear()
                ..addAll(cands);
              clarify0.stage = _ClarifyStage.pickCandidate;
              clarify0.lastProbeKind = cands.isNotEmpty
                  ? cands.first.kind
                  : _ProbeKind.none;
              localAssistantText = await _buildProbePickMessage(
                clarify0,
                cands,
              );
              localOnlyResponse = true;
            }
          }

          // 2) 正常意图分析（或澄清补充阶段：将补充信息合并进分析输入）
          if (!localOnlyResponse && intent == null) {
            String analyzeInput = text;
            final _ClarifyState? clarifyAsk = _clarifyState;
            if (clarifyAsk != null && clarifyAsk.stage == _ClarifyStage.ask) {
              // 将本轮用户输入作为补充信息
              if (!_isCancelMessage(text)) clarifyAsk.supplements.add(text);
              userQuestionForFinal = _composeFinalUserQuestionFromClarify(
                clarifyAsk,
              );
              analyzeInput = _composeClarifyIntentInput(clarifyAsk);
            }

            if (!localOnlyResponse) {
              final String preview = _clipOneLine(analyzeInput, 80);
              _appendAgentLog(
                _isZhLocale()
                    ? '调用意图分析模型…${preview.isEmpty ? '' : ' input="' + preview + '"'}'
                    : 'Calling intent model…${preview.isEmpty ? '' : ' input=\"' + preview + '\"'}',
              );
              final Stopwatch swIntent = Stopwatch()..start();
              intent = await IntentAnalysisService.instance.analyze(
                analyzeInput,
                previous: _lastIntent == null
                    ? null
                    : IntentPrevHint(
                        startMs: _lastIntent!.startMs,
                        endMs: _lastIntent!.endMs,
                        apps: _lastIntent!.apps,
                        summary: _lastIntent!.intentSummary,
                      ),
                previousUserQueries: _extractPreviousUserQueries(maxCount: 3),
              );
              swIntent.stop();
              final String range = intent!.hasValidRange
                  ? '[${intent!.startMs}-${intent!.endMs}]'
                  : '<invalid>';
              final String err = (intent!.errorCode ?? '').trim();
              _appendAgentLog(
                _isZhLocale()
                    ? '意图解析完成：${intent!.intentSummary} range=$range skipContext=${intent!.skipContext ? 1 : 0} contextAction=${intent!.contextAction}${err.isEmpty ? '' : ' error=' + err}（${swIntent.elapsedMilliseconds}ms）'
                    : 'Intent done: ${intent!.intentSummary} range=$range skipContext=${intent!.skipContext ? 1 : 0} contextAction=${intent!.contextAction}${err.isEmpty ? '' : ' error=' + err} (${swIntent.elapsedMilliseconds}ms)',
              );
            }
          }

          // 3) 缺少有效时间窗：优先在“续问”场景复用上一轮，否则自动补全默认范围继续检索
          if (!localOnlyResponse &&
              intent != null &&
              !intent!.hasValidRange &&
              !_intentAllowsNoTimeRange(intent!)) {
            _appendAgentLog(
              _isZhLocale()
                  ? '未解析到有效时间窗：尝试复用上一轮，否则使用默认范围继续检索…'
                  : 'No valid time range: try reuse previous; otherwise use a default range…',
            );
            final bool hasPreviousWindow =
                (_lastIntent != null && _lastIntent!.hasValidRange) ||
                (_lastCtxPack != null) ||
                (QueryContextService.instance.lastPack != null);
            final bool canReusePrevious =
                hasPreviousWindow && intent!.skipContext;
            if (canReusePrevious) {
              _appendAgentLog(
                _isZhLocale()
                    ? '尝试复用上一轮时间窗…'
                    : 'Trying to reuse previous time window…',
              );
              int? fbStart;
              int? fbEnd;
              if (_lastIntent != null && _lastIntent!.hasValidRange) {
                fbStart = _lastIntent!.startMs;
                fbEnd = _lastIntent!.endMs;
              } else if (_lastCtxPack != null) {
                fbStart = _lastCtxPack!.startMs;
                fbEnd = _lastCtxPack!.endMs;
              } else if (QueryContextService.instance.lastPack != null) {
                final p = QueryContextService.instance.lastPack!;
                fbStart = p.startMs;
                fbEnd = p.endMs;
              }
              if (fbStart != null && fbEnd != null && fbEnd >= fbStart) {
                _appendAgentLog(
                  _isZhLocale()
                      ? '已复用上一轮时间窗：[$fbStart-$fbEnd]'
                      : 'Reused previous window: [$fbStart-$fbEnd]',
                );
                intent = IntentResult(
                  intent: intent!.intent,
                  intentSummary: intent!.intentSummary.isNotEmpty
                      ? intent!.intentSummary
                      : '复用上一轮时间窗',
                  startMs: fbStart,
                  endMs: fbEnd,
                  timezone: intent!.timezone,
                  apps: intent!.apps,
                  keywords: intent!.keywords,
                  sqlFill: intent!.sqlFill,
                  skipContext: true,
                  errorCode: intent!.errorCode,
                  errorMessage: intent!.errorMessage,
                );
              } else {
                _appendAgentLog(
                  _isZhLocale()
                      ? '复用失败：没有可用的上一轮范围，将使用默认时间范围继续检索'
                      : 'Reuse failed: no previous window; using a default time range',
                );
                intent = _applyDefaultTimeRange(intent!);
                _appendAgentLog(
                  _isZhLocale()
                      ? '已自动补全默认时间范围：range=[${intent!.startMs}-${intent!.endMs}]'
                      : 'Auto-filled default time range: range=[${intent!.startMs}-${intent!.endMs}]',
                );
              }
            } else {
              _appendAgentLog(
                _isZhLocale()
                    ? '没有可复用的上一轮范围：将使用默认时间范围继续检索'
                    : 'No reusable previous window: using a default time range',
              );
              intent = _applyDefaultTimeRange(intent!);
              _appendAgentLog(
                _isZhLocale()
                    ? '已自动补全默认时间范围：range=[${intent!.startMs}-${intent!.endMs}]'
                    : 'Auto-filled default time range: range=[${intent!.startMs}-${intent!.endMs}]',
              );
            }
          }

          // 4) 时间范围过大且缺少线索：不追问，直接继续检索（必要时由模型通过工具分页/扩展范围）
          if (!localOnlyResponse &&
              intent != null &&
              !intent!.userWantsProceed &&
              _isOverlyBroadQuery(
                intent!,
                userQuestionForFinal,
                clarify: _clarifyState,
              )) {
            _appendAgentLog(
              _isZhLocale()
                  ? '时间范围较大：继续直接检索（不再向用户追问）'
                  : 'Large time range: proceeding without clarification',
            );
          }

          if (localOnlyResponse) {
            _appendAgentLog(
              _isZhLocale()
                  ? '本轮进入本地澄清/候选回复：不进行上下文检索与回答生成'
                  : 'Local clarification/candidates: skip context retrieval and answering',
            );
            _setState(() {
              final lastIdx = _messages.length - 1;
              final last = _messages[lastIdx];
              if (last.role == 'assistant') {
                _messages[lastIdx] = AIMessage(
                  role: 'assistant',
                  content: localAssistantText,
                  createdAt: last.createdAt,
                );
              }
              _contentSegmentsByIndex[assistantIdx] = <String>[
                localAssistantText,
              ];
              _finishActiveThinkingBlock(assistantIdx);
            });
            // 本地澄清/候选不走流式网络请求
            _stopDots();
            session = null;
          } else {
            final IntentResult resolvedIntent = intent!;
            final bool noContext = _intentAllowsNoTimeRange(resolvedIntent);

            // 清理澄清状态，避免污染下一轮
            if (_clarifyState != null &&
                (noContext || resolvedIntent.hasValidRange)) {
              if (noContext) {
                _appendAgentLog(
                  _isZhLocale()
                      ? '检测到非检索问题：退出澄清流程'
                      : 'Non-retrieval intent: exiting clarification flow',
                );
              }
              _clarifyState = null;
            }

            if (noContext) {
              await FlutterLogger.nativeInfo(
                'ChatFlow',
                'phase1 intent ok (no-context) intent=${resolvedIntent.intent} summary=${resolvedIntent.intentSummary}',
              );
              _appendAgentLog(
                _isZhLocale()
                    ? '意图已确认：${resolvedIntent.intentSummary}（无需时间窗/上下文检索）'
                    : 'Intent confirmed: ${resolvedIntent.intentSummary} (no time/context needed)',
              );
              _setState(() {
                final List<_ThinkingBlock>? blocks =
                    _thinkingBlocksByIndex[assistantIdx];
                if (blocks == null || blocks.isEmpty) return;
                final _ThinkingBlock b = blocks.last;
                _upsertEvent(
                  b,
                  type: _ThinkingEventType.intent,
                  title: _isZhLocale() ? '分析查询意图' : 'Analyze intent',
                  icon: Icons.search_outlined,
                  active: false,
                  subtitle: _formatIntentSubtitle(resolvedIntent),
                );
              });
              _renameActiveConversationTo(resolvedIntent.intentSummary);
              _setState(() {
                final lastIdx = _messages.length - 1;
                final last = _messages[lastIdx];
                if (last.role == 'assistant') {
                  _messages[lastIdx] = AIMessage(
                    role: 'assistant',
                    content: _isZhLocale()
                        ? '1/4 意图: ${resolvedIntent.intentSummary}\n\n2/4 无需上下文\n\n3/4 生成回答…'
                        : '1/4 Intent: ${resolvedIntent.intentSummary}\n\n2/4 No context needed\n\n3/4 Generating answer…',
                    createdAt: last.createdAt,
                  );
                }
              });
              _appendAgentLog(
                _isZhLocale() ? '阶段 3/4：生成回答' : 'Phase 3/4: generating answer',
                bullet: false,
              );
              _replaceAssistantContentOnNextToken = true; // 首个 token 到来时清空阶段状态
              session = await _chat.sendMessageStreamedV2WithDisplayOverride(
                text,
                text,
                includeHistory: true,
                // UI persists a post-processed version (e.g. evidence tag rewrites).
                // Prevent service-level tail persistence from overwriting UI history.
                persistHistoryTail: false,
                tools: AIChatService.defaultChatTools(),
                toolChoice: 'auto',
              );
            } else {
              await FlutterLogger.nativeInfo(
                'ChatFlow',
                'phase1 intent ok range=[${resolvedIntent.startMs}-${resolvedIntent.endMs}] summary=${resolvedIntent.intentSummary} apps=${resolvedIntent.apps.length}',
              );
              _appendAgentLog(
                _isZhLocale()
                    ? '意图已确认：${resolvedIntent.intentSummary} range=[${resolvedIntent.startMs}-${resolvedIntent.endMs}]'
                    : 'Intent confirmed: ${resolvedIntent.intentSummary} range=[${resolvedIntent.startMs}-${resolvedIntent.endMs}]',
              );

              // 显示意图摘要与时间窗
              _setState(() {
                final lastIdx = _messages.length - 1;
                final last = _messages[lastIdx];
                if (last.role == 'assistant') {
                  final start = DateTime.fromMillisecondsSinceEpoch(
                    resolvedIntent.startMs,
                  );
                  final end = DateTime.fromMillisecondsSinceEpoch(
                    resolvedIntent.endMs,
                  );
                  String two(int v) => v.toString().padLeft(2, '0');
                  String ymd(DateTime d) =>
                      '${d.year}-${two(d.month)}-${two(d.day)}';
                  final String dateLine =
                      (start.year == end.year &&
                          start.month == end.month &&
                          start.day == end.day)
                      ? '日期: ' + ymd(start)
                      : '日期: ' + ymd(start) + ' → ' + ymd(end);
                  final String range =
                      '${two(start.hour)}:${two(start.minute)}-${two(end.hour)}:${two(end.minute)}';
                  final updated =
                      '1/4 意图: ${resolvedIntent.intentSummary}\n' +
                      dateLine +
                      '\n时间: ' +
                      range +
                      ' (' +
                      resolvedIntent.timezone +
                      ')\n\n2/4 查找上下文…';
                  _messages[lastIdx] = AIMessage(
                    role: 'assistant',
                    content: updated,
                    createdAt: last.createdAt,
                  );
                }

                final List<_ThinkingBlock>? blocks =
                    _thinkingBlocksByIndex[assistantIdx];
                if (blocks != null && blocks.isNotEmpty) {
                  final _ThinkingBlock b = blocks.last;
                  _upsertEvent(
                    b,
                    type: _ThinkingEventType.intent,
                    title: _isZhLocale() ? '分析查询意图' : 'Analyze intent',
                    icon: Icons.search_outlined,
                    active: false,
                    subtitle: _formatIntentSubtitle(resolvedIntent),
                  );
                }
              });
              _renameActiveConversationTo(resolvedIntent.intentSummary);

              // 阶段 2/4：查找上下文（若 AI 判定可复用上一轮上下文，则跳过新的检索）
              await FlutterLogger.nativeInfo('ChatFlow', '阶段2 上下文开始');
              _appendAgentLog(
                _isZhLocale() ? '阶段 2/4：查找上下文' : 'Phase 2/4: building context',
                bullet: false,
              );
              final String ctxAction = (resolvedIntent.contextAction)
                  .trim()
                  .toLowerCase();
              reuse =
                  resolvedIntent.skipContext &&
                  ctxAction == 'reuse' &&
                  (_lastCtxPack != null ||
                      QueryContextService.instance.lastPack != null);
              _appendAgentLog(
                _isZhLocale()
                    ? '复用上一轮上下文：' + (reuse ? '是' : '否')
                    : 'Reuse previous context: ' + (reuse ? 'yes' : 'no'),
              );
              _appendAgentLog(
                _isZhLocale()
                    ? '上下文策略：' + ctxAction
                    : 'Context action: ' + ctxAction,
              );
              if (resolvedIntent.skipContext && !reuse) {
                _appendAgentLog(
                  _isZhLocale()
                      ? '意图模型建议不复用缓存上下文，将重新检索/翻页以获取更多证据。'
                      : 'Intent model suggests not reusing cached context; will refresh/page for more evidence.',
                );
              }

              // 不限制上下文事件数量；预加载少量证据图片“文件名/路径”（不预加载像素）。
              // 目的：让模型可以直接引用 filename（而不是臆造），从而在 UI 中稳定渲染图片证据。
              const int maxEvents = 0;
              // 证据图片：预加载文件名/路径（不预加载像素）；段内最多 15 张，总计最多 360 张（并尽量在段落间均匀分配）。
              const int maxImagesTotal = 360;
              const int maxImagesPerEvent = 15;

              // 当范围超过 7 天时，按周预加载（避免提示词过大导致超时/输入上限）。
              final int fullStartMs = resolvedIntent.startMs;
              final int fullEndMs = resolvedIntent.endMs;
              int preloadStartMs = fullStartMs;
              int preloadEndMs = fullEndMs;
              final bool windowed =
                  (fullEndMs - fullStartMs) > AIChatService.maxToolTimeSpanMs;
              if (windowed) {
                preloadEndMs = fullEndMs;
                preloadStartMs = fullEndMs - AIChatService.maxToolTimeSpanMs;
                if (preloadStartMs < fullStartMs) preloadStartMs = fullStartMs;
                _appendAgentLog(
                  _isZhLocale()
                      ? '时间范围较大：上下文按周分页，本次预加载 7 天窗口 range=[$preloadStartMs-$preloadEndMs]'
                      : 'Large time range: paging context by week; preloading a 7-day window range=[$preloadStartMs-$preloadEndMs]',
                );
              }

              // When the intent model asks to page within a multi-week range, move the
              // 7-day preload window accordingly instead of repeatedly using the same week.
              if (windowed &&
                  !reuse &&
                  (ctxAction == 'page_prev' || ctxAction == 'page_next')) {
                final QueryContextPack? prevPack =
                    (_lastCtxPack ?? QueryContextService.instance.lastPack);
                if (prevPack != null &&
                    prevPack.startMs >= fullStartMs &&
                    prevPack.endMs <= fullEndMs) {
                  if (ctxAction == 'page_prev' &&
                      prevPack.startMs > fullStartMs) {
                    final int prevEnd0 = prevPack.startMs - 1;
                    int nextEndMs = prevEnd0;
                    if (nextEndMs < fullStartMs) nextEndMs = fullStartMs;
                    int nextStartMs =
                        nextEndMs - AIChatService.maxToolTimeSpanMs;
                    if (nextStartMs < fullStartMs) nextStartMs = fullStartMs;
                    if (nextStartMs > nextEndMs) nextStartMs = nextEndMs;
                    preloadStartMs = nextStartMs;
                    preloadEndMs = nextEndMs;
                    _appendAgentLog(
                      _isZhLocale()
                          ? '自动翻页：加载上一周上下文 range=[$preloadStartMs-$preloadEndMs]'
                          : 'Auto paging: load previous week range=[$preloadStartMs-$preloadEndMs]',
                    );
                  } else if (ctxAction == 'page_next' &&
                      prevPack.endMs < fullEndMs) {
                    final int nextStart0 = prevPack.endMs + 1;
                    int nextStartMs = nextStart0;
                    if (nextStartMs > fullEndMs) nextStartMs = fullEndMs;
                    int nextEndMs =
                        nextStartMs + AIChatService.maxToolTimeSpanMs;
                    if (nextEndMs > fullEndMs) nextEndMs = fullEndMs;
                    if (nextStartMs > nextEndMs) nextStartMs = nextEndMs;
                    preloadStartMs = nextStartMs;
                    preloadEndMs = nextEndMs;
                    _appendAgentLog(
                      _isZhLocale()
                          ? '自动翻页：加载下一周上下文 range=[$preloadStartMs-$preloadEndMs]'
                          : 'Auto paging: load next week range=[$preloadStartMs-$preloadEndMs]',
                    );
                  } else {
                    _appendAgentLog(
                      _isZhLocale()
                          ? '已到达可翻页边界（或窗口无变化），将按当前周继续检索。'
                          : 'Reached paging boundary (or no window change); continue with current window.',
                    );
                  }
                } else {
                  _appendAgentLog(
                    _isZhLocale()
                        ? '无可用缓存窗口用于翻页，将按当前周继续检索。'
                        : 'No cached window for paging; continue with current window.',
                  );
                }
              }

              if (reuse) {
                _appendAgentLog(
                  _isZhLocale() ? '使用缓存上下文包' : 'Using cached context pack',
                );
                ctxPack =
                    (_lastCtxPack ?? QueryContextService.instance.lastPack!);
                ctxPackForRewrite = ctxPack;
              } else {
                _appendAgentLog(
                  _isZhLocale()
                      ? '查询本地数据库并组装上下文…'
                      : 'Querying local DB and assembling context…',
                );
                _setState(() {
                  final _ThinkingBlock b = _ensureThinkingBlock(assistantIdx);
                  final DateTime ds = DateTime.fromMillisecondsSinceEpoch(
                    preloadStartMs,
                  );
                  final DateTime de = DateTime.fromMillisecondsSinceEpoch(
                    preloadEndMs,
                  );
                  String two(int v) => v.toString().padLeft(2, '0');
                  String ymd(DateTime d) =>
                      '${d.year}-${two(d.month)}-${two(d.day)}';
                  String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
                  String dt(DateTime d) => '${ymd(d)} ${hm(d)}';
                  _upsertEvent(
                    b,
                    type: _ThinkingEventType.status,
                    title: _isZhLocale() ? '搜索' : 'Search',
                    icon: Icons.manage_search_outlined,
                    active: true,
                    subtitle: _isZhLocale()
                        ? '${dt(ds)} 至 ${dt(de)} 的事件'
                        : '${dt(ds)} to ${dt(de)}',
                  );
                });
                final Stopwatch swCtx = Stopwatch()..start();
                ctxPack = await QueryContextService.instance.buildContext(
                  startMs: preloadStartMs,
                  endMs: preloadEndMs,
                  maxEvents: maxEvents,
                  maxImagesTotal: maxImagesTotal,
                  maxImagesPerEvent: maxImagesPerEvent,
                  includeImages: true,
                );
                ctxPackForRewrite = ctxPack;
                swCtx.stop();
                _appendAgentLog(
                  _isZhLocale()
                      ? '上下文组装完成：events=${ctxPack.events.length}（${swCtx.elapsedMilliseconds}ms）'
                      : 'Context ready: events=${ctxPack.events.length} (${swCtx.elapsedMilliseconds}ms)',
                );
                _setState(() {
                  final List<_ThinkingBlock>? blocks =
                      _thinkingBlocksByIndex[assistantIdx];
                  if (blocks == null || blocks.isEmpty) return;
                  for (final e in blocks.last.events) {
                    if (e.type == _ThinkingEventType.status &&
                        e.title == (_isZhLocale() ? '搜索' : 'Search')) {
                      e.active = false;
                    }
                  }
                });
              }
              await FlutterLogger.nativeInfo(
                'ChatFlow',
                'phase2 context ok events=${ctxPack.events.length} reuse=${reuse ? 1 : 0}',
              );
              // 缓存上下文（页面内缓存与服务级缓存），便于紧邻多轮对话复用
              _lastCtxPack = ctxPack;
              try {
                QueryContextService.instance.setLastPack(ctxPack);
              } catch (_) {}
              // 证据图片像素不预加载；仅预加载少量文件名/路径，供 UI 渲染与模型引用。
              final List<EvidenceImageAttachment> attachments = (() {
                final Set<String> seen = <String>{};
                final List<EvidenceImageAttachment> out =
                    <EvidenceImageAttachment>[];
                for (final ev in ctxPack.events) {
                  for (final a in ev.keyImages) {
                    if (a.path.isEmpty) continue;
                    if (seen.add(a.path)) out.add(a);
                  }
                }
                return out;
              })();
              _appendAgentLog(
                _isZhLocale()
                    ? '证据图片：预加载文件名/路径 ${attachments.length} 条（不预加载像素；需要看原图像素再用 get_images）'
                    : 'Evidence images: preloaded filenames/paths ${attachments.length} (pixels not preloaded; use get_images when you must see pixels)',
              );
              _setState(() {
                _attachmentsByIndex[assistantIdx] = attachments;
                final lastIdx = _messages.length - 1;
                final last = _messages[lastIdx];
                if (last.role == 'assistant') {
                  final updated =
                      '2/4 查找上下文完成${reuse ? '（复用上一轮）' : ''}：事件 ${ctxPack.events.length}${windowed ? '（预加载 7 天窗口）' : ''}\n\n3/4 生成回答…';
                  _messages[lastIdx] = AIMessage(
                    role: 'assistant',
                    content: updated,
                    createdAt: last.createdAt,
                  );
                }
              });
              _scheduleEvidenceNsfwPreload(attachments.map((a) => a.path));

              // 生成最终提示词（包含上下文包的精简文本）
              final String finalQuery = _buildFinalQuestion(
                userQuestionForFinal,
                ctxPack,
                fullStartMs: fullStartMs,
                fullEndMs: fullEndMs,
              );
              final int finalQueryTokens = PromptBudget.approxTokensForText(
                finalQuery,
              );
              await FlutterLogger.nativeDebug(
                'ChatFlow',
                'phase3 finalQueryLen=${finalQuery.length} approxTokens=$finalQueryTokens',
              );
              _appendAgentLog(
                _isZhLocale() ? '阶段 3/4：生成回答' : 'Phase 3/4: generating answer',
                bullet: false,
              );
              _appendAgentLog(
                _isZhLocale()
                    ? '生成最终提示词：len=${finalQuery.length} tokens≈$finalQueryTokens'
                    : 'Final prompt: len=${finalQuery.length} tokens≈$finalQueryTokens',
              );
              _replaceAssistantContentOnNextToken = true; // 首个 token 到来时清空阶段状态

              // 使用"显示内容与实际发送内容分离"的新流式接口：
              final List<String> extraSystemMessages = <String>[
                _buildNowContextSystemMessage(),
              ];
              final List<Map<String, dynamic>> chatTools =
                  AIChatService.defaultChatTools();
              final bool forceToolFirstIfNoToolCalls =
                  ctxPack.events.isEmpty ||
                  resolvedIntent.intent == 'keyword_lookup' ||
                  resolvedIntent.keywords.isNotEmpty;
              _appendAgentLog(
                _isZhLocale()
                    ? '调用模型并启用工具：tools=${chatTools.length} tool_choice=auto'
                    : 'Calling model with tools: tools=${chatTools.length} tool_choice=auto',
              );
              session = await _chat.sendMessageStreamedV2WithDisplayOverride(
                text,
                finalQuery,
                includeHistory: resolvedIntent.skipContext,
                extraSystemMessages: extraSystemMessages,
                // UI persists a post-processed version (e.g. evidence tag rewrites).
                // Prevent service-level tail persistence from overwriting UI history.
                persistHistoryTail: false,
                tools: chatTools,
                toolChoice: 'auto',
                forceToolFirstIfNoToolCalls: forceToolFirstIfNoToolCalls,
              );
            }
          }

          if (session != null) {
            await for (final AIStreamEvent evt in session!.stream) {
              if (!mounted) return;
              final int? idx = _currentAssistantIndex;

              // UI 事件（工具调用等）：不作为正文输出，单独驱动“思考块”渲染。
              if (evt.kind == 'ui') {
                if (idx != null) {
                  final Map<String, dynamic>? payload = _tryParseJsonMap(
                    evt.data,
                  );
                  if (payload != null) {
                    _setState(() => _handleAiUiEvent(idx, payload));
                    _scheduleAutoScroll();
                    _markInFlightHistoryDirty();
                  }
                }
                continue;
              }

              // 禁止将模型 reasoning / 过程性文本放入“思考块”或正文（只展示结构化事件）。
              if (evt.kind == 'reasoning') {
                continue;
              }
              // 正文增量（首 token 到来时先清空阶段状态，再开始写入最终答案）
              _setState(() {
                final lastIdx = _messages.length - 1;
                final last = _messages[lastIdx];
                if (last.role == 'assistant') {
                  final String base = _replaceAssistantContentOnNextToken
                      ? ''
                      : last.content;
                  String incoming = evt.data;
                  final updated = AIMessage(
                    role: 'assistant',
                    content: base + incoming,
                    createdAt: last.createdAt, // 保留初始创建时间以准确计算思考耗时
                  );
                  final newList = List<AIMessage>.from(_messages);
                  newList[lastIdx] = updated;
                  _messages = newList;
                  _replaceAssistantContentOnNextToken = false;

                  if (idx != null && incoming.isNotEmpty) {
                    _finishActiveThinkingBlock(idx);
                    _appendContentChunk(idx, incoming);
                  }
                }
              });
              _scheduleAutoScroll();
              _markInFlightHistoryDirty();
            }
            await session!.completed;
            // 成功路径：更新"上一轮"缓存
            if (ctxPackForRewrite != null &&
                intent != null &&
                intent!.hasValidRange) {
              _lastCtxPack = ctxPackForRewrite;
              _lastIntent = intent;
            }
          }
        } catch (e) {
          try {
            await FlutterLogger.nativeError(
              'ChatFlow',
              'error ' + e.toString(),
            );
          } catch (_) {}
          if (!mounted) return;
          final String errorMessage;
          if (e is InvalidResponseStartException) {
            final String preview = e.receivedPreview.isEmpty
                ? '<empty>'
                : e.receivedPreview;
            final String truncated = preview.length > 800
                ? '${preview.substring(0, 800)}…'
                : preview;
            errorMessage =
                'Invalid response start marker. Raw preview:\n$truncated';
          } else if (e is InvalidEndpointConfigurationException) {
            errorMessage = 'Invalid endpoint configuration: ${e.message}';
          } else {
            errorMessage = e.toString();
          }
          _setState(() {
            _inStreaming = false;
            if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
              final newList = List<AIMessage>.from(_messages);
              newList[_messages.length - 1] = AIMessage(
                role: 'error',
                content: errorMessage,
              );
              _messages = newList;
            } else {
              _messages = List<AIMessage>.from(_messages)
                ..add(AIMessage(role: 'error', content: errorMessage));
            }
          });
          _stopInFlightHistoryPersistence();
          _stopDots();
          _scheduleAutoScroll();
          rethrow;
        }
        if (mounted) {
          _setState(() {
            _inStreaming = false;
            final idx = _currentAssistantIndex;
            if (idx != null && idx >= 0 && idx < _messages.length) {
              _finishActiveThinkingBlock(idx);
              // Safety net: in case we never observed a "finish" moment (e.g. stream ended early).
              _reasoningDurationByIndex[idx] ??= DateTime.now().difference(
                _messages[idx].createdAt,
              );
            }
            _currentAssistantIndex = null;
          });
          _stopInFlightHistoryPersistence();
          _stopDots();
          _scheduleAutoScroll();
          // 结束后合并深度思考内容并持久化
          try {
            final QueryContextPack? pack = ctxPackForRewrite;
            if (pack != null &&
                assistantIdx >= 0 &&
                assistantIdx < _messages.length &&
                _messages[assistantIdx].role == 'assistant') {
              // Keep segment boundaries stable by rewriting per segment first.
              final List<String>? segs0 = _contentSegmentsByIndex[assistantIdx];
              if (segs0 != null && segs0.isNotEmpty) {
                final List<String> segs1 = <String>[];
                for (final s in segs0) {
                  segs1.add(
                    await _rewriteNumericEvidenceTagsToFilenames(
                      s,
                      ctxPack: pack,
                    ),
                  );
                }
                _contentSegmentsByIndex[assistantIdx] = segs1;
                final String joined = segs1.join('');
                final AIMessage m0 = _messages[assistantIdx];
                if (joined != m0.content) {
                  final List<AIMessage> tmp = List<AIMessage>.from(_messages);
                  tmp[assistantIdx] = AIMessage(
                    role: m0.role,
                    content: joined,
                    createdAt: m0.createdAt,
                    reasoningContent: m0.reasoningContent,
                    reasoningDuration: m0.reasoningDuration,
                    uiThinkingJson: m0.uiThinkingJson,
                  );
                  _messages = tmp;
                }
              } else {
                final AIMessage m0 = _messages[assistantIdx];
                final String rewritten =
                    await _rewriteNumericEvidenceTagsToFilenames(
                      m0.content,
                      ctxPack: pack,
                    );
                if (rewritten != m0.content) {
                  final List<AIMessage> tmp = List<AIMessage>.from(_messages);
                  tmp[assistantIdx] = AIMessage(
                    role: m0.role,
                    content: rewritten,
                    createdAt: m0.createdAt,
                    reasoningContent: m0.reasoningContent,
                    reasoningDuration: m0.reasoningDuration,
                    uiThinkingJson: m0.uiThinkingJson,
                  );
                  _messages = tmp;
                }
              }
            }

            final List<AIMessage> merged = _mergeReasoningForPersistence(
              List<AIMessage>.from(_messages),
            );
            if (mounted) {
              _setState(() {
                _messages = merged;
                // After completion, render directly from the persisted `content`
                // so re-entering the page shows the exact same UI.
                _contentSegmentsByIndex.clear();
                _nextContentStartsNewSegmentByIndex.clear();
              });
            }
            await _enqueueChatHistorySave(merged);
          } catch (_) {
            try {
              final QueryContextPack? pack = ctxPackForRewrite;
              if (pack != null &&
                  assistantIdx >= 0 &&
                  assistantIdx < _messages.length &&
                  _messages[assistantIdx].role == 'assistant') {
                final List<String>? segs0 =
                    _contentSegmentsByIndex[assistantIdx];
                if (segs0 != null && segs0.isNotEmpty) {
                  final List<String> segs1 = <String>[];
                  for (final s in segs0) {
                    segs1.add(
                      await _rewriteNumericEvidenceTagsToFilenames(
                        s,
                        ctxPack: pack,
                      ),
                    );
                  }
                  _contentSegmentsByIndex[assistantIdx] = segs1;
                  final String joined = segs1.join('');
                  final AIMessage m0 = _messages[assistantIdx];
                  if (joined != m0.content) {
                    final List<AIMessage> tmp = List<AIMessage>.from(_messages);
                    tmp[assistantIdx] = AIMessage(
                      role: m0.role,
                      content: joined,
                      createdAt: m0.createdAt,
                      reasoningContent: m0.reasoningContent,
                      reasoningDuration: m0.reasoningDuration,
                      uiThinkingJson: m0.uiThinkingJson,
                    );
                    _messages = tmp;
                  }
                } else {
                  final AIMessage m0 = _messages[assistantIdx];
                  final String rewritten =
                      await _rewriteNumericEvidenceTagsToFilenames(
                        m0.content,
                        ctxPack: pack,
                      );
                  if (rewritten != m0.content) {
                    final List<AIMessage> tmp = List<AIMessage>.from(_messages);
                    tmp[assistantIdx] = AIMessage(
                      role: m0.role,
                      content: rewritten,
                      createdAt: m0.createdAt,
                      reasoningContent: m0.reasoningContent,
                      reasoningDuration: m0.reasoningDuration,
                      uiThinkingJson: m0.uiThinkingJson,
                    );
                    _messages = tmp;
                  }
                }
              }

              final List<AIMessage> toSave = _mergeReasoningForPersistence(
                List<AIMessage>.from(_messages),
              );
              await _enqueueChatHistorySave(toSave);
            } catch (_) {}
          }
        }
      } else {
        // 非流式：仍按阶段流程，最后一次性替换为最终答案
        final int assistantIdx = _messages.length;
        _setState(() {
          _thinkingText = '';
          _reasoningByIndex[assistantIdx] = '';
          _reasoningDurationByIndex.remove(assistantIdx);
          _messages = List<AIMessage>.from(_messages)
            ..add(
              AIMessage(
                role: 'assistant',
                content: '1/4 分析用户意图…',
                createdAt: DateTime.now(),
              ),
            );
        });
        _appendAgentLog(
          _isZhLocale() ? '开始处理本次请求' : 'Start handling request',
          assistantIndex: assistantIdx,
          bullet: false,
        );
        _appendAgentLog(
          _isZhLocale() ? '阶段 1/4：意图分析' : 'Phase 1/4: intent analysis',
          assistantIndex: assistantIdx,
          bullet: false,
        );

        try {
          await FlutterLogger.nativeInfo(
            'ChatFlow',
            'phase1 intent(begin, non-stream)',
          );

          IntentResult? intent;
          String userQuestionForFinal = text;
          bool localOnlyResponse = false;
          String localAssistantText = '';

          // 0) 如果处于澄清流程且用户选择取消，则结束本次查找
          if (_clarifyState != null && _isCancelMessage(text)) {
            _appendAgentLog(
              _isZhLocale()
                  ? '检测到取消指令：本次查找结束（不发起网络请求）'
                  : 'Cancel detected: stop (no network request)',
              assistantIndex: assistantIdx,
            );
            _clarifyState = null;
            localOnlyResponse = true;
            localAssistantText = _isZhLocale()
                ? '好的，已取消本次查找。你可以随时再问我。'
                : 'Ok, canceled. You can ask again anytime.';
          }

          // 1) 若正在等待“候选选择”，优先处理用户选择（回复序号）
          final _ClarifyState? clarify0 = _clarifyState;
          if (!localOnlyResponse &&
              clarify0 != null &&
              clarify0.stage == _ClarifyStage.pickCandidate) {
            _appendAgentLog(
              _isZhLocale()
                  ? '澄清流程：解析候选选择…'
                  : 'Clarification: parsing candidate selection…',
              assistantIndex: assistantIdx,
            );
            final int? pick = _parsePickIndex(text, clarify0.candidates.length);
            if (pick != null) {
              final _ProbeCandidate c = clarify0.candidates[pick - 1];
              _appendAgentLog(
                _isZhLocale()
                    ? '已选择候选 #$pick，定位时间窗…'
                    : 'Picked candidate #$pick, using its time window…',
                assistantIndex: assistantIdx,
              );
              String tzReadable() {
                final Duration off = DateTime.now().timeZoneOffset;
                final int mins = off.inMinutes;
                final String sign = mins >= 0 ? '+' : '-';
                final int abs = mins.abs();
                final String hh = (abs ~/ 60).toString().padLeft(2, '0');
                final String mm = (abs % 60).toString().padLeft(2, '0');
                return 'UTC$sign$hh:$mm';
              }

              intent = IntentResult(
                intent: 'pick_candidate',
                intentSummary: _isZhLocale() ? '根据候选定位' : 'Locate by candidate',
                startMs: c.startMs,
                endMs: c.endMs,
                timezone: tzReadable(),
                apps: const <String>[],
                sqlFill: const <String, dynamic>{},
                skipContext: false,
                contextAction: 'refresh',
              );
              userQuestionForFinal = _composeFinalUserQuestionFromClarify(
                clarify0,
              );
              _clarifyState = null;
            } else {
              // 不是序号：视为“都不是/补充线索”，直接根据新线索再跑一次探测检索
              if (!_isCancelMessage(text)) clarify0.supplements.add(text);
              final String probeQ = _clipOneLine(
                _composeFinalUserQuestionFromClarify(clarify0),
                80,
              );
              _appendAgentLog(
                _isZhLocale()
                    ? '未识别到序号：基于补充线索做一次探测检索…'
                    : 'No pick index: probing candidates from supplemental hints…',
                assistantIndex: assistantIdx,
              );
              final Stopwatch swProbe = Stopwatch()..start();
              final List<_ProbeCandidate> cands = await _probeCandidates(
                query: probeQ.isEmpty ? _clipOneLine(text, 80) : probeQ,
                state: clarify0,
                limit: 6,
              );
              swProbe.stop();
              _appendAgentLog(
                _isZhLocale()
                    ? '探测检索完成：候选 ${cands.length}（${swProbe.elapsedMilliseconds}ms）'
                    : 'Probe done: ${cands.length} candidates (${swProbe.elapsedMilliseconds}ms)',
                assistantIndex: assistantIdx,
              );
              clarify0.candidates
                ..clear()
                ..addAll(cands);
              clarify0.stage = _ClarifyStage.pickCandidate;
              clarify0.lastProbeKind = cands.isNotEmpty
                  ? cands.first.kind
                  : _ProbeKind.none;
              localAssistantText = await _buildProbePickMessage(
                clarify0,
                cands,
              );
              localOnlyResponse = true;
            }
          }

          // 2) 正常意图分析（或澄清补充阶段：将补充信息合并进分析输入）
          if (!localOnlyResponse && intent == null) {
            String analyzeInput = text;
            final _ClarifyState? clarifyAsk = _clarifyState;
            if (clarifyAsk != null && clarifyAsk.stage == _ClarifyStage.ask) {
              if (!_isCancelMessage(text)) clarifyAsk.supplements.add(text);
              userQuestionForFinal = _composeFinalUserQuestionFromClarify(
                clarifyAsk,
              );
              analyzeInput = _composeClarifyIntentInput(clarifyAsk);
            }

            if (!localOnlyResponse) {
              final String preview = _clipOneLine(analyzeInput, 80);
              _appendAgentLog(
                _isZhLocale()
                    ? '调用意图分析模型…${preview.isEmpty ? '' : ' input="' + preview + '"'}'
                    : 'Calling intent model…${preview.isEmpty ? '' : ' input=\"' + preview + '\"'}',
                assistantIndex: assistantIdx,
              );
              final Stopwatch swIntent = Stopwatch()..start();
              intent = await IntentAnalysisService.instance.analyze(
                analyzeInput,
                previous: _lastIntent == null
                    ? null
                    : IntentPrevHint(
                        startMs: _lastIntent!.startMs,
                        endMs: _lastIntent!.endMs,
                        apps: _lastIntent!.apps,
                        summary: _lastIntent!.intentSummary,
                      ),
                previousUserQueries: _extractPreviousUserQueries(maxCount: 3),
              );
              swIntent.stop();
              final String range = intent!.hasValidRange
                  ? '[${intent!.startMs}-${intent!.endMs}]'
                  : '<invalid>';
              final String err = (intent!.errorCode ?? '').trim();
              _appendAgentLog(
                _isZhLocale()
                    ? '意图解析完成：${intent!.intentSummary} range=$range skipContext=${intent!.skipContext ? 1 : 0} contextAction=${intent!.contextAction}${err.isEmpty ? '' : ' error=' + err}（${swIntent.elapsedMilliseconds}ms）'
                    : 'Intent done: ${intent!.intentSummary} range=$range skipContext=${intent!.skipContext ? 1 : 0} contextAction=${intent!.contextAction}${err.isEmpty ? '' : ' error=' + err} (${swIntent.elapsedMilliseconds}ms)',
                assistantIndex: assistantIdx,
              );
            }
          }

          // 3) 缺少有效时间窗：优先在“续问”场景复用上一轮，否则自动补全默认范围继续检索
          if (!localOnlyResponse &&
              intent != null &&
              !intent!.hasValidRange &&
              !_intentAllowsNoTimeRange(intent!)) {
            _appendAgentLog(
              _isZhLocale()
                  ? '未解析到有效时间窗：尝试复用上一轮，否则使用默认范围继续检索…'
                  : 'No valid time range: try reuse previous; otherwise use a default range…',
              assistantIndex: assistantIdx,
            );
            final bool hasPreviousWindow =
                (_lastIntent != null && _lastIntent!.hasValidRange) ||
                (_lastCtxPack != null) ||
                (QueryContextService.instance.lastPack != null);
            final bool canReusePrevious =
                hasPreviousWindow && intent!.skipContext;
            if (canReusePrevious) {
              _appendAgentLog(
                _isZhLocale()
                    ? '尝试复用上一轮时间窗…'
                    : 'Trying to reuse previous time window…',
                assistantIndex: assistantIdx,
              );
              int? fbStart;
              int? fbEnd;
              if (_lastIntent != null && _lastIntent!.hasValidRange) {
                fbStart = _lastIntent!.startMs;
                fbEnd = _lastIntent!.endMs;
              } else if (_lastCtxPack != null) {
                fbStart = _lastCtxPack!.startMs;
                fbEnd = _lastCtxPack!.endMs;
              } else if (QueryContextService.instance.lastPack != null) {
                final p = QueryContextService.instance.lastPack!;
                fbStart = p.startMs;
                fbEnd = p.endMs;
              }
              if (fbStart != null && fbEnd != null && fbEnd >= fbStart) {
                _appendAgentLog(
                  _isZhLocale()
                      ? '已复用上一轮时间窗：[$fbStart-$fbEnd]'
                      : 'Reused previous window: [$fbStart-$fbEnd]',
                  assistantIndex: assistantIdx,
                );
                intent = IntentResult(
                  intent: intent!.intent,
                  intentSummary: intent!.intentSummary.isNotEmpty
                      ? intent!.intentSummary
                      : '复用上一轮时间窗',
                  startMs: fbStart,
                  endMs: fbEnd,
                  timezone: intent!.timezone,
                  apps: intent!.apps,
                  keywords: intent!.keywords,
                  sqlFill: intent!.sqlFill,
                  skipContext: true,
                  errorCode: intent!.errorCode,
                  errorMessage: intent!.errorMessage,
                );
              } else {
                _appendAgentLog(
                  _isZhLocale()
                      ? '复用失败：没有可用的上一轮范围，将使用默认时间范围继续检索'
                      : 'Reuse failed: no previous window; using a default time range',
                  assistantIndex: assistantIdx,
                );
                intent = _applyDefaultTimeRange(intent!);
                _appendAgentLog(
                  _isZhLocale()
                      ? '已自动补全默认时间范围：range=[${intent!.startMs}-${intent!.endMs}]'
                      : 'Auto-filled default time range: range=[${intent!.startMs}-${intent!.endMs}]',
                  assistantIndex: assistantIdx,
                );
              }
            } else {
              _appendAgentLog(
                _isZhLocale()
                    ? '没有可复用的上一轮范围：将使用默认时间范围继续检索'
                    : 'No reusable previous window: using a default time range',
                assistantIndex: assistantIdx,
              );
              intent = _applyDefaultTimeRange(intent!);
              _appendAgentLog(
                _isZhLocale()
                    ? '已自动补全默认时间范围：range=[${intent!.startMs}-${intent!.endMs}]'
                    : 'Auto-filled default time range: range=[${intent!.startMs}-${intent!.endMs}]',
                assistantIndex: assistantIdx,
              );
            }
          }

          // 4) 时间范围过大且缺少线索：不追问，直接继续检索（必要时由模型通过工具分页/扩展范围）
          if (!localOnlyResponse &&
              intent != null &&
              !intent!.userWantsProceed &&
              _isOverlyBroadQuery(
                intent!,
                userQuestionForFinal,
                clarify: _clarifyState,
              )) {
            _appendAgentLog(
              _isZhLocale()
                  ? '时间范围较大：继续直接检索（不再向用户追问）'
                  : 'Large time range: proceeding without clarification',
              assistantIndex: assistantIdx,
            );
          }

          if (localOnlyResponse) {
            _appendAgentLog(
              _isZhLocale()
                  ? '本轮进入本地澄清/候选回复：不进行上下文检索与回答生成'
                  : 'Local clarification/candidates: skip context retrieval and answering',
              assistantIndex: assistantIdx,
            );
            _setState(() {
              final lastIdx = _messages.length - 1;
              final last = _messages[lastIdx];
              _messages[lastIdx] = AIMessage(
                role: 'assistant',
                content: localAssistantText,
                createdAt: last.createdAt,
              );
            });
            _scheduleAutoScroll();
            try {
              final List<AIMessage> toSave = _mergeReasoningForPersistence(
                List<AIMessage>.from(_messages),
              );
              await _enqueueChatHistorySave(toSave);
            } catch (_) {}
            return;
          }

          final IntentResult resolvedIntent = intent!;
          final bool noContext = _intentAllowsNoTimeRange(resolvedIntent);

          // 清理澄清状态，避免污染下一轮
          if (_clarifyState != null &&
              (noContext || resolvedIntent.hasValidRange)) {
            if (noContext) {
              _appendAgentLog(
                _isZhLocale()
                    ? '检测到非检索问题：退出澄清流程'
                    : 'Non-retrieval intent: exiting clarification flow',
                assistantIndex: assistantIdx,
              );
            }
            _clarifyState = null;
          }

          if (noContext) {
            await FlutterLogger.nativeInfo(
              'ChatFlow',
              'phase1 intent ok (no-context, non-stream) intent=${resolvedIntent.intent} summary=${resolvedIntent.intentSummary}',
            );
            _appendAgentLog(
              _isZhLocale()
                  ? '意图已确认：${resolvedIntent.intentSummary}（无需时间窗/上下文检索）'
                  : 'Intent confirmed: ${resolvedIntent.intentSummary} (no time/context needed)',
              assistantIndex: assistantIdx,
            );
            _renameActiveConversationTo(resolvedIntent.intentSummary);
            _setState(() {
              final lastIdx = _messages.length - 1;
              final last = _messages[lastIdx];
              _messages[lastIdx] = AIMessage(
                role: 'assistant',
                content: _isZhLocale()
                    ? '1/4 意图: ${resolvedIntent.intentSummary}\n\n2/4 无需上下文\n\n3/4 生成回答…'
                    : '1/4 Intent: ${resolvedIntent.intentSummary}\n\n2/4 No context needed\n\n3/4 Generating answer…',
                createdAt: last.createdAt,
              );
            });
            _appendAgentLog(
              _isZhLocale() ? '阶段 3/4：生成回答' : 'Phase 3/4: generating answer',
              assistantIndex: assistantIdx,
              bullet: false,
            );
            final Stopwatch swAnswer = Stopwatch()..start();
            final assistant = await _chat.sendMessageWithDisplayOverride(
              text,
              text,
              includeHistory: true,
              // UI persists a post-processed version (e.g. evidence tag rewrites).
              // Prevent service-level tail persistence from overwriting UI history.
              persistHistoryTail: false,
              tools: AIChatService.defaultChatTools(),
              toolChoice: 'auto',
              emitEvent: (evt) {
                if (!mounted) return;
                if (evt.kind != 'reasoning') return;
                _setState(() {
                  _thinkingText += evt.data;
                  _reasoningByIndex[assistantIdx] =
                      (_reasoningByIndex[assistantIdx] ?? '') + evt.data;
                });
                _scheduleAutoScroll();
                _scheduleReasoningPreviewScroll();
              },
            );
            swAnswer.stop();
            _appendAgentLog(
              _isZhLocale()
                  ? '模型已响应（${swAnswer.elapsedMilliseconds}ms）'
                  : 'Model responded (${swAnswer.elapsedMilliseconds}ms)',
              assistantIndex: assistantIdx,
            );
            if (!mounted) return;
            _setState(() {
              final lastIdx = _messages.length - 1;
              _messages[lastIdx] = AIMessage(
                role: 'assistant',
                content: assistant.content,
                createdAt: _messages[lastIdx].createdAt,
              );
            });
            _scheduleAutoScroll();
            try {
              final List<AIMessage> toSave = _mergeReasoningForPersistence(
                List<AIMessage>.from(_messages),
              );
              await _enqueueChatHistorySave(toSave);
            } catch (_) {}
            return;
          }

          await FlutterLogger.nativeInfo(
            'ChatFlow',
            'phase1 intent ok range=[${resolvedIntent.startMs}-${resolvedIntent.endMs}] summary=${resolvedIntent.intentSummary}',
          );
          _appendAgentLog(
            _isZhLocale()
                ? '意图已确认：${resolvedIntent.intentSummary} range=[${resolvedIntent.startMs}-${resolvedIntent.endMs}]'
                : 'Intent confirmed: ${resolvedIntent.intentSummary} range=[${resolvedIntent.startMs}-${resolvedIntent.endMs}]',
            assistantIndex: assistantIdx,
          );
          _renameActiveConversationTo(resolvedIntent.intentSummary);
          final start = DateTime.fromMillisecondsSinceEpoch(
            resolvedIntent.startMs,
          );
          final end = DateTime.fromMillisecondsSinceEpoch(resolvedIntent.endMs);
          String two(int v) => v.toString().padLeft(2, '0');
          final String range =
              '${two(start.hour)}:${two(start.minute)}-${two(end.hour)}:${two(end.minute)}';
          _setState(() {
            final lastIdx = _messages.length - 1;
            final last = _messages[lastIdx];
            _messages[lastIdx] = AIMessage(
              role: 'assistant',
              content:
                  '1/4 意图: ${resolvedIntent.intentSummary}\n时间: $range (${resolvedIntent.timezone})\n\n2/4 查找上下文…',
              createdAt: last.createdAt,
            );
          });

          await FlutterLogger.nativeInfo(
            'ChatFlow',
            'phase2 context(begin, non-stream)',
          );
          _appendAgentLog(
            _isZhLocale() ? '阶段 2/4：查找上下文' : 'Phase 2/4: building context',
            assistantIndex: assistantIdx,
            bullet: false,
          );
          final String ctxAction = (resolvedIntent.contextAction)
              .trim()
              .toLowerCase();
          final bool reuse =
              resolvedIntent.skipContext &&
              ctxAction == 'reuse' &&
              (_lastCtxPack != null ||
                  QueryContextService.instance.lastPack != null);
          _appendAgentLog(
            _isZhLocale()
                ? '复用上一轮上下文：' + (reuse ? '是' : '否')
                : 'Reuse previous context: ' + (reuse ? 'yes' : 'no'),
            assistantIndex: assistantIdx,
          );
          _appendAgentLog(
            _isZhLocale()
                ? '上下文策略：' + ctxAction
                : 'Context action: ' + ctxAction,
            assistantIndex: assistantIdx,
          );
          if (resolvedIntent.skipContext && !reuse) {
            _appendAgentLog(
              _isZhLocale()
                  ? '意图模型建议不复用缓存上下文，将重新检索/翻页以获取更多证据。'
                  : 'Intent model suggests not reusing cached context; will refresh/page for more evidence.',
              assistantIndex: assistantIdx,
            );
          }

          // 不限制上下文事件数量；预加载少量证据图片“文件名/路径”（不预加载像素）。
          // 目的：让模型可以直接引用 filename（而不是臆造），从而在 UI 中稳定渲染图片证据。
          const int maxEvents = 0;
          // 证据图片：预加载文件名/路径（不预加载像素）；段内最多 15 张，总计最多 360 张（并尽量在段落间均匀分配）。
          const int maxImagesTotal = 360;
          const int maxImagesPerEvent = 15;

          // 当范围超过 7 天时，按周预加载（避免提示词过大导致超时/输入上限）。
          final int fullStartMs = resolvedIntent.startMs;
          final int fullEndMs = resolvedIntent.endMs;
          int preloadStartMs = fullStartMs;
          int preloadEndMs = fullEndMs;
          final bool windowed =
              (fullEndMs - fullStartMs) > AIChatService.maxToolTimeSpanMs;
          if (windowed) {
            preloadEndMs = fullEndMs;
            preloadStartMs = fullEndMs - AIChatService.maxToolTimeSpanMs;
            if (preloadStartMs < fullStartMs) preloadStartMs = fullStartMs;
            _appendAgentLog(
              _isZhLocale()
                  ? '时间范围较大：上下文按周分页，本次预加载 7 天窗口 range=[$preloadStartMs-$preloadEndMs]'
                  : 'Large time range: paging context by week; preloading a 7-day window range=[$preloadStartMs-$preloadEndMs]',
              assistantIndex: assistantIdx,
            );
          }

          if (windowed &&
              !reuse &&
              (ctxAction == 'page_prev' || ctxAction == 'page_next')) {
            final QueryContextPack? prevPack =
                (_lastCtxPack ?? QueryContextService.instance.lastPack);
            if (prevPack != null &&
                prevPack.startMs >= fullStartMs &&
                prevPack.endMs <= fullEndMs) {
              if (ctxAction == 'page_prev' && prevPack.startMs > fullStartMs) {
                final int prevEnd0 = prevPack.startMs - 1;
                int nextEndMs = prevEnd0;
                if (nextEndMs < fullStartMs) nextEndMs = fullStartMs;
                int nextStartMs = nextEndMs - AIChatService.maxToolTimeSpanMs;
                if (nextStartMs < fullStartMs) nextStartMs = fullStartMs;
                if (nextStartMs > nextEndMs) nextStartMs = nextEndMs;
                preloadStartMs = nextStartMs;
                preloadEndMs = nextEndMs;
                _appendAgentLog(
                  _isZhLocale()
                      ? '自动翻页：加载上一周上下文 range=[$preloadStartMs-$preloadEndMs]'
                      : 'Auto paging: load previous week range=[$preloadStartMs-$preloadEndMs]',
                  assistantIndex: assistantIdx,
                );
              } else if (ctxAction == 'page_next' &&
                  prevPack.endMs < fullEndMs) {
                final int nextStart0 = prevPack.endMs + 1;
                int nextStartMs = nextStart0;
                if (nextStartMs > fullEndMs) nextStartMs = fullEndMs;
                int nextEndMs = nextStartMs + AIChatService.maxToolTimeSpanMs;
                if (nextEndMs > fullEndMs) nextEndMs = fullEndMs;
                if (nextStartMs > nextEndMs) nextStartMs = nextEndMs;
                preloadStartMs = nextStartMs;
                preloadEndMs = nextEndMs;
                _appendAgentLog(
                  _isZhLocale()
                      ? '自动翻页：加载下一周上下文 range=[$preloadStartMs-$preloadEndMs]'
                      : 'Auto paging: load next week range=[$preloadStartMs-$preloadEndMs]',
                  assistantIndex: assistantIdx,
                );
              } else {
                _appendAgentLog(
                  _isZhLocale()
                      ? '已到达可翻页边界（或窗口无变化），将按当前周继续检索。'
                      : 'Reached paging boundary (or no window change); continue with current window.',
                  assistantIndex: assistantIdx,
                );
              }
            } else {
              _appendAgentLog(
                _isZhLocale()
                    ? '无可用缓存窗口用于翻页，将按当前周继续检索。'
                    : 'No cached window for paging; continue with current window.',
                assistantIndex: assistantIdx,
              );
            }
          }

          final QueryContextPack ctxPack;
          if (reuse) {
            _appendAgentLog(
              _isZhLocale() ? '使用缓存上下文包' : 'Using cached context pack',
              assistantIndex: assistantIdx,
            );
            ctxPack = (_lastCtxPack ?? QueryContextService.instance.lastPack!);
          } else {
            _appendAgentLog(
              _isZhLocale()
                  ? '查询本地数据库并组装上下文…'
                  : 'Querying local DB and assembling context…',
              assistantIndex: assistantIdx,
            );
            final Stopwatch swCtx = Stopwatch()..start();
            ctxPack = await QueryContextService.instance.buildContext(
              startMs: preloadStartMs,
              endMs: preloadEndMs,
              maxEvents: maxEvents,
              maxImagesTotal: maxImagesTotal,
              maxImagesPerEvent: maxImagesPerEvent,
              includeImages: true,
            );
            swCtx.stop();
            _appendAgentLog(
              _isZhLocale()
                  ? '上下文组装完成：events=${ctxPack.events.length}（${swCtx.elapsedMilliseconds}ms）'
                  : 'Context ready: events=${ctxPack.events.length} (${swCtx.elapsedMilliseconds}ms)',
              assistantIndex: assistantIdx,
            );
          }
          await FlutterLogger.nativeInfo(
            'ChatFlow',
            'phase2 context ok events=${ctxPack.events.length} reuse=${reuse ? 1 : 0}',
          );
          // 缓存上下文，便于下一轮复用
          _lastCtxPack = ctxPack;
          try {
            QueryContextService.instance.setLastPack(ctxPack);
          } catch (_) {}
          final List<EvidenceImageAttachment> attachments = (() {
            final Set<String> seen = <String>{};
            final List<EvidenceImageAttachment> out =
                <EvidenceImageAttachment>[];
            for (final ev in ctxPack.events) {
              for (final a in ev.keyImages) {
                if (a.path.isEmpty) continue;
                if (seen.add(a.path)) out.add(a);
              }
            }
            return out;
          })();
          _appendAgentLog(
            _isZhLocale()
                ? '证据图片：预加载文件名/路径 ${attachments.length} 条（不预加载像素；需要看原图像素再用 get_images）'
                : 'Evidence images: preloaded filenames/paths ${attachments.length} (pixels not preloaded; use get_images when you must see pixels)',
            assistantIndex: assistantIdx,
          );
          _setState(() {
            _attachmentsByIndex[assistantIdx] = attachments;
            final lastIdx = _messages.length - 1;
            final last = _messages[lastIdx];
            _messages[lastIdx] = AIMessage(
              role: 'assistant',
              content:
                  '2/4 查找上下文完成' +
                  (reuse ? '（复用上一轮）' : '') +
                  '：事件 ${ctxPack.events.length}' +
                  (windowed ? '（预加载 7 天窗口）' : '') +
                  '\n\n3/4 生成回答…',
              createdAt: last.createdAt,
            );
          });
          _scheduleEvidenceNsfwPreload(attachments.map((a) => a.path));

          final finalQuery = _buildFinalQuestion(
            userQuestionForFinal,
            ctxPack,
            fullStartMs: fullStartMs,
            fullEndMs: fullEndMs,
          );
          final int finalQueryTokens = PromptBudget.approxTokensForText(
            finalQuery,
          );
          await FlutterLogger.nativeDebug(
            'ChatFlow',
            'phase3 finalQueryLen=${finalQuery.length} approxTokens=$finalQueryTokens (non-stream)',
          );
          _appendAgentLog(
            _isZhLocale() ? '阶段 3/4：生成回答' : 'Phase 3/4: generating answer',
            assistantIndex: assistantIdx,
            bullet: false,
          );
          _appendAgentLog(
            _isZhLocale()
                ? '生成最终提示词：len=${finalQuery.length} tokens≈$finalQueryTokens'
                : 'Final prompt: len=${finalQuery.length} tokens≈$finalQueryTokens',
            assistantIndex: assistantIdx,
          );
          // 非流式：拿到回复后直接写入最终答案（证据图片在渲染时按 basename 解析）
          final List<String> extraSystemMessages = <String>[
            _buildNowContextSystemMessage(),
          ];
          final List<Map<String, dynamic>> chatTools =
              AIChatService.defaultChatTools();
          final bool forceToolFirstIfNoToolCalls =
              ctxPack.events.isEmpty ||
              resolvedIntent.intent == 'keyword_lookup' ||
              resolvedIntent.keywords.isNotEmpty;
          _appendAgentLog(
            _isZhLocale()
                ? '调用模型并启用工具：tools=${chatTools.length} tool_choice=auto'
                : 'Calling model with tools: tools=${chatTools.length} tool_choice=auto',
            assistantIndex: assistantIdx,
          );
          final Stopwatch swAnswer = Stopwatch()..start();
          final assistant = await _chat.sendMessageWithDisplayOverride(
            text,
            finalQuery,
            includeHistory: resolvedIntent.skipContext,
            extraSystemMessages: extraSystemMessages,
            // UI persists a post-processed version (e.g. evidence tag rewrites).
            // Prevent service-level tail persistence from overwriting UI history.
            persistHistoryTail: false,
            tools: chatTools,
            toolChoice: 'auto',
            forceToolFirstIfNoToolCalls: forceToolFirstIfNoToolCalls,
            emitEvent: (evt) {
              if (!mounted) return;
              if (evt.kind != 'reasoning') return;
              _setState(() {
                _thinkingText += evt.data;
                _reasoningByIndex[assistantIdx] =
                    (_reasoningByIndex[assistantIdx] ?? '') + evt.data;
              });
              _scheduleAutoScroll();
              _scheduleReasoningPreviewScroll();
            },
          );
          swAnswer.stop();
          _appendAgentLog(
            _isZhLocale()
                ? '模型已响应（${swAnswer.elapsedMilliseconds}ms）'
                : 'Model responded (${swAnswer.elapsedMilliseconds}ms)',
            assistantIndex: assistantIdx,
          );
          final String content = assistant.content;
          if (!mounted) return;
          _setState(() {
            // 用最终答案替换占位
            final lastIdx = _messages.length - 1;
            // 如复用上一轮上下文，则在正文前加一行提示
            final String finalContent =
                (reuse ? '（已复用上一轮上下文）\n\n' : '') + content;
            _messages[lastIdx] = AIMessage(
              role: 'assistant',
              content: finalContent,
              createdAt: _messages[lastIdx].createdAt,
            );
            _inStreaming = false;
          });
          // 覆写历史：合并深度思考内容
          try {
            List<AIMessage> toSave = _mergeReasoningForPersistence(
              List<AIMessage>.from(_messages),
            );
            if (assistantIdx >= 0 &&
                assistantIdx < toSave.length &&
                toSave[assistantIdx].role == 'assistant') {
              final AIMessage m = toSave[assistantIdx];
              String rewritten = await _rewriteNumericEvidenceTagsToFilenames(
                m.content,
                ctxPack: ctxPack,
              );
              if (rewritten != m.content) {
                toSave = List<AIMessage>.from(toSave);
                toSave[assistantIdx] = AIMessage(
                  role: m.role,
                  content: rewritten,
                  createdAt: m.createdAt,
                  reasoningContent: m.reasoningContent,
                  reasoningDuration: m.reasoningDuration,
                  uiThinkingJson: m.uiThinkingJson,
                );
                if (mounted) _setState(() => _messages = toSave);
              }
            }
            await _enqueueChatHistorySave(toSave);
          } catch (_) {}
          // 成功路径：更新"上一轮"缓存
          _lastCtxPack = ctxPack;
          _lastIntent = resolvedIntent;
        } catch (e) {
          try {
            await FlutterLogger.nativeError(
              'ChatFlow',
              'error(non-stream) ' + e.toString(),
            );
          } catch (_) {}
          if (!mounted) return;
          _setState(() {
            final lastIdx = _messages.length - 1;
            _messages[lastIdx] = AIMessage(
              role: 'error',
              content: e.toString(),
            );
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      // 将错误显示为一条"错误"气泡，便于区分样式
      _setState(() {
        _inStreaming = false;
        if (_streamEnabled &&
            _messages.isNotEmpty &&
            _messages.last.role == 'assistant') {
          final newList = List<AIMessage>.from(_messages);
          newList[_messages.length - 1] = AIMessage(
            role: 'error',
            content: e.toString(),
          );
          _messages = newList;
        } else {
          _messages = List<AIMessage>.from(_messages)
            ..add(AIMessage(role: 'error', content: e.toString()));
        }
      });
      _stopDots();
      UINotifier.error(
        context,
        AppLocalizations.of(context).sendFailedWithError(e.toString()),
      );
    } finally {
      if (mounted)
        _setState(() {
          _sending = false;
        });
    }
  }

  String? _thinkingIconKey(IconData? icon) {
    if (icon == null) return null;
    if (icon == Icons.search_outlined) return 'search_outlined';
    if (icon == Icons.manage_search_outlined) return 'manage_search_outlined';
    if (icon == Icons.auto_awesome_outlined) return 'auto_awesome_outlined';
    return null;
  }

  IconData? _thinkingIconFromKey(String? key) {
    final String k = (key ?? '').trim();
    switch (k) {
      case 'search_outlined':
        return Icons.search_outlined;
      case 'manage_search_outlined':
        return Icons.manage_search_outlined;
      case 'auto_awesome_outlined':
        return Icons.auto_awesome_outlined;
    }
    return null;
  }
}
