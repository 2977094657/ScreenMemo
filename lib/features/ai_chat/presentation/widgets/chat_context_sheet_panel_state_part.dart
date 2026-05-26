part of 'chat_context_sheet.dart';

extension _ChatContextPanelStatePart on _ChatContextPanelState {
  void _refreshSnapshotOnly() {
    if (_refreshInFlight) {
      _logAiChatPerf('ContextPanel.refresh.skip', detail: 'inFlight');
      return;
    }
    final Stopwatch sw = Stopwatch()..start();
    _logAiChatPerf('ContextPanel.refresh.start');
    _refreshInFlight = true;
    final Future<ChatContextSnapshot> snapFuture = ChatContextService.instance
        .getSnapshot();
    snapFuture
        .then((s) {
          _logAiChatPerf(
            'ContextPanel.snapshot.done',
            stopwatch: sw,
            detail:
                'cidHash=${s.cid.hashCode} messages=${s.fullMessageCount} tokens=${s.lastPromptTokens}',
          );
          _cachedSnapshot = s;
          unawaited(() async {
            try {
              final List<ChatContextEvent> events = await ChatContextService
                  .instance
                  .listRecentContextEvents(
                    cid: s.cid,
                    type: 'prompt_trim',
                    limit: _ChatContextPanelState._trimEventsDefaultLimit,
                  );
              _logAiChatPerf(
                'ContextPanel.trimEvents.done',
                stopwatch: sw,
                detail: 'events=${events.length}',
              );
              if (!mounted) return;
              _panelSetState(() {
                _cachedTrimEvents = events;
              });
            } catch (e) {
              _logAiChatPerf(
                'ContextPanel.trimEvents.error',
                stopwatch: sw,
                detail: 'err=$e',
              );
            }
            try {
              final List<PromptUsageEvent> usageEvents =
                  await ChatContextService.instance.listPromptUsageEvents(
                    cid: s.cid,
                    limit: 1,
                  );
              final PromptUsageEvent? latest = usageEvents.isEmpty
                  ? null
                  : usageEvents.first;
              _logAiChatPerf(
                'ContextPanel.usageEvents.done',
                stopwatch: sw,
                detail: 'events=${usageEvents.length}',
              );
              if (!mounted) return;
              _panelSetState(() {
                _cachedLatestUsage = latest;
              });
            } catch (e) {
              _logAiChatPerf(
                'ContextPanel.usageEvents.error',
                stopwatch: sw,
                detail: 'err=$e',
              );
            }
            try {
              final CodexStyleTokenUsageInfo info = await ChatContextService
                  .instance
                  .getCodexStyleTokenUsageInfo(
                    cid: s.cid,
                    modelContextWindow: _activeModelContextTokens,
                  );
              _logAiChatPerf(
                'ContextPanel.codexUsage.done',
                stopwatch: sw,
                detail:
                    'cap=${_activeModelContextTokens ?? -1} tokens=${info.lastTokenUsage.tokensInContextWindow}',
              );
              if (!mounted) return;
              _panelSetState(() {
                _cachedCodexUsageInfo = info;
              });
            } catch (e) {
              _logAiChatPerf(
                'ContextPanel.codexUsage.error',
                stopwatch: sw,
                detail: 'err=$e',
              );
            }
          }());
          try {
            final String raw = s.lastPromptBreakdownJson.trim();
            if (raw.isEmpty) {
              _logAiChatPerf(
                'ContextPanel.breakdown.skip',
                stopwatch: sw,
                detail: 'empty',
              );
              return;
            }
            final dynamic decoded = jsonDecode(raw);
            if (decoded is! Map) {
              _logAiChatPerf(
                'ContextPanel.breakdown.skip',
                stopwatch: sw,
                detail: 'notMap rawLen=${raw.length}',
              );
              return;
            }
            final String m = (decoded['model'] ?? '').toString().trim();
            if (m.isEmpty) {
              _logAiChatPerf(
                'ContextPanel.breakdown.skip',
                stopwatch: sw,
                detail: 'emptyModel rawLen=${raw.length}',
              );
              return;
            }
            if (m == _lastPromptModelForCapOverride) {
              _logAiChatPerf(
                'ContextPanel.capOverride.skip',
                stopwatch: sw,
                detail: 'model=$m cached',
              );
              return;
            }
            _lastPromptModelForCapOverride = m;
            unawaited(() async {
              final Stopwatch overrideSw = Stopwatch()..start();
              final int? v = await AIModelPromptCapsService.instance
                  .getOverride(m);
              _logAiChatPerf(
                'ContextPanel.capOverride.done',
                stopwatch: overrideSw,
                detail: 'model=$m override=${v ?? -1}',
              );
              if (!mounted) return;
              // Only rebuild if we actually have a custom override (otherwise
              // the default inference stays the same).
              if (v != null) _panelSetState(() {});
            }());
          } catch (e) {
            _logAiChatPerf(
              'ContextPanel.breakdown.error',
              stopwatch: sw,
              detail: 'err=$e',
            );
          }
        })
        .catchError((e) {
          _logAiChatPerf(
            'ContextPanel.snapshot.error',
            stopwatch: sw,
            detail: 'err=$e',
          );
        });
    snapFuture.whenComplete(() {
      _refreshInFlight = false;
      _logAiChatPerf('ContextPanel.refresh.done', stopwatch: sw);
    });
    _panelSetState(() {
      _future = snapFuture;
    });
    _logAiChatPerf('ContextPanel.future.setState.done', stopwatch: sw);
  }

  void _reload() {
    _refreshSnapshotOnly();
    _loadModelInfo();
  }
}
