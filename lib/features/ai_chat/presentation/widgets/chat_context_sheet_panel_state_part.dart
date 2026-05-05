part of 'chat_context_sheet.dart';

extension _ChatContextPanelStatePart on _ChatContextPanelState {
  void _refreshSnapshotOnly() {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    final Future<ChatContextSnapshot> snapFuture = ChatContextService.instance
        .getSnapshot();
    snapFuture
        .then((s) {
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
              if (!mounted) return;
              _panelSetState(() {
                _cachedTrimEvents = events;
              });
            } catch (_) {}
            try {
              final List<PromptUsageEvent> usageEvents =
                  await ChatContextService.instance.listPromptUsageEvents(
                    cid: s.cid,
                    limit: 1,
                  );
              final PromptUsageEvent? latest = usageEvents.isEmpty
                  ? null
                  : usageEvents.first;
              if (!mounted) return;
              _panelSetState(() {
                _cachedLatestUsage = latest;
              });
            } catch (_) {}
          }());
          try {
            final String raw = s.lastPromptBreakdownJson.trim();
            if (raw.isEmpty) return;
            final dynamic decoded = jsonDecode(raw);
            if (decoded is! Map) return;
            final String m = (decoded['model'] ?? '').toString().trim();
            if (m.isEmpty) return;
            if (m == _lastPromptModelForCapOverride) return;
            _lastPromptModelForCapOverride = m;
            unawaited(() async {
              final int? v = await AIModelPromptCapsService.instance
                  .getOverride(m);
              if (!mounted) return;
              // Only rebuild if we actually have a custom override (otherwise
              // the default inference stays the same).
              if (v != null) _panelSetState(() {});
            }());
          } catch (_) {}
        })
        .catchError((_) {});
    snapFuture.whenComplete(() {
      _refreshInFlight = false;
    });
    _panelSetState(() {
      _future = snapFuture;
    });
  }

  void _reload() {
    _refreshSnapshotOnly();
    _loadModelInfo();
  }

  Future<void> _loadMemorySidebarEntryVisibility() async {
    try {
      final bool visible = await AISettingsService.instance
          .getNocturneMemorySidebarEntryVisible();
      if (!mounted) return;
      _panelSetState(() {
        _memoryEntryVisible = visible;
      });
    } catch (_) {}
  }

  Future<void> _onMemoryEntryUnlockTap() async {
    if (_memoryEntryVisible) return;
    final int nextCount = (_memoryEntryUnlockTapCount + 1).clamp(
      0,
      _ChatContextPanelState._memoryEntryUnlockTapTarget,
    );
    final int remaining =
        _ChatContextPanelState._memoryEntryUnlockTapTarget - nextCount;

    if (remaining <= 0) {
      try {
        await AISettingsService.instance.setNocturneMemorySidebarEntryVisible(
          true,
        );
        if (!mounted) return;
        _panelSetState(() {
          _memoryEntryVisible = true;
          _memoryEntryUnlockTapCount = nextCount;
        });
        UINotifier.success(
          context,
          ChatContextSheet._loc(
            context,
            '记忆入口已显示，可在左侧边栏打开',
            'Memory entry is now visible in the sidebar',
          ),
        );
      } catch (e) {
        if (!mounted) return;
        UINotifier.error(
          context,
          ChatContextSheet._loc(
            context,
            '显示记忆入口失败：$e',
            'Failed to reveal memory entry: $e',
          ),
        );
      }
      return;
    }

    _panelSetState(() {
      _memoryEntryUnlockTapCount = nextCount;
    });
    if (remaining <= _ChatContextPanelState._memoryEntryUnlockHintThreshold) {
      UINotifier.info(
        context,
        ChatContextSheet._loc(
          context,
          '再点击 $remaining 次显示记忆入口',
          'Tap $remaining more times to reveal the memory entry',
        ),
      );
    }
  }
}
