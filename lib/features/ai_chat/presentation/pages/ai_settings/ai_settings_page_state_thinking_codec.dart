part of '../ai_settings_page.dart';

extension _AISettingsPageStateThinkingCodecExt on _AISettingsPageState {
  List<int> _decodeSegmentLengthsFromUiJson(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return const <int>[];

    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? 0;
      return 0;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(t);
    } catch (_) {
      return const <int>[];
    }
    if (decoded is! Map) return const <int>[];
    final Map<String, dynamic> obj = Map<String, dynamic>.from(decoded as Map);
    final int ver = asInt(obj['v']);
    if (ver != 2) return const <int>[];

    final dynamic lens0 = obj['seg_lens'];
    if (lens0 is! List) return const <int>[];
    final List<int> lens = <int>[];
    for (final dynamic it in lens0) {
      final int n = asInt(it);
      if (n > 0) lens.add(n);
    }
    return lens;
  }

  String? _encodeThinkingBlocksForIndex(int assistantIdx) {
    final List<_ThinkingBlock>? blocks0 = _thinkingBlocksByIndex[assistantIdx];
    if (blocks0 == null || blocks0.isEmpty) return null;

    bool hasAnyEvents = false;
    for (final b in blocks0) {
      if (b.events.isNotEmpty) {
        hasAnyEvents = true;
        break;
      }
    }
    if (!hasAnyEvents) return null;

    final List<Map<String, dynamic>> blocks = <Map<String, dynamic>>[];
    for (final b in blocks0) {
      final bool isLoading = b.finishedAt == null;
      final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
      for (final e in b.events) {
        final String iconKey = (_thinkingIconKey(e.icon) ?? '').trim();
        final List<Map<String, dynamic>> tools = <Map<String, dynamic>>[];
        for (final c in e.tools) {
          final Map<String, dynamic> chip = <String, dynamic>{
            'call_id': c.callId,
            'tool_name': c.toolName,
            'label': c.label,
            if (c.appNames.isNotEmpty) 'app_names': c.appNames,
            if (c.appPackageNames.isNotEmpty)
              'app_package_names': c.appPackageNames,
            if (isLoading) 'active': c.active,
            if (c.resultSummary != null && c.resultSummary!.trim().isNotEmpty)
              'result_summary': c.resultSummary,
          };
          tools.add(chip);
        }

        final Map<String, dynamic> ev = <String, dynamic>{
          'type': e.type.name,
          'title': e.title,
          if (e.subtitle != null && e.subtitle!.trim().isNotEmpty)
            'subtitle': e.subtitle,
          if (iconKey.isNotEmpty) 'icon': iconKey,
          if (isLoading && e.active) 'active': true,
          if (tools.isNotEmpty) 'tools': tools,
        };
        events.add(ev);
      }

      blocks.add(<String, dynamic>{
        'created_at': b.createdAt.millisecondsSinceEpoch,
        if (b.finishedAt != null)
          'finished_at': b.finishedAt!.millisecondsSinceEpoch,
        if (events.isNotEmpty) 'events': events,
      });
    }

    // Persist content segment boundaries so we can restore the same
    // 思考块/正文 interleaving order after reload/copy.
    List<int> segLens = <int>[];
    final List<String>? segs0 = _contentSegmentsByIndex[assistantIdx];
    if (segs0 != null && segs0.length > 1) {
      segLens = <int>[for (final s in segs0) s.length];
    } else if (assistantIdx >= 0 && assistantIdx < _messages.length) {
      final String? existingUi = _messages[assistantIdx].uiThinkingJson;
      if (existingUi != null && existingUi.trim().isNotEmpty) {
        final List<int> fromUi = _decodeSegmentLengthsFromUiJson(existingUi);
        if (fromUi.length > 1) segLens = fromUi;
      }
    }

    return jsonEncode(<String, dynamic>{
      'v': 2,
      'blocks': blocks,
      if (segLens.length > 1) 'seg_lens': segLens,
    });
  }

  List<_ThinkingBlock> _decodeThinkingBlocks(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return const <_ThinkingBlock>[];

    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? 0;
      return 0;
    }

    bool asBool(dynamic v) {
      if (v is bool) return v;
      if (v is int) return v != 0;
      if (v is String) {
        final String s = v.trim().toLowerCase();
        return s == '1' || s == 'true' || s == 'yes';
      }
      return false;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(t);
    } catch (_) {
      return const <_ThinkingBlock>[];
    }
    if (decoded is! Map) return const <_ThinkingBlock>[];
    final Map<String, dynamic> obj = Map<String, dynamic>.from(decoded as Map);
    final int ver = asInt(obj['v']);
    if (ver != 1 && ver != 2) return const <_ThinkingBlock>[];

    final List<dynamic> blocks0 = (obj['blocks'] is List)
        ? List<dynamic>.from(obj['blocks'] as List)
        : const <dynamic>[];
    final List<_ThinkingBlock> out = <_ThinkingBlock>[];
    for (final b0 in blocks0) {
      if (b0 is! Map) continue;
      final Map<String, dynamic> b = Map<String, dynamic>.from(b0 as Map);
      final int createdAtMs = asInt(b['created_at']);
      if (createdAtMs <= 0) continue;
      final _ThinkingBlock block = _ThinkingBlock(
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      );
      final int finishedAtMs = asInt(b['finished_at']);
      if (finishedAtMs > 0) {
        block.finishedAt = DateTime.fromMillisecondsSinceEpoch(finishedAtMs);
      }

      final List<dynamic> events0 = (b['events'] is List)
          ? List<dynamic>.from(b['events'] as List)
          : const <dynamic>[];
      for (final e0 in events0) {
        if (e0 is! Map) continue;
        final Map<String, dynamic> eMap = Map<String, dynamic>.from(e0 as Map);
        final String typeStr = (eMap['type'] ?? '').toString().trim();
        final _ThinkingEventType type = switch (typeStr) {
          'intent' => _ThinkingEventType.intent,
          'tools' => _ThinkingEventType.tools,
          _ => _ThinkingEventType.status,
        };

        final String title = (eMap['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final String subtitleRaw = (eMap['subtitle'] ?? '').toString().trim();
        final String iconKey = (eMap['icon'] ?? '').toString().trim();

        final List<dynamic> tools0 = (eMap['tools'] is List)
            ? List<dynamic>.from(eMap['tools'] as List)
            : const <dynamic>[];
        final List<_ThinkingToolChip> tools = <_ThinkingToolChip>[];
        for (final c0 in tools0) {
          if (c0 is! Map) continue;
          final Map<String, dynamic> cm = Map<String, dynamic>.from(c0 as Map);
          final String callId = (cm['call_id'] ?? '').toString().trim();
          final String toolName = (cm['tool_name'] ?? '').toString().trim();
          if (callId.isEmpty || toolName.isEmpty) continue;

          List<String> parseStringList(dynamic raw) {
            if (raw is List) {
              return raw
                  .map((e) => e?.toString().trim() ?? '')
                  .where((e) => e.isNotEmpty)
                  .toSet()
                  .toList(growable: false);
            }
            if (raw is String) {
              final String s = raw.trim();
              return s.isEmpty ? const <String>[] : <String>[s];
            }
            return const <String>[];
          }

          final String labelRaw = (cm['label'] ?? '').toString().trim();
          final String summaryRaw = (cm['result_summary'] ?? '')
              .toString()
              .trim();
          final List<String> appNames = parseStringList(cm['app_names']);
          final List<String> appPkgs = parseStringList(cm['app_package_names']);
          tools.add(
            _ThinkingToolChip(
              callId: callId,
              toolName: toolName,
              label: labelRaw.isEmpty ? toolName : labelRaw,
              appNames: appNames,
              appPackageNames: appPkgs,
              active: asBool(cm['active']),
              resultSummary: summaryRaw.isEmpty ? null : summaryRaw,
            ),
          );
        }

        block.events.add(
          _ThinkingEvent(
            type: type,
            title: title,
            subtitle: subtitleRaw.isEmpty ? null : subtitleRaw,
            icon: _thinkingIconFromKey(iconKey),
            active: asBool(eMap['active']),
            tools: tools,
          ),
        );
      }

      if (block.events.isNotEmpty || block.finishedAt != null) {
        out.add(block);
      }
    }
    return out;
  }

  List<AIMessage> _mergeReasoningForPersistence(List<AIMessage> input) {
    final List<AIMessage> out = List<AIMessage>.from(input);
    for (int i = 0; i < out.length; i++) {
      final AIMessage m = out[i];
      if (m.role == 'user' || m.role == 'system') continue;
      final String? r = _reasoningByIndex[i];
      final Duration? d = _reasoningDurationByIndex[i];
      final String? uiJson = _encodeThinkingBlocksForIndex(i);
      final String? existingR = m.reasoningContent;
      final Duration? existingD = m.reasoningDuration;
      final String? existingUi = m.uiThinkingJson;
      final String? mergedR = (r != null && r.trim().isNotEmpty)
          ? r
          : existingR;
      final Duration? mergedD = d ?? existingD;
      final String? mergedUi = (uiJson != null && uiJson.trim().isNotEmpty)
          ? uiJson
          : existingUi;
      if (mergedR == existingR &&
          mergedD == existingD &&
          mergedUi == existingUi) {
        continue;
      }
      out[i] = AIMessage(
        role: m.role,
        content: m.content,
        createdAt: m.createdAt,
        reasoningContent: mergedR,
        reasoningDuration: mergedD,
        uiThinkingJson: mergedUi,
      );
    }
    return out;
  }

  String _basenameFromPath(String path) {
    final int idx1 = path.lastIndexOf('/');
    final int idx2 = path.lastIndexOf('\\');
    final int i = idx1 > idx2 ? idx1 : idx2;
    return i >= 0 ? path.substring(i + 1) : path;
  }

  String _evidenceMsgKey(AIMessage m) {
    // createdAt 足够稳定；叠加 role/content hash 避免同秒多条消息冲突
    return '${m.createdAt.millisecondsSinceEpoch}|${m.role}|${m.content.hashCode}';
  }

  void _scheduleEvidenceRebuild() {
    if (_evidenceRebuildScheduled) return;
    _evidenceRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evidenceRebuildScheduled = false;
      if (!mounted) return;
      _setState(() {});
    });
  }

  void _scheduleEvidenceNsfwPreload(Iterable<String> filePaths) {
    final List<String> paths = filePaths
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (paths.isEmpty) return;

    final List<String> toLoad = <String>[];
    for (final p in paths) {
      if (_evidenceNsfwRequestedPaths.add(p)) {
        toLoad.add(p);
      }
    }
    if (toLoad.isEmpty) return;

    // Serialize to avoid DB storms while scrolling/rebuilding.
    final Future<void>? prev = _evidenceNsfwPreloadFuture;
    final Future<void> next = () async {
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      try {
        await _preloadEvidenceNsfwNow(toLoad);
      } catch (_) {}
    }();
    _evidenceNsfwPreloadFuture = next;
    unawaited(next);
  }

  Future<void> _preloadEvidenceNsfwNow(List<String> filePaths) async {
    if (filePaths.isEmpty) return;

    final List<ScreenshotRecord> found = <ScreenshotRecord>[];
    for (final p in filePaths) {
      if (_evidenceScreenshotByPath.containsKey(p)) continue;
      try {
        final ScreenshotRecord? s = await ScreenshotDatabase.instance
            .getScreenshotByPath(p);
        _evidenceScreenshotByPath[p] = s;
        if (s != null) found.add(s);
      } catch (_) {
        _evidenceScreenshotByPath[p] = null;
      }
    }

    // Best-effort preloads. Missing caches are treated as "not NSFW".
    try {
      await NsfwPreferenceService.instance.ensureRulesLoaded();
    } catch (_) {}
    try {
      await NsfwPreferenceService.instance.preloadAiNsfwFlags(
        filePaths: filePaths,
      );
    } catch (_) {}
    try {
      await NsfwPreferenceService.instance.preloadSegmentNsfwFlags(
        filePaths: filePaths,
      );
    } catch (_) {}

    final Map<String, Set<int>> idsByApp = <String, Set<int>>{};
    for (final s in found) {
      final int? id = s.id;
      if (id == null) continue;
      idsByApp.putIfAbsent(s.appPackageName, () => <int>{}).add(id);
    }
    for (final e in idsByApp.entries) {
      try {
        await NsfwPreferenceService.instance.preloadManualFlags(
          appPackageName: e.key,
          screenshotIds: e.value.toList(growable: false),
        );
      } catch (_) {}
    }

    if (!mounted) return;
    _scheduleEvidenceRebuild();
  }

  Future<Map<String, String>> _resolveEvidencePathsCached({
    required String msgKey,
    required Set<String> missingNames,
  }) {
    if (missingNames.isEmpty) return Future.value(const <String, String>{});
    final List<String> sorted = missingNames.toList()..sort();
    final String lookupKey = '$msgKey|${sorted.join("|")}';
    return _evidenceResolveFutures.putIfAbsent(lookupKey, () async {
      final Stopwatch sw = Stopwatch()..start();
      _uiPerf.log(
        'evidence.resolve.start',
        detail:
            'lookup=${lookupKey.hashCode} missing=${missingNames.length} names=${sorted.take(3).join(",")}',
      );
      Map<String, String> map = const <String, String>{};
      try {
        map = await ScreenshotDatabase.instance.findPathsByBasenames(
          missingNames,
        );
      } catch (_) {
        map = const <String, String>{};
      }
      _uiPerf.log(
        'evidence.resolve.db.done',
        detail:
            'lookup=${lookupKey.hashCode} ms=${sw.elapsedMilliseconds} found=${map.length}',
      );
      if (!mounted) return map;
      if (map.isNotEmpty) {
        _scheduleEvidenceNsfwPreload(map.values);
        final Map<String, String> existing =
            _evidenceResolvedByMsgKey[msgKey] ?? const <String, String>{};
        bool changed = false;
        for (final e in map.entries) {
          if (existing[e.key] != e.value) {
            changed = true;
            break;
          }
        }
        if (changed) {
          _evidenceResolvedByMsgKey[msgKey] = <String, String>{
            ...existing,
            ...map,
          };
          _uiPerf.log(
            'evidence.cache.update',
            detail:
                'lookup=${lookupKey.hashCode} msg=${msgKey.hashCode} merged=${existing.length + map.length}',
          );
          // 关键：证据路径缓存更新后，主动触发一次页面重建；
          // 否则在“退出→进入”场景里可能要等到 Drawer/键盘等外部 UI 事件触发 rebuild 才会显示图片。
          _scheduleEvidenceRebuild();
        }
      }
      _uiPerf.log(
        'evidence.resolve.done',
        detail:
            'lookup=${lookupKey.hashCode} ms=${sw.elapsedMilliseconds} found=${map.length}',
      );
      return map;
    });
  }

  void _cancelRequest() {
    _detachStreamingUiForBackground(persistUiState: true);
    if (!mounted) return;
    UINotifier.info(context, AppLocalizations.of(context).requestStoppedInfo);
  }

  // 载入"对话页(chat)"的提供商/模型选择（独立于动态页）
  Future<void> _loadChatContextSelection() async {
    try {
      final svc = AIProvidersService.instance;
      final providers = await svc.listProviders();
      if (providers.isEmpty) {
        if (mounted) {
          _setState(() {
            _ctxChatProvider = null;
            _ctxChatModel = null;
            _ctxLoading = false;
          });
        }
        return;
      }
      final ctxRow = await _settings.getAIContextRow('chat');
      AIProvider? sel;
      if (ctxRow != null && ctxRow['provider_id'] is int) {
        sel = await svc.getProvider(ctxRow['provider_id'] as int);
      }
      sel ??= await svc.getDefaultProvider();
      sel ??= providers.first;

      String model =
          (ctxRow != null &&
              (ctxRow['model'] as String?)?.trim().isNotEmpty == true)
          ? (ctxRow['model'] as String).trim()
          : ((sel.extra['active_model'] as String?) ?? sel.defaultModel)
                .toString()
                .trim();
      // 如果上下文中的模型不属于新提供商，回退到"提供商页选择的模型/默认/首个"
      if (model.isEmpty ||
          (sel.models.isNotEmpty && !sel.models.contains(model))) {
        final String fallback =
            ((sel.extra['active_model'] as String?) ?? sel.defaultModel)
                .toString()
                .trim();
        model = fallback.isNotEmpty
            ? fallback
            : (sel.models.isNotEmpty ? sel.models.first : model);
      }

      if (mounted) {
        _setState(() {
          _ctxChatProvider = sel;
          _ctxChatModel = model;
          _ctxLoading = false;
        });
      }
    } catch (_) {
      if (mounted) _setState(() => _ctxLoading = false);
    }
  }

  Future<void> _showProviderSheetChat() async {
    final svc = AIProvidersService.instance;
    final list = await svc.listProviders();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final currentId = _ctxChatProvider?.id ?? -1;
        // 控制器与文本持久化，避免键盘折叠时内容丢失
        final TextEditingController queryCtrl = TextEditingController(
          text: _providerQueryText,
        );
        return StatefulBuilder(
          builder: (c, setModalState) {
            final String q = queryCtrl.text.trim().toLowerCase();
            final List<AIProvider> items = q.isEmpty
                ? list
                : list.where((p) {
                    final name = p.name.toLowerCase();
                    final type = p.type.toLowerCase();
                    final base = (p.baseUrl ?? '').toString().toLowerCase();
                    return name.contains(q) ||
                        type.contains(q) ||
                        base.contains(q);
                  }).toList();
            // 选中的提供商置顶展示
            final selIdx = items.indexWhere((e) => e.id == currentId);
            if (selIdx > 0) {
              final sel = items.removeAt(selIdx);
              items.insert(0, sel);
            }
            return FractionallySizedBox(
              heightFactor: 0.9,
              child: UISheetSurface(
                child: Column(
                  children: [
                    const SizedBox(height: AppTheme.spacing3),
                    const UISheetHandle(),
                    const SizedBox(height: AppTheme.spacing3),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: SearchTextField(
                        controller: queryCtrl,
                        hintText: AppLocalizations.of(
                          context,
                        ).searchProviderPlaceholder,
                        autofocus: true,
                        onChanged: (_) {
                          _providerQueryText = queryCtrl.text;
                          setModalState(() {});
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (c, i) => Container(
                          height: 1,
                          color: Theme.of(
                            c,
                          ).colorScheme.outline.withOpacity(0.6),
                        ),
                        itemBuilder: (c, i) {
                          final p = items[i];
                          final selected = p.id == currentId;
                          return ListTile(
                            leading: SvgPicture.asset(
                              ModelIconUtils.getProviderIconPath(p.type),
                              width: 20,
                              height: 20,
                            ),
                            title: Text(
                              p.name,
                              style: Theme.of(c).textTheme.bodyMedium,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (selected)
                                  Icon(
                                    Icons.check_circle,
                                    color: Theme.of(c).colorScheme.onSurface,
                                  ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: AppLocalizations.of(
                                    context,
                                  ).actionDelete,
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Theme.of(c).colorScheme.error,
                                  ),
                                  onPressed: () async {
                                    final t = AppLocalizations.of(context);
                                    final confirmed =
                                        await showUIDialog<bool>(
                                          context: context,
                                          title: t.deleteGroup,
                                          message: t
                                              .confirmDeleteProviderMessage(
                                                p.name,
                                              ),
                                          actions: [
                                            UIDialogAction<bool>(
                                              text: t.dialogCancel,
                                              result: false,
                                            ),
                                            UIDialogAction<bool>(
                                              text: t.actionDelete,
                                              style: UIDialogActionStyle
                                                  .destructive,
                                              result: true,
                                            ),
                                          ],
                                        ) ??
                                        false;
                                    if (!confirmed) return;
                                    final ok = await svc.deleteProvider(p.id!);
                                    if (!ok) {
                                      // 二次校验：若已删除则按成功处理
                                      final still = await svc.getProvider(
                                        p.id!,
                                      );
                                      if (still != null) {
                                        UINotifier.error(
                                          context,
                                          t.deleteFailed,
                                        );
                                        return;
                                      }
                                    }
                                    // 如果删除的是当前选中提供商，清空上下文并提示
                                    if (selected) {
                                      if (mounted) {
                                        _setState(() {
                                          _ctxChatProvider = null;
                                          _ctxChatModel = null;
                                        });
                                      }
                                    }
                                    // 刷新底部列表
                                    final refreshed = await svc.listProviders();
                                    items
                                      ..clear()
                                      ..addAll(
                                        q.isEmpty
                                            ? refreshed
                                            : refreshed.where((pp) {
                                                final name = pp.name
                                                    .toLowerCase();
                                                final type = pp.type
                                                    .toLowerCase();
                                                final base = (pp.baseUrl ?? '')
                                                    .toString()
                                                    .toLowerCase();
                                                return name.contains(q) ||
                                                    type.contains(q) ||
                                                    base.contains(q);
                                              }),
                                      );
                                    setModalState(() {});
                                    UINotifier.success(context, t.deletedToast);
                                  },
                                ),
                              ],
                            ),
                            onTap: () async {
                              String model = (_ctxChatModel ?? '').trim();
                              final List<String> available = p.models;
                              if (model.isEmpty ||
                                  (available.isNotEmpty &&
                                      !available.contains(model))) {
                                String fb =
                                    (p.extra['active_model'] as String? ??
                                            p.defaultModel)
                                        .toString()
                                        .trim();
                                if (fb.isEmpty && available.isNotEmpty)
                                  fb = available.first;
                                model = fb;
                              }
                              await _settings.setAIContextSelection(
                                context: 'chat',
                                providerId: p.id!,
                                model: model,
                              );
                              if (mounted) {
                                _setState(() {
                                  _ctxChatProvider = p;
                                  _ctxChatModel = model;
                                });
                                Navigator.of(ctx).pop();
                                UINotifier.success(
                                  context,
                                  AppLocalizations.of(
                                    context,
                                  ).providerSelectedToast(p.name),
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showModelSheetChat() async {
    final p = _ctxChatProvider;
    if (p == null) {
      UINotifier.info(
        context,
        AppLocalizations.of(context).pleaseSelectProviderFirst,
      );
      return;
    }
    final models = p.models;
    if (models.isEmpty) {
      UINotifier.info(
        context,
        AppLocalizations.of(context).noModelsForProviderHint,
      );
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final active = (_ctxChatModel ?? '').trim();
        // 控制器与文本持久化，避免键盘折叠时内容丢失
        final TextEditingController queryCtrl = TextEditingController(
          text: _modelQueryText,
        );
        return StatefulBuilder(
          builder: (c, setModalState) {
            final String q = queryCtrl.text.trim().toLowerCase();
            final List<String> items = q.isEmpty
                ? List<String>.from(models)
                : models.where((mm) => mm.toLowerCase().contains(q)).toList();
            if (active.isNotEmpty && items.contains(active)) {
              items.remove(active);
              items.insert(0, active);
            }
            return FractionallySizedBox(
              heightFactor: 0.9,
              child: UISheetSurface(
                child: Column(
                  children: [
                    const SizedBox(height: AppTheme.spacing3),
                    const UISheetHandle(),
                    const SizedBox(height: AppTheme.spacing3),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: SearchTextField(
                        controller: queryCtrl,
                        hintText: AppLocalizations.of(
                          context,
                        ).searchModelPlaceholder,
                        autofocus: true,
                        onChanged: (_) {
                          _modelQueryText = queryCtrl.text;
                          setModalState(() {});
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (c, i) => Container(
                          height: 1,
                          color: Theme.of(
                            c,
                          ).colorScheme.outline.withOpacity(0.6),
                        ),
                        itemBuilder: (c, i) {
                          final m = items[i];
                          final selected = m == active;
                          return ListTile(
                            leading: SvgPicture.asset(
                              ModelIconUtils.getIconPath(m),
                              width: 20,
                              height: 20,
                            ),
                            title: Text(
                              m,
                              style: Theme.of(c).textTheme.bodyMedium,
                            ),
                            trailing: selected
                                ? Icon(
                                    Icons.check_circle,
                                    color: Theme.of(c).colorScheme.onSurface,
                                  )
                                : null,
                            onTap: () async {
                              await _settings.setAIContextSelection(
                                context: 'chat',
                                providerId: p.id!,
                                model: m,
                              );
                              if (mounted) {
                                _setState(() => _ctxChatModel = m);
                                Navigator.of(ctx).pop();
                                UINotifier.success(
                                  context,
                                  AppLocalizations.of(
                                    context,
                                  ).modelSwitchedToast(m),
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 顶部"提供商 / 模型"极小字号、可点击切换
  Widget _buildProviderModelHeader() {
    final theme = Theme.of(context);
    final String providerLabel = AppLocalizations.of(context).providerLabel;
    final String providerName = _ctxChatProvider?.name ?? '—';
    final String modelName = _ctxChatModel ?? '—';
    final TextStyle? underlined = theme.textTheme.labelSmall?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.onSurface.withOpacity(0.6),
      color: theme.colorScheme.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
      child: Row(
        children: [
          GestureDetector(
            onTap: _showProviderSheetChat,
            behavior: HitTestBehavior.opaque,
            child: Text(providerLabel, style: underlined),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              providerName,
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          GestureDetector(
            onTap: _showModelSheetChat,
            behavior: HitTestBehavior.opaque,
            child: Text(
              modelName,
              style: underlined,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
  }) {
    // 紧凑型输入框（更小的字体与内边距）
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onTap: () {
          // 点击连接设置里的输入框时，自动收起上方分组下拉区域
          if (_groupSelectorVisible) {
            _setState(() {
              _groupSelectorVisible = false;
            });
          }
        },
        style: Theme.of(context).textTheme.bodySmall,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing2,
            vertical: AppTheme.spacing2,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: Theme.of(context).textTheme.bodySmall,
          hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          filled: false,
        ),
      ),
    );
  }

  /// 折叠头部摘要：展示当前分组 + baseUrl + model（截断显示）
  String _buildConnSummary() {
    final gid = _activeGroupId;
    String groupName;
    if (gid == null) {
      groupName = AppLocalizations.of(context).ungroupedSingleConfig;
    } else {
      final g = _groups.where((e) => e.id == gid).toList();
      groupName = g.isNotEmpty
          ? g.first.name
          : AppLocalizations.of(context).siteGroupDefaultName(gid);
    }
    final base = _baseUrlController.text.trim().isEmpty
        ? 'https://api.openai.com'
        : _baseUrlController.text.trim();
    final model = _modelController.text.trim().isEmpty
        ? 'gpt-4o-mini'
        : _modelController.text.trim();

    String brief(String s, int max) =>
        s.length > max ? (s.substring(0, max) + '…') : s;

    return '$groupName · ${brief(base, 36)} · ${brief(model, 24)}';
  }

  /// 折叠头部摘要：提示词管理当前状态
  String _buildPromptSummary() {
    final l10n = AppLocalizations.of(context);
    final seg = (_promptSegment == null || _promptSegment!.trim().isEmpty)
        ? l10n.defaultLabel
        : l10n.customLabel;
    final mer = (_promptMerge == null || _promptMerge!.trim().isEmpty)
        ? l10n.defaultLabel
        : l10n.customLabel;
    final day = (_promptDaily == null || _promptDaily!.trim().isEmpty)
        ? l10n.defaultLabel
        : l10n.customLabel;
    return '${l10n.normalShortLabel} $seg · ${l10n.mergeShortLabel} $mer · ${l10n.dailyShortLabel} $day';
  }

  Future<void> _onGroupChanged(int? newId) async {
    await _settings.setActiveGroupId(newId);
    await _loadAll();
    if (!mounted) return;
    UINotifier.success(
      context,
      newId == null
          ? AppLocalizations.of(context).groupSwitchedToUngrouped
          : AppLocalizations.of(context).groupSwitched,
    );
  }

  Future<void> _addGroup() async {
    try {
      final name = AppLocalizations.of(
        context,
      ).siteGroupDefaultName(_groups.length + 1);
      final base = _baseUrlController.text.trim().isEmpty
          ? 'https://api.openai.com'
          : _baseUrlController.text.trim();
      final key = _apiKeyController.text.trim();
      final model = _modelController.text.trim().isEmpty
          ? 'gpt-4o-mini'
          : _modelController.text.trim();
      final id = await _settings.addSiteGroup(
        name: name,
        baseUrl: base,
        apiKey: key.isEmpty ? null : key,
        model: model,
      );
      await _settings.setActiveGroupId(id);
      await _loadAll();
      if (!mounted) return;
      UINotifier.success(context, AppLocalizations.of(context).groupAddedToast);
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).addGroupFailedWithError(e.toString()),
      );
    }
  }

  Future<void> _renameActiveGroup() async {
    final gid = _activeGroupId;
    if (gid == null) {
      if (mounted)
        UINotifier.info(context, AppLocalizations.of(context).groupNotSelected);
      return;
    }
    try {
      final g = await _settings.getSiteGroupById(gid);
      if (g == null) {
        if (mounted)
          UINotifier.error(context, AppLocalizations.of(context).groupNotFound);
        return;
      }
      final controller = TextEditingController(text: g.name);
      await showUIDialog<void>(
        context: context,
        title: AppLocalizations.of(context).renameGroupTitle,
        content: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          child: TextField(
            controller: controller,
            style: Theme.of(context).textTheme.bodySmall,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).groupNameLabel,
              hintText: AppLocalizations.of(context).groupNameHint,
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing2,
                vertical: AppTheme.spacing2,
              ),
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
          ),
        ),
        actions: [
          UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
          UIDialogAction(
            text: AppLocalizations.of(context).dialogOk,
            style: UIDialogActionStyle.primary,
            closeOnPress: false,
            onPressed: (ctx) async {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                UINotifier.error(
                  ctx,
                  AppLocalizations.of(ctx).nameCannotBeEmpty,
                );
                return;
              }
              try {
                final updated = g.copyWith(name: newName);
                await _settings.updateSiteGroup(updated);
                if (ctx.mounted) Navigator.of(ctx).pop();
                await _loadAll();
                if (mounted)
                  UINotifier.success(
                    context,
                    AppLocalizations.of(context).renameSuccess,
                  );
              } catch (e) {
                if (ctx.mounted)
                  UINotifier.error(
                    ctx,
                    AppLocalizations.of(
                      ctx,
                    ).renameFailedWithError(e.toString()),
                  );
              }
            },
          ),
        ],
      );
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).loadGroupFailedWithError(e.toString()),
        );
    }
  }

  Future<void> _deleteActiveGroup() async {
    final gid = _activeGroupId;
    if (gid == null) {
      UINotifier.info(context, AppLocalizations.of(context).groupNotSelected);
      return;
    }
    try {
      await _settings.deleteSiteGroup(gid);
      await _settings.setActiveGroupId(null);
      await _loadAll();
      if (!mounted) return;
      UINotifier.success(
        context,
        AppLocalizations.of(context).groupDeletedToast,
      );
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).deleteGroupFailedWithError(e.toString()),
      );
    }
  }

  Widget _buildGroupSelector() {
    final items = <DropdownMenuItem<int?>>[
      DropdownMenuItem<int?>(
        value: null,
        child: Text(AppLocalizations.of(context).ungroupedSingleConfig),
      ),
      ..._groups.map(
        (g) => DropdownMenuItem<int?>(value: g.id, child: Text(g.name)),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).siteGroupsTitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          AppLocalizations.of(context).siteGroupsHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTheme.spacing2),
        if (_groupSelectorVisible)
          Row(
            children: [
              DropdownButton<int?>(
                value: _activeGroupId,
                items: items,
                isDense: true,
                style: Theme.of(context).textTheme.bodySmall,
                onChanged: (v) => _onGroupChanged(v),
              ),
              const SizedBox(width: AppTheme.spacing2),
              UIButton(
                text: AppLocalizations.of(context).rename,
                variant: UIButtonVariant.outline,
                size: UIButtonSize.small,
                onPressed: (_activeGroupId == null) ? null : _renameActiveGroup,
              ),
              const SizedBox(width: AppTheme.spacing2),
              UIButton(
                text: AppLocalizations.of(context).addGroup,
                variant: UIButtonVariant.outline,
                size: UIButtonSize.small,
                onPressed: _addGroup,
              ),
            ],
          )
        else
          TextButton(
            onPressed: () => _setState(() {
              _groupSelectorVisible = true;
            }),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing2,
                vertical: AppTheme.spacing1,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              AppLocalizations.of(context).showGroupSelector,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildInputField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: TextField(
        controller: _inputController,
        textAlignVertical: TextAlignVertical.center,
        onTap: () {
          // 点击底部输入框时收起整个"连接设置"折叠区，避免遮挡内容
          _setState(() {
            _connExpanded = false;
          });
        },
        style: Theme.of(context).textTheme.bodySmall,
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context).inputMessageHint,
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppTheme.spacing2,
            vertical: AppTheme.spacing2,
          ),
          filled: false,
        ),
        minLines: 1,
        maxLines: null,
      ),
    );
  }

  // 魔法渐变图标（auto_awesome）
  // withGlow=true 时在图标背后叠加弥散光（主色/次色）
  Widget _buildMagicIcon({double size = 18, bool withGlow = false}) {
    // 不使用主题主/次色，改为 Gemini 风蓝色系（避免主题色影响视觉）
    final br = Theme.of(context).brightness;
    LinearGradient _maskGradient(Rect bounds) {
      final colors = _geminiGradientColors(br);
      // 蓝 -> 黄，提升黄端占比与亮度感（通过倾斜 stops）
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [colors[2], colors[8]],
        stops: const [0.0, 0.75],
      );
    }

    Widget _buildGradientGlowBackground(double iconSize) {
      // 使用蓝色系圆形渐变，叠加模糊形成柔和弥散光，确保为圆形而非矩形
      final double glowDiameter = iconSize * 3.0;
      return SizedBox(
        width: glowDiameter,
        height: glowDiameter,
        child: ClipOval(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: iconSize * 0.9,
              sigmaY: iconSize * 0.9,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.85,
                  colors: [
                    _geminiGradientColors(
                      br,
                    )[2].withOpacity(br == Brightness.dark ? 0.42 : 0.52),
                    _geminiGradientColors(br)[5].withOpacity(0.0),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 使用蓝色系 ShaderMask 渐变方案，显式设置白色避免 IconTheme 重新上色
    final Widget gradientIcon = ShaderMask(
      shaderCallback: (Rect bounds) =>
          _maskGradient(bounds).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Icon(Icons.auto_awesome, size: size, color: Colors.white),
    );
    if (!withGlow) return gradientIcon;
    // 使用渐变+模糊的柔光背景，替代主题色 BoxShadow，确保与菜单第三项一致的渐变观感
    return Stack(
      alignment: Alignment.center,
      children: [_buildGradientGlowBackground(size), gradientIcon],
    );
  }

  Widget _buildMarkdownForMessage({
    required AIMessage message,
    required int messageIndex,
    required String content,
    required Color fg,
    required bool isCurrentStreaming,
  }) {
    if (isCurrentStreaming && !_renderImagesDuringStreaming) {
      // 流式期间渲染轻量文本，避免高频 Markdown 重建。
      // 同时裁掉开头的空行，避免与最终 Markdown（会忽略前导换行）出现明显跳动。
      final String t = content
          .replaceAll('\r\n', '\n')
          .replaceFirst(RegExp(r'^\n+'), '');
      return SelectableText(
        t,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
      );
    }

    // 非流式：构建 Markdown 与 evidence 解析
    final String perfMsgKey = _evidenceMsgKey(message);
    final bool logOnce = _perfLoggedMarkdownMsgKeys.add(perfMsgKey);
    final Stopwatch mdSw = Stopwatch()..start();
    final String preprocessedMd = preprocessForChatMarkdown(content);
    if (logOnce) {
      _uiPerf.log(
        'md.preprocess',
        detail:
            'msg=${perfMsgKey.hashCode} ms=${mdSw.elapsedMilliseconds} len=${content.length}',
      );
    }
    final Map<String, String> evidenceNameToPath = <String, String>{};
    final List<EvidenceImageAttachment> atts =
        _attachmentsByIndex[messageIndex] ?? const <EvidenceImageAttachment>[];
    for (final a in atts) {
      final String name = _basenameFromPath(a.path).trim();
      if (name.isNotEmpty) evidenceNameToPath[name] = a.path;
    }
    final List<String> orderedEvidencePathsFromAtts = (() {
      final List<String> out = <String>[];
      final Set<String> seen = <String>{};
      for (final a in atts) {
        final String p = a.path.trim();
        if (p.isEmpty) continue;
        if (seen.add(p)) out.add(p);
      }
      return out;
    })();
    final mathConfig = MarkdownMathConfig(
      inlineTextStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: fg),
      blockTextStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: fg),
      appIconByPackage: _chatAppIconByPackage,
      appIconByNameLower: _chatAppIconByNameLower,
      appNameByPackage: _chatAppNameByPackage,
      evidenceNameToPath: evidenceNameToPath,
      orderedEvidencePaths: orderedEvidencePathsFromAtts,
      screenshotByPath: _evidenceScreenshotByPath,
      perfLogger: _uiPerf,
    );

    // 提取 evidence 引用（保留顺序，便于为查看器构建稳定的 gallery 顺序）
    final List<String> evidenceNamesInOrder = <String>[];
    final Set<String> evidenceNames = <String>{};
    for (final mm in RegExp(
      r'\[evidence:\s*([^\]\s]+)\s*\]',
    ).allMatches(preprocessedMd)) {
      final String name = (mm.group(1) ?? '').trim();
      if (name.isEmpty) continue;
      if (evidenceNames.add(name)) evidenceNamesInOrder.add(name);
    }
    if (logOnce) {
      _uiPerf.log(
        'md.evidence.scan',
        detail:
            'msg=${perfMsgKey.hashCode} evidence=${evidenceNames.length} atts=${atts.length}',
      );
    }

    // 流式期间（且允许渲染图片）尽量只用预加载附件映射，避免高频重建触发扫库
    if (isCurrentStreaming) {
      return MarkdownBody(
        data: preprocessedMd,
        builders: mathConfig.builders,
        blockSyntaxes: mathConfig.blockSyntaxes,
        inlineSyntaxes: mathConfig.inlineSyntaxes,
        styleSheet: _mdStyle(context).copyWith(
          p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
        ),
        onTapLink: (text, href, title) async {
          if (href == null) return;
          final uri = Uri.tryParse(href);
          if (uri != null) {
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {}
          }
        },
      );
    }

    if (evidenceNames.isEmpty) {
      return MarkdownBody(
        data: preprocessedMd,
        builders: mathConfig.builders,
        blockSyntaxes: mathConfig.blockSyntaxes,
        inlineSyntaxes: mathConfig.inlineSyntaxes,
        styleSheet: _mdStyle(context).copyWith(
          p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
        ),
        onTapLink: (text, href, title) async {
          if (href == null) return;
          final uri = Uri.tryParse(href);
          if (uri != null) {
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {}
          }
        },
      );
    }

    final String msgKey = perfMsgKey;
    final Map<String, String> cached =
        _evidenceResolvedByMsgKey[msgKey] ?? const <String, String>{};
    final Map<String, String> baseMap = <String, String>{
      ...evidenceNameToPath,
      ...cached,
    };
    _scheduleEvidenceNsfwPreload(baseMap.values);
    final Set<String> missing = evidenceNames
        .where((n) => !baseMap.containsKey(n))
        .toSet();
    if (logOnce) {
      _uiPerf.log(
        'md.evidence.missing',
        detail:
            'msg=${perfMsgKey.hashCode} missing=${missing.length} cached=${cached.length}',
      );
    }

    List<String> orderedEvidencePathsFromMap(Map<String, String> map) {
      if (orderedEvidencePathsFromAtts.isNotEmpty) {
        return orderedEvidencePathsFromAtts;
      }
      final List<String> out = <String>[];
      final Set<String> seen = <String>{};
      for (final n in evidenceNamesInOrder) {
        final String? p = map[n];
        if (p == null || p.trim().isEmpty) continue;
        if (seen.add(p)) out.add(p);
      }
      return out;
    }

    if (missing.isEmpty) {
      final resolved = MarkdownMathConfig(
        inlineTextStyle: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: fg),
        blockTextStyle: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: fg),
        appIconByPackage: _chatAppIconByPackage,
        appIconByNameLower: _chatAppIconByNameLower,
        appNameByPackage: _chatAppNameByPackage,
        evidenceNameToPath: baseMap,
        orderedEvidencePaths: orderedEvidencePathsFromMap(baseMap),
        screenshotByPath: _evidenceScreenshotByPath,
        perfLogger: _uiPerf,
      );
      return MarkdownBody(
        data: preprocessedMd,
        builders: resolved.builders,
        blockSyntaxes: resolved.blockSyntaxes,
        inlineSyntaxes: resolved.inlineSyntaxes,
        styleSheet: _mdStyle(context).copyWith(
          p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
        ),
        onTapLink: (text, href, title) async {
          if (href == null) return;
          final uri = Uri.tryParse(href);
          if (uri != null) {
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {}
          }
        },
      );
    }

    if (logOnce) {
      _uiPerf.log(
        'md.evidence.resolve.future',
        detail:
            'msg=${perfMsgKey.hashCode} missing=${missing.length} willQueryDb=1',
      );
    }
    return FutureBuilder<Map<String, String>>(
      future: _resolveEvidencePathsCached(
        msgKey: msgKey,
        missingNames: missing,
      ),
      builder: (context, snap) {
        final Map<String, String> map = snap.data ?? const <String, String>{};
        final merged = <String, String>{...baseMap, ...map};
        _scheduleEvidenceNsfwPreload(merged.values);
        final resolved = MarkdownMathConfig(
          inlineTextStyle: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: fg),
          blockTextStyle: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: fg),
          appIconByPackage: _chatAppIconByPackage,
          appIconByNameLower: _chatAppIconByNameLower,
          appNameByPackage: _chatAppNameByPackage,
          // While the future is resolving, avoid flashing raw `[evidence: ...]`
          // text; show a fixed-size shimmer placeholder instead.
          evidenceLoading: snap.connectionState != ConnectionState.done,
          evidenceNameToPath: merged,
          orderedEvidencePaths: orderedEvidencePathsFromMap(merged),
          screenshotByPath: _evidenceScreenshotByPath,
          perfLogger: _uiPerf,
        );
        return MarkdownBody(
          // flutter_markdown may cache internal builders across rebuilds when the
          // markdown `data` doesn't change. Force a rebuild when the evidence
          // resolve state changes so resolved paths can take effect.
          key: ValueKey(
            'md:$msgKey:${snap.connectionState.name}:${map.length}',
          ),
          data: preprocessedMd,
          builders: resolved.builders,
          blockSyntaxes: resolved.blockSyntaxes,
          inlineSyntaxes: resolved.inlineSyntaxes,
          styleSheet: _mdStyle(context).copyWith(
            p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
          ),
          onTapLink: (text, href, title) async {
            if (href == null) return;
            final uri = Uri.tryParse(href);
            if (uri != null) {
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            }
          },
        );
      },
    );
  }

  List<_ThinkingBlock> _blocksForMessageIndex(int messageIndex) {
    final List<_ThinkingBlock>? existing = _thinkingBlocksByIndex[messageIndex];
    if (existing != null && existing.isNotEmpty) return existing;

    // When restoring history, keep the UI consistent with the live rendering:
    // - We do NOT expand legacy reasoning logs into many event rows.
    // - We still show a thinking card with the recorded duration (if available).
    final String legacyReasoning = (_reasoningByIndex[messageIndex] ?? '')
        .trim();
    final Duration? dur =
        _reasoningDurationByIndex[messageIndex] ??
        ((messageIndex >= 0 && messageIndex < _messages.length)
            ? _messages[messageIndex].reasoningDuration
            : null);
    if (legacyReasoning.isEmpty && (dur == null || dur.inMilliseconds <= 0)) {
      return const <_ThinkingBlock>[];
    }

    final DateTime createdAt =
        (messageIndex >= 0 && messageIndex < _messages.length)
        ? _messages[messageIndex].createdAt
        : DateTime.now();
    final _ThinkingBlock b = _ThinkingBlock(createdAt: createdAt);
    if (dur != null && dur.inMilliseconds > 0) {
      b.finishedAt = createdAt.add(dur);
    } else {
      b.finishedAt = createdAt;
    }
    return <_ThinkingBlock>[b];
  }

  List<String> _contentSegmentsForMessageIndex(int messageIndex) {
    final List<String>? segs = _contentSegmentsByIndex[messageIndex];
    if (segs != null) return segs;
    if (messageIndex >= 0 && messageIndex < _messages.length) {
      final AIMessage m = _messages[messageIndex];
      final String t = m.content;
      if (t.trim().isEmpty) return const <String>[];

      // Restore streaming segment boundaries (if recorded) so the bubble/copy
      // order matches the original model/tool interleaving.
      final String uiJson = (m.uiThinkingJson ?? '').trim();
      if (uiJson.isNotEmpty) {
        final List<int> lens = _decodeSegmentLengthsFromUiJson(uiJson);
        if (lens.length > 1) {
          int offset = 0;
          final List<String> out = <String>[];
          bool invalid = false;
          for (final int len in lens) {
            final int end = offset + len;
            if (len <= 0 || end > t.length) {
              invalid = true;
              break;
            }
            out.add(t.substring(offset, end));
            offset = end;
          }
          if (!invalid) {
            if (offset < t.length) {
              // Preserve any tail text if content changed (best-effort).
              if (out.isEmpty) {
                out.add(t.substring(offset));
              } else {
                out[out.length - 1] = out.last + t.substring(offset);
              }
            }
            if (out.length > 1) {
              _contentSegmentsByIndex[messageIndex] = out;
              return out;
            }
          }
        }
      }

      return <String>[t];
    }
    return const <String>[];
  }

  String _buildThinkingBlockTextForCopy(_ThinkingBlock b) {
    if (b.events.isEmpty) return '';
    final sb = StringBuffer();
    for (final e in b.events) {
      final String title = e.title.trim();
      final String sub = (e.subtitle ?? '').trim();
      if (title.isNotEmpty) sb.writeln(title);
      if (sub.isNotEmpty) sb.writeln(sub);
      if (e.type == _ThinkingEventType.tools && e.tools.isNotEmpty) {
        for (final chip in e.tools) {
          final String text = _toolChipTextForDisplay(context, chip).trim();
          if (text.isNotEmpty) sb.writeln('- $text');
        }
      }
      if (title.isNotEmpty || sub.isNotEmpty || e.tools.isNotEmpty) {
        sb.writeln();
      }
    }
    return sb.toString().trim();
  }

  String _buildThinkingTimelineTextForCopy(int messageIndex) {
    final List<_ThinkingBlock> blocks = _blocksForMessageIndex(messageIndex);
    if (blocks.isEmpty) return '';
    final sb = StringBuffer();
    for (final b in blocks) {
      final String part = _buildThinkingBlockTextForCopy(b);
      if (part.isNotEmpty) sb.writeln(part + '\n');
    }
    return sb.toString().trim();
  }

  String _buildMessageCopyText(AIMessage m, int messageIndex) {
    final bool isAssistant = m.role == 'assistant';

    if (!isAssistant) return m.content.trim();

    // Interleave blocks/segs in the same order as the bubble UI.
    final List<_ThinkingBlock> blocks = _blocksForMessageIndex(messageIndex);
    final List<String> segs = _contentSegmentsForMessageIndex(messageIndex);
    final int n = (blocks.length > segs.length) ? blocks.length : segs.length;

    final List<String> parts = <String>[];
    for (int i = 0; i < n; i++) {
      if (i < blocks.length) {
        final String t = _buildThinkingBlockTextForCopy(blocks[i]).trim();
        if (t.isNotEmpty) parts.add(t);
      }
      if (i < segs.length) {
        final String s = segs[i].trim();
        if (s.isNotEmpty) parts.add(s);
      }
    }

    // Only include legacy reasoning while any thinking block is still loading
    // (matches the UI, which hides legacy logs after completion).
    if (parts.isEmpty) {
      final bool anyLoading = blocks.any((b) => b.finishedAt == null);
      if (anyLoading) {
        final String legacy =
            (_reasoningByIndex[messageIndex] ?? m.reasoningContent ?? '')
                .trim();
        if (legacy.isNotEmpty) return legacy;
      }
      return m.content.trim();
    }
    return parts.join('\n\n').trim();
  }
}
