part of '../ai_settings_page.dart';

bool _isInternalReasoningProgressLine(String line) {
  final String t = line.trimLeft();
  if (t.isEmpty) return true;
  final String lower = t.toLowerCase();
  return t.startsWith('- ') ||
      t.startsWith('分析查询意图') ||
      t.startsWith('阶段') ||
      t.startsWith('开始处理本次请求') ||
      lower.startsWith('start handling request') ||
      lower.startsWith('phase ') ||
      lower.startsWith('stage ') ||
      lower.startsWith('analyze intent') ||
      lower.startsWith('calling intent model');
}

String _filterReasoningChunkForUi(String raw) {
  if (raw.trim().isEmpty) return '';
  final List<String> kept = <String>[];
  for (final String line in raw.split('\n')) {
    if (_isInternalReasoningProgressLine(line)) continue;
    kept.add(line);
  }
  if (kept.isEmpty) return '';
  String out = kept.join('\n');
  if (raw.endsWith('\n')) out += '\n';
  return out;
}

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

    final int sendEpoch = ++_sendEpoch;
    _activeSendEpoch = sendEpoch;
    final String initialCid = (_activeConversationCid ?? '').trim();
    String requestCid = initialCid;
    try {
      if (requestCid.isEmpty) {
        requestCid = await _settings.getActiveConversationCid();
      }
      requestCid = requestCid.trim();
      _inFlightConversationCid = requestCid.isEmpty ? null : requestCid;
      void setStateIfActive(VoidCallback fn) {
        if (!mounted) return;
        if (_activeSendEpoch != sendEpoch) return;
        _setState(fn);
      }

      // 先本地追加用户消息，提升即时反馈
      setStateIfActive(() {
        _messages = List<AIMessage>.from(_messages)
          ..add(AIMessage(role: 'user', content: text));
      });
      _inputController.clear();
      _scheduleAutoScroll();

      if (_streamEnabled) {
        // 追加一个空的助手消息作为占位，并进入"思考中"可视化状态
        final int assistantIdx = _messages.length;
        final DateTime createdAt = DateTime.now();
        setStateIfActive(() {
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
          _gatewayLogsByIndex.remove(assistantIdx);
          _reasoningDurationByIndex.remove(assistantIdx);

          final _ThinkingBlock first = _ThinkingBlock(createdAt: createdAt);
          if (_showAgentProgressLogs) {
            first.events.add(
              _ThinkingEvent(
                type: _ThinkingEventType.intent,
                title: _isZhLocale() ? '分析查询意图' : 'Analyze intent',
                icon: Icons.search_outlined,
                active: true,
              ),
            );
          }
          _thinkingBlocksByIndex[assistantIdx] = <_ThinkingBlock>[first];
          _contentSegmentsByIndex[assistantIdx] = <String>[];
          _nextContentStartsNewSegmentByIndex[assistantIdx] = true;
        });
        _markInFlightHistoryDirty();
        // Mirror gateway logs to a dedicated file (best-effort) so it's easier
        // to copy/paste full request/response traces when debugging streaming.
        try {
          await _startGatewayLogsFileMirrorIfNeeded(
            assistantIdx,
            conversationCid: requestCid,
            userInput: text,
          );
        } catch (_) {}
        // Persist the placeholder bubble immediately so background tool-loop
        // updates (after a conversation/page switch) can reliably patch the
        // same assistant row by created_at.
        unawaited(() async {
          try {
            final List<AIMessage> merged = _mergeReasoningForPersistence(
              List<AIMessage>.from(_messages),
            );
            await _enqueueChatHistorySave(merged);
          } catch (_) {}
        }());
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
          _appendAgentLog(
            _isZhLocale() ? '阶段 1/4：意图分析' : 'Phase 1/4: intent analysis',
            bullet: false,
          );

          IntentResult? intent;
          String userQuestionForFinal = text;
          bool localOnlyResponse = false;
          String localAssistantText = '';
          AIStreamingSession? session;

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

          // 3) 缺少有效时间窗：不再自动补全默认范围，后续由模型在工具调用中自行决定/调整
          if (!localOnlyResponse &&
              intent != null &&
              !intent!.hasValidRange &&
              !_intentAllowsNoTimeRange(intent!)) {
            _appendAgentLog(
              _isZhLocale()
                  ? '未解析到固定时间窗：不自动补全。后续由模型按需调用工具并自行调整 start_local/end_local。'
                  : 'No fixed time range parsed: skip auto-fill. Let the model call tools and adjust start_local/end_local as needed.',
            );
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
            setStateIfActive(() {
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
            unawaited(_stopGatewayLogsFileMirror(assistantIdx));
          } else {
            final IntentResult resolvedIntent = intent!;

            // 清理澄清状态，避免污染下一轮
            if (_clarifyState != null) {
              _appendAgentLog(
                _isZhLocale()
                    ? '当前不预设固定时间窗：退出澄清流程'
                    : 'No fixed time range preset: exiting clarification flow',
              );
              _clarifyState = null;
            }

            await FlutterLogger.nativeInfo(
              'ChatFlow',
              'phase1 intent ok (no-preset-window) intent=${resolvedIntent.intent} summary=${resolvedIntent.intentSummary}',
            );
            _appendAgentLog(
              _isZhLocale()
                  ? '意图已确认：${resolvedIntent.intentSummary}（不预设时间窗，由模型按需检索）'
                  : 'Intent confirmed: ${resolvedIntent.intentSummary} (no preset time window; model retrieves as needed)',
            );
            if (_showAgentProgressLogs) {
              setStateIfActive(() {
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
            }
            _renameActiveConversationTo(
              resolvedIntent.intentSummary,
              conversationCid: requestCid,
            );
            _appendAgentLog(
              _isZhLocale() ? '阶段 3/4：生成回答' : 'Phase 3/4: generating answer',
              bullet: false,
            );
            _replaceAssistantContentOnNextToken = true; // 首个 token 到来时清空阶段状态
            session = await _chat.sendMessageStreamedV2WithDisplayOverride(
              text,
              text,
              includeHistory: true,
              // Persist the tail at service-level so background completion (after
              // conversation/page switch) still lands in the original CID.
              persistHistoryTail: true,
              tools: AIChatService.defaultChatTools(),
              toolChoice: 'auto',
              conversationCid: requestCid,
              uiAssistantCreatedAtMs: createdAt.millisecondsSinceEpoch,
            );
          }

          if (session != null) {
            // UI might have been detached (conversation/page switch) while we were
            // still preparing the streaming session. Let the service complete in
            // background without attaching stream listeners.
            if (_activeSendEpoch != sendEpoch) {
              unawaited(session!.completed.catchError((_) {}));
              return;
            }
            final Completer<void> streamDone = Completer<void>();
            _streamLoopCompleter = streamDone;

            // Ensure cancel() can stop UI updates immediately (conversation/page switch).
            final sub0 = _streamSubscription;
            if (sub0 != null) {
              try {
                await sub0.cancel();
              } catch (_) {}
              _streamSubscription = null;
            }

            _streamSubscription = session!.stream.listen(
              (AIStreamEvent evt) {
                if (!mounted) return;
                // UI is detached from this in-flight request; ignore further deltas.
                if (_activeSendEpoch != sendEpoch) return;

                final int? idx = _currentAssistantIndex;

                // UI 事件（工具调用等）：不作为正文输出，单独驱动“思考块”渲染。
                if (evt.kind == 'ui') {
                  if (idx != null) {
                    final Map<String, dynamic>? payload = _tryParseJsonMap(
                      evt.data,
                    );
                    if (payload != null) {
                      final String t =
                          (payload['type'] as String?)?.trim() ?? '';
                      if (t == 'gateway_log') {
                        _handleGatewayLogUiEvent(idx, payload);
                        // Debug logs are out-of-band; do not drive scrolling/persistence.
                        return;
                      } else {
                        _setState(() => _handleAiUiEvent(idx, payload));
                      }
                      _scheduleAutoScroll();
                      _markInFlightHistoryDirty();
                    }
                  }
                  return;
                }

                // 将模型返回的 reasoning / 过程性文本展示到“思考过程”面板，避免长时间无正文时看起来卡住。
                if (evt.kind == 'reasoning') {
                  final String reasoningDelta = _showAgentProgressLogs
                      ? evt.data
                      : _filterReasoningChunkForUi(evt.data);
                  if (idx != null && reasoningDelta.trim().isNotEmpty) {
                    _setState(() {
                      _thinkingText += reasoningDelta;
                      _reasoningByIndex[idx] =
                          (_reasoningByIndex[idx] ?? '') + reasoningDelta;
                    });
                    _scheduleAutoScroll();
                    _scheduleReasoningPreviewScroll();
                    _markInFlightHistoryDirty();
                  }
                  return;
                }
                // 正文增量（首 token 到来时先清空阶段状态，再开始写入最终答案）
                _setState(() {
                  final int? currentIdx = _currentAssistantIndex;
                  final int fallbackIdx = _messages.length - 1;
                  final int targetIdx =
                      (currentIdx != null &&
                          currentIdx >= 0 &&
                          currentIdx < _messages.length)
                      ? currentIdx
                      : fallbackIdx;
                  if (targetIdx < 0 || targetIdx >= _messages.length) {
                    return;
                  }
                  final AIMessage target = _messages[targetIdx];
                  if (target.role == 'assistant') {
                    final String base = _replaceAssistantContentOnNextToken
                        ? ''
                        : target.content;
                    final String incoming = evt.data;
                    final updated = AIMessage(
                      role: 'assistant',
                      content: base + incoming,
                      createdAt: target.createdAt, // 保留初始创建时间以准确计算思考耗时
                    );
                    final newList = List<AIMessage>.from(_messages);
                    newList[targetIdx] = updated;
                    _messages = newList;
                    _replaceAssistantContentOnNextToken = false;

                    if (currentIdx != null && incoming.isNotEmpty) {
                      _finishActiveThinkingBlock(currentIdx);
                      _appendContentChunk(currentIdx, incoming);
                    }
                  }
                });
                _scheduleAutoScroll();
                _markInFlightHistoryDirty();
              },
              onError: (Object error, StackTrace st) {
                // If the UI has been detached, do not surface errors here.
                if (_activeSendEpoch != sendEpoch) {
                  if (!streamDone.isCompleted) streamDone.complete();
                  return;
                }
                if (!streamDone.isCompleted) {
                  streamDone.completeError(error, st);
                }
              },
              onDone: () {
                if (!streamDone.isCompleted) streamDone.complete();
              },
            );

            try {
              await streamDone.future;
            } finally {
              if (_streamLoopCompleter == streamDone) {
                _streamLoopCompleter = null;
              }
              final sub1 = _streamSubscription;
              if (sub1 != null) {
                try {
                  await sub1.cancel();
                } catch (_) {}
              }
              _streamSubscription = null;
            }

            // If the UI has been detached (conversation/page switch), do not touch
            // state/persistence further; let the service complete in background.
            if (!mounted || _activeSendEpoch != sendEpoch) {
              unawaited(_stopGatewayLogsFileMirror(assistantIdx));
              unawaited(session!.completed.catchError((_) {}));
              return;
            }

            final AIMessage completed = await session!.completed;
            // Add an explicit UI summary line to logs (helps diagnose cases where
            // providers only return `reasoning_content` and leave `content` empty).
            try {
              _appendGatewayLogLine(
                assistantIdx,
                '[UI] completed contentLen=${completed.content.length} reasoningLen=${(completed.reasoningContent ?? '').length}',
              );
            } catch (_) {}

            // Safety net: some providers/models only emit Responses/ChatCompletions "done" events
            // (or we may filter out empty deltas). If we never saw any content token, replace the
            // phase placeholder with the final completed content so the UI doesn't look "stuck".
            if (_replaceAssistantContentOnNextToken &&
                completed.content.trim().isNotEmpty) {
              _setState(() {
                final int? currentIdx = _currentAssistantIndex;
                final int fallbackIdx = _messages.length - 1;
                final int targetIdx =
                    (currentIdx != null &&
                        currentIdx >= 0 &&
                        currentIdx < _messages.length)
                    ? currentIdx
                    : fallbackIdx;
                if (targetIdx < 0 || targetIdx >= _messages.length) {
                  return;
                }
                final AIMessage target = _messages[targetIdx];
                if (target.role != 'assistant') return;

                final updated = AIMessage(
                  role: 'assistant',
                  content: completed.content,
                  createdAt: target.createdAt,
                  reasoningContent: target.reasoningContent,
                  reasoningDuration: target.reasoningDuration,
                  uiThinkingJson: target.uiThinkingJson,
                );
                final newList = List<AIMessage>.from(_messages);
                newList[targetIdx] = updated;
                _messages = newList;
                _replaceAssistantContentOnNextToken = false;

                if (currentIdx != null && completed.content.isNotEmpty) {
                  _finishActiveThinkingBlock(currentIdx);
                  _appendContentChunk(currentIdx, completed.content);
                }
              });
              _scheduleAutoScroll();
              _markInFlightHistoryDirty();
            }

            // Stream providers may emit overlapping terminal events; ensure the final
            // assistant bubble always converges to completed.content exactly.
            if (completed.content.trim().isNotEmpty) {
              _setState(() {
                final int? currentIdx = _currentAssistantIndex;
                final int fallbackIdx = _messages.length - 1;
                final int targetIdx =
                    (currentIdx != null &&
                        currentIdx >= 0 &&
                        currentIdx < _messages.length)
                    ? currentIdx
                    : fallbackIdx;
                if (targetIdx < 0 || targetIdx >= _messages.length) {
                  return;
                }
                final AIMessage target = _messages[targetIdx];
                if (target.role != 'assistant') return;
                if (target.content == completed.content) return;

                final updated = AIMessage(
                  role: 'assistant',
                  content: completed.content,
                  createdAt: target.createdAt,
                  reasoningContent: target.reasoningContent,
                  reasoningDuration: target.reasoningDuration,
                  uiThinkingJson: target.uiThinkingJson,
                );
                final newList = List<AIMessage>.from(_messages);
                newList[targetIdx] = updated;
                _messages = newList;

                if (currentIdx != null) {
                  _contentSegmentsByIndex[currentIdx] = <String>[
                    completed.content,
                  ];
                  _nextContentStartsNewSegmentByIndex[currentIdx] = false;
                }
              });
              _scheduleAutoScroll();
              _markInFlightHistoryDirty();
            }
            // 成功路径：更新"上一轮"缓存
            if (intent != null) {
              _lastIntent = intent;
            }
            unawaited(_stopGatewayLogsFileMirror(assistantIdx));
          }
        } catch (e) {
          try {
            await FlutterLogger.nativeError(
              'ChatFlow',
              'error ' + e.toString(),
            );
          } catch (_) {}
          unawaited(_stopGatewayLogsFileMirror(assistantIdx));
          if (!mounted) return;
          // UI might have been detached (conversation/page switch). Do not touch
          // state; let the service complete/persist in background.
          if (_activeSendEpoch != sendEpoch) rethrow;
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
          setStateIfActive(() {
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
        // UI might have been detached by a conversation/page switch while the
        // request continues in background.
        if (_activeSendEpoch != sendEpoch) return;
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
            await _enqueueChatHistorySaveByCid(requestCid, merged);
          } catch (_) {
            try {
              final List<AIMessage> toSave = _mergeReasoningForPersistence(
                List<AIMessage>.from(_messages),
              );
              await _enqueueChatHistorySaveByCid(requestCid, toSave);
            } catch (_) {}
          }
        }
      } else {
        // 非流式：仍按阶段流程，最后一次性替换为最终答案
        final int assistantIdx = _messages.length;
        setStateIfActive(() {
          _thinkingText = '';
          _reasoningByIndex[assistantIdx] = '';
          _reasoningDurationByIndex.remove(assistantIdx);
          _messages = List<AIMessage>.from(_messages)
            ..add(
              AIMessage(
                role: 'assistant',
                content: '',
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

          // 3) 缺少有效时间窗：不再自动补全默认范围，后续由模型在工具调用中自行决定/调整
          if (!localOnlyResponse &&
              intent != null &&
              !intent!.hasValidRange &&
              !_intentAllowsNoTimeRange(intent!)) {
            _appendAgentLog(
              _isZhLocale()
                  ? '未解析到固定时间窗：不自动补全。后续由模型按需调用工具并自行调整 start_local/end_local。'
                  : 'No fixed time range parsed: skip auto-fill. Let the model call tools and adjust start_local/end_local as needed.',
              assistantIndex: assistantIdx,
            );
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
            if (_activeSendEpoch != sendEpoch) return;
            _appendAgentLog(
              _isZhLocale()
                  ? '本轮进入本地澄清/候选回复：不进行上下文检索与回答生成'
                  : 'Local clarification/candidates: skip context retrieval and answering',
              assistantIndex: assistantIdx,
            );
            setStateIfActive(() {
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
              await _enqueueChatHistorySaveByCid(requestCid, toSave);
            } catch (_) {}
            return;
          }

          final IntentResult resolvedIntent = intent!;

          // 清理澄清状态，避免污染下一轮
          if (_clarifyState != null) {
            _appendAgentLog(
              _isZhLocale()
                  ? '当前不预设固定时间窗：退出澄清流程'
                  : 'No fixed time range preset: exiting clarification flow',
              assistantIndex: assistantIdx,
            );
            _clarifyState = null;
          }

          await FlutterLogger.nativeInfo(
            'ChatFlow',
            'phase1 intent ok (no-preset-window, non-stream) intent=${resolvedIntent.intent} summary=${resolvedIntent.intentSummary}',
          );
          _appendAgentLog(
            _isZhLocale()
                ? '意图已确认：${resolvedIntent.intentSummary}（不预设时间窗，由模型按需检索）'
                : 'Intent confirmed: ${resolvedIntent.intentSummary} (no preset time window; model retrieves as needed)',
            assistantIndex: assistantIdx,
          );
          _renameActiveConversationTo(
            resolvedIntent.intentSummary,
            conversationCid: requestCid,
          );
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
            // Persist tail at service-level so leaving/switching won't lose the result.
            persistHistoryTail: true,
            tools: AIChatService.defaultChatTools(),
            toolChoice: 'auto',
            conversationCid: requestCid,
            emitEvent: (evt) {
              if (!mounted) return;
              if (_activeSendEpoch != sendEpoch) return;
              if (evt.kind != 'reasoning') return;
              final String reasoningDelta = _showAgentProgressLogs
                  ? evt.data
                  : _filterReasoningChunkForUi(evt.data);
              if (reasoningDelta.trim().isEmpty) return;
              setStateIfActive(() {
                _thinkingText += reasoningDelta;
                _reasoningByIndex[assistantIdx] =
                    (_reasoningByIndex[assistantIdx] ?? '') + reasoningDelta;
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
          if (!mounted || _activeSendEpoch != sendEpoch) return;
          setStateIfActive(() {
            final lastIdx = _messages.length - 1;
            _messages[lastIdx] = AIMessage(
              role: 'assistant',
              content: assistant.content,
              createdAt: _messages[lastIdx].createdAt,
            );
          });
          _scheduleAutoScroll();
          _lastIntent = resolvedIntent;
          try {
            final List<AIMessage> toSave = _mergeReasoningForPersistence(
              List<AIMessage>.from(_messages),
            );
            await _enqueueChatHistorySaveByCid(requestCid, toSave);
          } catch (_) {}
          return;
        } catch (e) {
          try {
            await FlutterLogger.nativeError(
              'ChatFlow',
              'error(non-stream) ' + e.toString(),
            );
          } catch (_) {}
          if (!mounted || _activeSendEpoch != sendEpoch) return;
          setStateIfActive(() {
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
      // This send has been detached (conversation/page switch). Ignore errors here.
      if (_activeSendEpoch != sendEpoch) return;
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
      final bool stillActive = (_activeSendEpoch == sendEpoch);
      if (stillActive) {
        _activeSendEpoch = 0;
        _inFlightConversationCid = null;
        _cancelStreamUiSubscription();
      }
      if (mounted && stillActive) {
        _setState(() {
          _sending = false;
        });
        if (_pendingChatReload) {
          _pendingChatReload = false;
          unawaited(() async {
            await _loadChatContextSelection();
            await _loadAll();
          }());
        }
      } else if (stillActive) {
        _pendingChatReload = false;
      }
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
