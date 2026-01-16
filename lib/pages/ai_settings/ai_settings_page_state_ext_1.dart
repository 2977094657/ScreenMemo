part of '../ai_settings_page.dart';

extension _AISettingsPageStateExt1 on _AISettingsPageState {
  Widget _withDrawerSwipe(Widget child) {
    // 在任意位置从左向右滑动达到一定阈值后，打开上层 Scaffold 的 Drawer
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _drawerGestureAccumDx = 0.0;
        _drawerGestureTriggered = false;
      },
      onHorizontalDragUpdate: (details) {
        if (_drawerGestureTriggered) return;
        final double dx = (details.primaryDelta ?? details.delta.dx);
        if (dx > 0) {
          _drawerGestureAccumDx += dx;
        } else {
          // 向左滑动重置累计，避免误触
          _drawerGestureAccumDx = 0.0;
        }
        // 触发阈值（约 56 像素），避免轻微抖动误开
        if (_drawerGestureAccumDx >= 56.0) {
          final scaffold = Scaffold.maybeOf(context);
          if (scaffold != null && !scaffold.isDrawerOpen) {
            FocusScope.of(context).unfocus();
            scaffold.openDrawer();
          }
          _drawerGestureTriggered = true;
        }
      },
      onHorizontalDragEnd: (_) {
        _drawerGestureAccumDx = 0.0;
        _drawerGestureTriggered = false;
      },
      onHorizontalDragCancel: () {
        _drawerGestureAccumDx = 0.0;
        _drawerGestureTriggered = false;
      },
      child: child,
    );
  }

  // —— Gemini 风蓝色系颜色（供图标/弥散光使用；明暗自适应） ——
  List<Color> _geminiGradientColors(Brightness brightness) {
    // 进一步提亮与增饱和：按"至少值"提升，避免乘法带来的变暗
    Color tune(
      Color c, {
      double sMinLight = 0.98,
      double sMinDark = 0.96,
      double lMinLight = 0.80,
      double lMinDark = 0.72,
    }) {
      final h = HSLColor.fromColor(c);
      final double sTarget = brightness == Brightness.dark
          ? sMinDark
          : sMinLight;
      final double lTarget = brightness == Brightness.dark
          ? lMinDark
          : lMinLight;
      final double s = (h.saturation < sTarget) ? sTarget : h.saturation;
      final double l = (h.lightness < lTarget) ? lTarget : h.lightness;
      return h.withSaturation(s).withLightness(l).toColor();
    }

    // 蓝色主调 + 黄色（去掉青色）
    final Color c1 = tune(const Color(0xFF1F6FEB)); // 深蓝
    final Color c2 = tune(const Color(0xFF3B82F6)); // 标准蓝
    final Color c3 = tune(const Color(0xFF60A5FA)); // 浅蓝
    final Color c4 = tune(const Color(0xFF7C83FF)); // 蓝紫
    // 黄色单独进一步提亮，确保更"亮"更显眼
    final Color cY = tune(
      const Color(0xFFF59E0B),
      lMinLight: 0.86,
      lMinDark: 0.76,
    );
    return [
      c1,
      Color.lerp(c1, c2, 0.5)!,
      c2,
      Color.lerp(c2, c3, 0.5)!,
      c3,
      Color.lerp(c3, c4, 0.5)!,
      c4,
      Color.lerp(c4, cY, 0.45)!,
      cY,
    ];
  }

  // 提供近期"仅用户消息"的文本，用于意图分析器判断是否续问
  List<String> _extractPreviousUserQueries({int maxCount = 3}) {
    if (_messages.isEmpty) return const <String>[];
    final List<String> out = <String>[];
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.role == 'user') {
        final c = m.content.trim();
        if (c.isNotEmpty) out.add(c);
        if (out.length >= maxCount) break;
      }
    }
    return out;
  }

  Future<void> _loadAll() async {
    final sw = Stopwatch()..start();
    try {
      if (_loadingAllInFlight) return; // 防止重入触发的重复加载
      _loadingAllInFlight = true;
      // 并行预取，避免串行等待造成的累计时延
      final Future<List<AISiteGroup>> fGroups = _settings.listSiteGroups();
      final Future<int?> fActiveId = _settings.getActiveGroupId();
      final Future<List<AIMessage>> fHistory = _settings.getChatHistory();
      final Future<bool> fStreamEnabled = _settings.getStreamEnabled();
      final Future<String?> fSegPrompt = _settings.getPromptSegment();
      final Future<String?> fMergePrompt = _settings.getPromptMerge();
      final Future<String?> fDailyPrompt = _settings.getPromptDaily();
      final Future<String> fBaseUrl = _settings.getBaseUrl();
      // 读取密钥设置超时，避免拖慢首屏（超时则稍后用户手动查看/编辑）
      final Future<String?> fApiKey = _settings.getApiKey().timeout(
        const Duration(milliseconds: 600),
        onTimeout: () => null,
      );
      final Future<String> fModel = _settings.getModel();

      // 先拿到分组与激活ID
      final List<AISiteGroup> groups = await fGroups;
      final int? activeId = await fActiveId;

      // 基础配置：若存在激活分组，则优先使用分组中的值；否则使用未分组键值
      String baseUrl;
      String? apiKey;
      String model;
      if (activeId != null) {
        final g = await _settings.getSiteGroupById(activeId);
        baseUrl = g?.baseUrl ?? await fBaseUrl;
        apiKey = g?.apiKey ?? await fApiKey;
        model = g?.model ?? await fModel;
      } else {
        baseUrl = await fBaseUrl;
        apiKey = await fApiKey;
        model = await fModel;
      }

      // 收集其余预取结果
      final List<AIMessage> history = await fHistory;
      final bool streamEnabled = await fStreamEnabled;
      final bool renderImgs = await _settings.getRenderImagesDuringStreaming();
      final String? segPrompt = await fSegPrompt;
      final String? mergePrompt = await fMergePrompt;
      final String? dailyPrompt = await fDailyPrompt;

      // 回填历史消息的深度思考内容与耗时（索引映射到消息）
      final Map<int, String> rb = <int, String>{};
      final Map<int, Duration> rd = <int, Duration>{};
      final Map<int, List<_ThinkingBlock>> tb = <int, List<_ThinkingBlock>>{};
      for (int i = 0; i < history.length; i++) {
        final m = history[i];
        if (m.role != 'user') {
          final String? rc = m.reasoningContent;
          if (rc != null && rc.trim().isNotEmpty) rb[i] = rc;
          final Duration? dur = m.reasoningDuration;
          if (dur != null && dur.inMilliseconds > 0) rd[i] = dur;
        }

        // Restore chat-bubble thinking timeline blocks/events (if available).
        final String? uiJson = m.uiThinkingJson;
        if (uiJson != null && uiJson.trim().isNotEmpty) {
          final List<_ThinkingBlock> blocks = _decodeThinkingBlocks(uiJson);
          if (blocks.isNotEmpty) tb[i] = blocks;
        }
      }

      if (!mounted) return;
      _setState(() {
        _groups = groups;
        _activeGroupId = activeId;

        // 未分组：默认值隐藏；分组：直接填充实际值
        if (activeId == null) {
          _baseUrlController.text = (baseUrl == 'https://api.openai.com')
              ? ''
              : baseUrl;
          _apiKeyController.text = apiKey ?? '';
          _modelController.text = (model == 'gpt-4o-mini') ? '' : model;
        } else {
          _baseUrlController.text = baseUrl;
          _apiKeyController.text = apiKey ?? '';
          _modelController.text = model;
        }

        // 分批填充消息，降低单帧构建压力
        _messages = <AIMessage>[];
        _clarifyState = null;
        _attachmentsByIndex.clear();
        _evidenceResolvedByMsgKey.clear();
        _evidenceResolveFutures.clear();
        _thinkingBlocksByIndex
          ..clear()
          ..addAll(tb);
        _contentSegmentsByIndex.clear();
        _nextContentStartsNewSegmentByIndex.clear();
        _reasoningByIndex
          ..clear()
          ..addAll(rb);
        _reasoningDurationByIndex
          ..clear()
          ..addAll(rd);
        _streamEnabled = streamEnabled;
        _promptSegment = segPrompt;
        _promptMerge = mergePrompt;
        _promptDaily = dailyPrompt;
        _renderImagesDuringStreaming = renderImgs;
        // 预填编辑器：仅填充用户补充说明，避免暴露系统默认模板
        _promptSegmentController.text = _promptSegment?.trim() ?? '';
        _promptMergeController.text = _promptMerge?.trim() ?? '';
        _promptDailyController.text = _promptDaily?.trim() ?? '';
        _loading = false;
      });
      if (mounted) {
        // 将消息分批追加到列表，避免一次性构建大量 Markdown
        const int batch = 24;
        for (int i = 0; i < history.length; i += batch) {
          final int end = (i + batch > history.length)
              ? history.length
              : (i + batch);
          final List<AIMessage> slice = history.sublist(i, end);
          final bool isLast = end >= history.length;
          // 逐批在微任务中追加，释放主帧
          scheduleMicrotask(() {
            if (!mounted) return;
            _setState(() {
              _messages.addAll(slice);
            });
            if (isLast) {
              _scrollToBottom(animated: true);
            }
          });
        }
      }
      // 记录 UI 填充耗时（数据到状态）
      try {
        await FlutterLogger.nativeInfo(
          'UI',
          'AISettings._loadAll setState ms=' +
              sw.elapsedMilliseconds.toString(),
        );
      } catch (_) {}
    } catch (_) {
      if (mounted)
        _setState(() {
          _loading = false;
        });
    } finally {
      _loadingAllInFlight = false;
    }
    // 首帧绘制完成耗时（状态更新到绘制）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await FlutterLogger.nativeInfo(
          'UI',
          'AISettings._loadAll first-frame ms=' +
              sw.elapsedMilliseconds.toString(),
        );
      } catch (_) {}
    });
  }

  Future<void> _saveSettings() async {
    if (_saving) return;
    _setState(() {
      _saving = true;
    });
    try {
      final base = _baseUrlController.text.trim();
      final key = _apiKeyController.text.trim();
      final model = _modelController.text.trim();

      final gid = _activeGroupId;
      if (gid != null) {
        // 更新当前分组
        final g = await _settings.getSiteGroupById(gid);
        if (g == null) {
          UINotifier.error(context, AppLocalizations.of(context).groupNotFound);
        } else {
          final updated = g.copyWith(
            baseUrl: base.isEmpty ? g.baseUrl : base,
            apiKey: key.isEmpty ? null : key,
            model: model.isEmpty ? g.model : model,
          );
          await _settings.updateSiteGroup(updated);
          UINotifier.success(
            context,
            AppLocalizations.of(context).savedCurrentGroupToast,
          );
        }
      } else {
        // 未分组：保存到键值
        await _settings.setBaseUrl(base);
        await _settings.setApiKey(key.isEmpty ? null : key);
        await _settings.setModel(model);
        UINotifier.success(context, AppLocalizations.of(context).saveSuccess);
      }
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).saveFailedError(e.toString()),
      );
    } finally {
      if (mounted)
        _setState(() {
          _saving = false;
        });
    }
  }

  // ======= 提示词管理 =======
  Widget _buildPromptManagerCard() {
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final hintStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    const int maxAddonLength = 2000;

    Widget buildSection({
      required String label,
      required String currentAddon,
      required String infoText,
      required String suggestion,
      required bool editing,
      required TextEditingController controller,
      required VoidCallback onEditToggle,
      required Future<void> Function() onSave,
      required Future<void> Function() onReset,
      required bool saving,
    }) {
      final theme = Theme.of(context);
      final placeholderStyle = theme.textTheme.bodySmall?.copyWith(
        color: theme.hintColor,
      );
      final hasAddon = currentAddon.trim().isNotEmpty;
      final displayText = hasAddon ? currentAddon.trim() : suggestion;
      final displayStyle = hasAddon
          ? theme.textTheme.bodySmall
          : placeholderStyle;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: titleStyle),
              const Spacer(),
              Align(
                alignment: Alignment.centerRight,
                child: editing
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: saving ? null : onSave,
                            child: Text(
                              saving
                                  ? AppLocalizations.of(context).savingLabel
                                  : AppLocalizations.of(context).actionSave,
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing1),
                          TextButton(
                            onPressed: saving ? null : onReset,
                            child: Text(
                              AppLocalizations.of(context).resetToDefault,
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing1),
                          TextButton(
                            onPressed: saving ? null : onEditToggle,
                            child: Text(
                              AppLocalizations.of(context).dialogCancel,
                            ),
                          ),
                        ],
                      )
                    : TextButton(
                        onPressed: onEditToggle,
                        child: Text(AppLocalizations.of(context).actionEdit),
                      ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(infoText, style: hintStyle),
          const SizedBox(height: AppTheme.spacing1),
          if (!editing)
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacing3),
                child: SelectableText(displayText, style: displayStyle),
              ),
            )
          else
            TextField(
              controller: controller,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 10,
              maxLines: null,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: suggestion,
                hintMaxLines: 16,
                contentPadding: const EdgeInsets.all(AppTheme.spacing3),
              ),
            ),
          const SizedBox(height: AppTheme.spacing3),
        ],
      );
    }

    final segAddon = _promptSegment?.trim() ?? '';
    final mergeAddon = _promptMerge?.trim() ?? '';
    final dailyAddon = _promptDaily?.trim() ?? '';
    final addonInfo = AppLocalizations.of(context).promptAddonGeneralInfo;
    final suggestionSegment = AppLocalizations.of(
      context,
    ).promptAddonSuggestionSegment;
    final suggestionMerge = AppLocalizations.of(
      context,
    ).promptAddonSuggestionMerge;
    final suggestionDaily = AppLocalizations.of(
      context,
    ).promptAddonSuggestionDaily;

    return UICard(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 折叠标题（点击展开/收起）
          GestureDetector(
            onTap: () => _setState(() {
              _promptExpanded = !_promptExpanded;
            }),
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).promptManagerTitle,
                        style: titleStyle,
                      ),
                      const SizedBox(height: 2),
                      Text(_buildPromptSummary(), style: hintStyle),
                    ],
                  ),
                ),
                Icon(_promptExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          if (_promptExpanded) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              AppLocalizations.of(context).promptManagerHint,
              style: hintStyle,
            ),
            const SizedBox(height: AppTheme.spacing3),

            // 普通事件提示词
            buildSection(
              label: AppLocalizations.of(context).normalEventPromptLabel,
              currentAddon: segAddon,
              infoText: addonInfo,
              suggestion: suggestionSegment,
              editing: _editingPromptSegment,
              controller: _promptSegmentController,
              onEditToggle: () => _setState(
                () => _editingPromptSegment = !_editingPromptSegment,
              ),
              onSave: _savePromptSegment,
              onReset: _resetPromptSegment,
              saving: _savingPromptSegment,
            ),

            // 合并事件提示词
            buildSection(
              label: AppLocalizations.of(context).mergeEventPromptLabel,
              currentAddon: mergeAddon,
              infoText: addonInfo,
              suggestion: suggestionMerge,
              editing: _editingPromptMerge,
              controller: _promptMergeController,
              onEditToggle: () =>
                  _setState(() => _editingPromptMerge = !_editingPromptMerge),
              onSave: _savePromptMerge,
              onReset: _resetPromptMerge,
              saving: _savingPromptMerge,
            ),
            // 每日总结提示词
            buildSection(
              label: AppLocalizations.of(context).dailySummaryPromptLabel,
              currentAddon: dailyAddon,
              infoText: addonInfo,
              suggestion: suggestionDaily,
              editing: _editingPromptDaily,
              controller: _promptDailyController,
              onEditToggle: () =>
                  _setState(() => _editingPromptDaily = !_editingPromptDaily),
              onSave: _savePromptDaily,
              onReset: _resetPromptDaily,
              saving: _savingPromptDaily,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _savePromptSegment() async {
    if (_savingPromptSegment) return;
    _setState(() => _savingPromptSegment = true);
    try {
      final text = _promptSegmentController.text.trim();
      final normalized = text.isEmpty ? null : text;
      await _settings.setPromptSegment(normalized);
      if (mounted) {
        _setState(() {
          _promptSegment = normalized;
          _promptSegmentController.text = normalized ?? '';
          _editingPromptSegment = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).savedNormalPromptToast,
        );
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
    } finally {
      if (mounted) _setState(() => _savingPromptSegment = false);
    }
  }

  Future<void> _resetPromptSegment() async {
    if (_savingPromptSegment) return;
    _setState(() => _savingPromptSegment = true);
    try {
      await _settings.setPromptSegment(null);
      if (mounted) {
        _setState(() {
          _promptSegment = null;
          _promptSegmentController.text = '';
          _editingPromptSegment = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).resetToDefaultPromptToast,
        );
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).resetFailedWithError(e.toString()),
        );
    } finally {
      if (mounted) _setState(() => _savingPromptSegment = false);
    }
  }

  Future<void> _savePromptMerge() async {
    if (_savingPromptMerge) return;
    _setState(() => _savingPromptMerge = true);
    try {
      final text = _promptMergeController.text.trim();
      final normalized = text.isEmpty ? null : text;
      await _settings.setPromptMerge(normalized);
      if (mounted) {
        _setState(() {
          _promptMerge = normalized;
          _promptMergeController.text = normalized ?? '';
          _editingPromptMerge = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).savedMergePromptToast,
        );
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
    } finally {
      if (mounted) _setState(() => _savingPromptMerge = false);
    }
  }

  Future<void> _resetPromptMerge() async {
    if (_savingPromptMerge) return;
    _setState(() => _savingPromptMerge = true);
    try {
      await _settings.setPromptMerge(null);
      if (mounted) {
        _setState(() {
          _promptMerge = null;
          _promptMergeController.text = '';
          _editingPromptMerge = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).resetToDefaultPromptToast,
        );
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).resetFailedWithError(e.toString()),
        );
    } finally {
      if (mounted) _setState(() => _savingPromptMerge = false);
    }
  }

  Future<void> _savePromptDaily() async {
    if (_savingPromptDaily) return;
    _setState(() => _savingPromptDaily = true);
    try {
      final text = _promptDailyController.text.trim();
      final normalized = text.isEmpty ? null : text;
      await _settings.setPromptDaily(normalized);
      if (mounted) {
        _setState(() {
          _promptDaily = normalized;
          _promptDailyController.text = normalized ?? '';
          _editingPromptDaily = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).savedDailyPromptToast,
        );
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
    } finally {
      if (mounted) _setState(() => _savingPromptDaily = false);
    }
  }

  Future<void> _resetPromptDaily() async {
    if (_savingPromptDaily) return;
    _setState(() => _savingPromptDaily = true);
    try {
      await _settings.setPromptDaily(null);
      if (mounted) {
        _setState(() {
          _promptDaily = null;
          _promptDailyController.text = '';
          _editingPromptDaily = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).resetToDefaultPromptToast,
        );
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).resetFailedWithError(e.toString()),
        );
    } finally {
      if (mounted) _setState(() => _savingPromptDaily = false);
    }
  }

  Future<void> _clearHistory() async {
    try {
      await _chat.clearConversation();
      if (!mounted) return;
      _setState(() {
        _messages = <AIMessage>[];
        _attachmentsByIndex.clear();
        _evidenceResolvedByMsgKey.clear();
        _evidenceResolveFutures.clear();
        _reasoningByIndex.clear();
        _reasoningDurationByIndex.clear();
        _currentAssistantIndex = null;
        _inStreaming = false;
        _clarifyState = null;
      });
      UINotifier.success(context, AppLocalizations.of(context).clearSuccess);
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).clearFailedWithError(e.toString()),
      );
    }
  }

  // 自动滚动到底部（在下一帧执行，避免布局未完成）
  void _scrollToBottom({bool animated = true}) {
    final c = _chatScrollController;
    if (!c.hasClients) return;
    final pos = c.position.maxScrollExtent;
    if (animated) {
      c.animateTo(
        pos,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    } else {
      c.jumpTo(pos);
    }
  }

  void _scheduleAutoScroll() {
    // 仅当粘在底部时，才允许自动滚动；用户上滑后暂停
    if (!_stickToBottom) return;

    final now = DateTime.now();
    final last = _lastAutoScrollTime;
    final elapsed = (last == null)
        ? const Duration(days: 1)
        : now.difference(last);
    if (elapsed.inMilliseconds >= _AISettingsPageState._autoScrollThrottleMs) {
      _lastAutoScrollTime = now;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_stickToBottom) return;
        _scrollToBottom(animated: false);
      });
    } else if (!_autoScrollPending) {
      _autoScrollPending = true;
      final delay = Duration(
        milliseconds:
            _AISettingsPageState._autoScrollThrottleMs - elapsed.inMilliseconds,
      );
      Future.delayed(delay, () {
        _autoScrollPending = false;
        if (!mounted || !_stickToBottom) return;
        _lastAutoScrollTime = DateTime.now();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_stickToBottom) return;
          _scrollToBottom(animated: false);
        });
      });
    }
  }

  void _scheduleReasoningPreviewScroll() {
    // 仅处理底部思考面板的自动滚动，气泡内的滚动由 ReasoningCard 自己处理
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_reasoningPanelScrollController.hasClients) {
        _reasoningPanelScrollController.animateTo(
          _reasoningPanelScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _startDots() {
    // 迁移为 ReasoningCard 内部自管理省略号动画，避免整页 setState 重建
    // 这里不再执行任何刷新逻辑，仅确保先前计时器被取消
    _dotsTimer?.cancel();
    _dotsTimer = null;
  }

  void _stopDots() {
    _dotsTimer?.cancel();
    _dotsTimer = null;
  }

  Future<void> _enqueueChatHistorySave(List<AIMessage> messages) {
    final Future<void> next = _chatHistorySaveChain.then((_) async {
      try {
        await _settings.saveChatHistoryActive(messages);
      } catch (_) {}
    });
    // Keep the chain alive even if a write fails.
    _chatHistorySaveChain = next.catchError((_) {});
    return _chatHistorySaveChain;
  }

  void _markInFlightHistoryDirty() {
    if (!_inStreaming) return;
    _inFlightHistoryDirty = true;
    if (_inFlightSaveTimer != null) return;

    // Throttle: write at most once per 2s while streaming/tool-loop is in flight.
    _inFlightSaveTimer = Timer(const Duration(seconds: 2), () {
      _inFlightSaveTimer = null;
      if (!_inStreaming || !_inFlightHistoryDirty) return;
      _inFlightHistoryDirty = false;
      unawaited(() async {
        try {
          final List<AIMessage> merged = _mergeReasoningForPersistence(
            List<AIMessage>.from(_messages),
          );
          await _enqueueChatHistorySave(merged);
        } catch (_) {}
        if (_inStreaming && _inFlightHistoryDirty) {
          _markInFlightHistoryDirty();
        }
      }());
    });
  }

  void _stopInFlightHistoryPersistence() {
    _inFlightSaveTimer?.cancel();
    _inFlightSaveTimer = null;
    _inFlightHistoryDirty = false;
  }

  bool _isZhLocale() {
    try {
      return Localizations.localeOf(
        context,
      ).languageCode.toLowerCase().startsWith('zh');
    } catch (_) {
      return true;
    }
  }

  String _clipOneLine(String s, int maxLen) {
    final String t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return '';
    return t.length <= maxLen ? t : (t.substring(0, maxLen) + '…');
  }

  void _appendAgentLog(
    String message, {
    int? assistantIndex,
    bool bullet = true,
  }) {
    if (!mounted) return;
    final int? idx = assistantIndex ?? _currentAssistantIndex;
    if (idx == null || idx < 0 || idx >= _messages.length) return;
    final String t = message.trim();
    if (t.isEmpty) return;
    final String line = (bullet ? '- ' : '') + t;
    _setState(() {
      _thinkingText += line + '\n';
      _reasoningByIndex[idx] = (_reasoningByIndex[idx] ?? '') + line + '\n';
    });
    _scheduleAutoScroll();
    _scheduleReasoningPreviewScroll();
    _markInFlightHistoryDirty();
  }

  String _formatIntentSubtitle(IntentResult intent) {
    // Only show the intent summary; hide date/time range noise.
    return intent.intentSummary.trim();
  }

  String _truncateConversationTitle(String text) {
    final String t = text.trim();
    if (t.isEmpty) return '';
    if (t.length <= 30) return t;
    return t.substring(0, 30) + '...';
  }

  void _renameActiveConversationTo(String titleSource) {
    final String t = _truncateConversationTitle(titleSource);
    if (t.isEmpty) return;
    unawaited(() async {
      try {
        final String cid = await _settings.getActiveConversationCid();
        if (cid.trim().isEmpty) return;
        await _settings.renameConversation(cid.trim(), t);
      } catch (_) {}
    }());
  }

  void _handleAiUiEvent(int assistantIdx, Map<String, dynamic> payload) {
    final String type = (payload['type'] as String?)?.trim() ?? '';
    if (type.isEmpty) return;

    if (type == 'tool_batch_begin') {
      final List<dynamic> tools = (payload['tools'] as List?) ?? const [];
      final _ThinkingBlock block = _ensureThinkingBlock(assistantIdx);
      final String title = _isZhLocale() ? '工具调用' : 'Tools';
      final _ThinkingEvent toolsEvent = _upsertEvent(
        block,
        type: _ThinkingEventType.tools,
        title: title,
        icon: Icons.auto_awesome_outlined,
        tools: <_ThinkingToolChip>[],
      );

      final Set<String> seenInBatch = <String>{};
      for (final t in tools) {
        if (t is! Map) continue;
        final Map<String, dynamic> m = Map<String, dynamic>.from(t);
        final String callId = (m['call_id'] as String?)?.trim() ?? '';
        final String toolName = (m['tool_name'] as String?)?.trim() ?? '';
        final String label = (m['label'] as String?)?.trim() ?? toolName.trim();
        if (callId.isEmpty || toolName.isEmpty) continue;
        seenInBatch.add(callId);

        _ThinkingToolChip? existing;
        for (final c in toolsEvent.tools) {
          if (c.callId == callId) {
            existing = c;
            break;
          }
        }
        if (existing != null) {
          existing.active = true;
          existing.resultSummary = null;
        } else {
          toolsEvent.tools.add(
            _ThinkingToolChip(
              callId: callId,
              toolName: toolName,
              label: label.isEmpty ? toolName : label,
              active: true,
            ),
          );
        }
      }

      // Only shimmer the tools that are currently in flight.
      for (final c in toolsEvent.tools) {
        if (!seenInBatch.contains(c.callId)) c.active = false;
      }
      return;
    }

    if (type == 'tool_call_end') {
      final String callId = (payload['call_id'] as String?)?.trim() ?? '';
      if (callId.isEmpty) return;
      final String resultSummary =
          (payload['result_summary'] as String?)?.trim() ?? '';

      final List<_ThinkingBlock> blocks =
          _thinkingBlocksByIndex[assistantIdx] ?? const <_ThinkingBlock>[];
      for (int bi = blocks.length - 1; bi >= 0; bi--) {
        final b = blocks[bi];
        for (final e in b.events) {
          if (e.type != _ThinkingEventType.tools) continue;
          for (final chip in e.tools) {
            if (chip.callId != callId) continue;
            chip.active = false;
            if (resultSummary.isNotEmpty) chip.resultSummary = resultSummary;
            return;
          }
        }
      }
      return;
    }
  }

  void _finishActiveThinkingBlock(int assistantIdx) {
    final List<_ThinkingBlock>? blocks = _thinkingBlocksByIndex[assistantIdx];
    if (blocks == null || blocks.isEmpty) return;
    final _ThinkingBlock last = blocks.last;
    last.finishedAt ??= DateTime.now();

    // Persist a stable "thinking duration" for this assistant message.
    // We only record it once (the first time we finish a thinking block),
    // so later tool loops won't overwrite the original value.
    if (_reasoningDurationByIndex[assistantIdx] == null &&
        assistantIdx >= 0 &&
        assistantIdx < _messages.length) {
      final Duration d = last.finishedAt!.difference(
        _messages[assistantIdx].createdAt,
      );
      if (d.inMilliseconds > 0) _reasoningDurationByIndex[assistantIdx] = d;
    }
  }

  void _appendContentChunk(int assistantIdx, String chunk) {
    final List<String> segs = _contentSegmentsByIndex.putIfAbsent(
      assistantIdx,
      () => <String>[],
    );
    final bool startNew =
        (_nextContentStartsNewSegmentByIndex[assistantIdx] ?? segs.isEmpty);
    if (startNew) {
      segs.add(chunk);
      _nextContentStartsNewSegmentByIndex[assistantIdx] = false;
    } else {
      segs[segs.length - 1] = segs.last + chunk;
    }
  }

  String _stripMarkdownCodeFences(String text) {
    String t = text.trim();
    if (!t.startsWith('```')) return t;
    t = t.replaceFirst(RegExp(r'^```[a-zA-Z0-9_-]*\s*'), '');
    t = t.replaceFirst(RegExp(r'\s*```$'), '');
    return t.trim();
  }

  Map<String, dynamic>? _tryParseJsonMap(String text) {
    String t = _stripMarkdownCodeFences(text);
    if (t.isEmpty) return null;
    try {
      final dynamic v = jsonDecode(t);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    final int s = t.indexOf('{');
    final int e = t.lastIndexOf('}');
    if (s >= 0 && e > s) {
      final String sub = t.substring(s, e + 1);
      try {
        final dynamic v = jsonDecode(sub);
        if (v is Map) return Map<String, dynamic>.from(v);
      } catch (_) {}
    }
    return null;
  }

  bool _isCancelMessage(String text) {
    final String t = text.trim();
    if (t.isEmpty) return false;
    const List<String> keys = <String>[
      '取消',
      '算了',
      '不用了',
      '停止',
      '结束',
      '退出',
      '不查了',
      'cancel',
      'stop',
      'quit',
    ];
    final String low = t.toLowerCase();
    for (final k in keys) {
      if (k.length <= 3) {
        if (t == k || low == k) return true;
      } else {
        if (t.contains(k) || low.contains(k)) return true;
      }
    }
    return false;
  }

  bool _intentAllowsNoTimeRange(IntentResult intent) {
    final String v = intent.intent.trim().toLowerCase();
    if (v == 'other' || v == 'chat' || v == 'general') return true;
    final String ec = (intent.errorCode ?? '').trim().toUpperCase();
    if (ec == 'UNSUPPORTED') return true;
    return false;
  }

  IntentResult _applyDefaultTimeRange(IntentResult intent, {int days = 30}) {
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    int startMs = nowMs - Duration(days: days).inMilliseconds;
    if (startMs < 0) startMs = 0;
    return IntentResult(
      intent: intent.intent,
      intentSummary: intent.intentSummary,
      startMs: startMs,
      endMs: nowMs,
      timezone: intent.timezone,
      apps: intent.apps,
      keywords: intent.keywords,
      sqlFill: intent.sqlFill,
      skipContext: false,
      contextAction: 'refresh',
      userWantsProceed: true,
    );
  }

  String _fmtWindowShort(int startMs, int endMs) {
    if (startMs <= 0 || endMs <= 0) return '';
    final DateTime ds = DateTime.fromMillisecondsSinceEpoch(startMs);
    final DateTime de = DateTime.fromMillisecondsSinceEpoch(endMs);
    final bool sameDay =
        ds.year == de.year && ds.month == de.month && ds.day == de.day;
    if (sameDay) {
      return '${DateFormat('MM-dd HH:mm').format(ds)}–${DateFormat('HH:mm').format(de)}';
    }
    return '${DateFormat('MM-dd HH:mm').format(ds)}–${DateFormat('MM-dd HH:mm').format(de)}';
  }

  String _composeClarifyIntentInput(_ClarifyState state) {
    final String q = state.originalQuestion.trim();
    if (state.supplements.isEmpty) return q;
    final StringBuffer sb = StringBuffer();
    if (q.isNotEmpty) sb.writeln(q);
    sb.writeln();
    sb.writeln('用户补充信息：');
    for (final s in state.supplements) {
      final String t = s.trim();
      if (t.isEmpty) continue;
      sb.writeln('- ' + t);
    }
    return sb.toString().trim();
  }

  String _composeFinalUserQuestionFromClarify(_ClarifyState state) {
    final String q = state.originalQuestion.trim();
    if (state.supplements.isEmpty) return q.isEmpty ? '' : q;
    final StringBuffer sb = StringBuffer();
    if (q.isNotEmpty) sb.writeln(q);
    sb.writeln();
    sb.writeln('补充信息：');
    for (final s in state.supplements) {
      final String t = s.trim();
      if (t.isEmpty) continue;
      sb.writeln('- ' + t);
    }
    return sb.toString().trim();
  }

  bool _isOverlyBroadQuery(
    IntentResult intent,
    String userText, {
    _ClarifyState? clarify,
  }) {
    if (!intent.hasValidRange) return false;
    if (intent.apps.isNotEmpty) return false;
    final int spanMs = intent.endMs - intent.startMs;
    if (spanMs <= 0) return false;
    final Duration span = Duration(milliseconds: spanMs);
    if (span <= const Duration(days: 7)) return false;

    const List<String> summaryHints = <String>[
      '总结',
      '回顾',
      '概览',
      '汇总',
      '统计',
      '复盘',
      '周总结',
      '月总结',
      '时间线',
    ];
    for (final k in summaryHints) {
      if (userText.contains(k)) return false;
    }

    // 语句较长且细节多，允许直接查
    if (userText.trim().length >= 28) return false;

    return true;
  }

  Future<List<_ProbeCandidate>> _probeCandidates({
    required String query,
    _ClarifyState? state,
    int limit = 6,
  }) async {
    final String q = query.trim();
    if (q.isEmpty) return const <_ProbeCandidate>[];

    final int now = DateTime.now().millisecondsSinceEpoch;
    final int endMs = state?.hintEndMs ?? now;
    final int fetchLimit = (limit <= 0 || limit > 12) ? 6 : limit;

    Future<List<_ProbeCandidate>?> searchInRange(int startMs, int endMs) async {
      // 1) 优先在 segment_results_fts 中找候选
      try {
        final List<Map<String, dynamic>> segHits = await ScreenshotDatabase
            .instance
            .searchSegmentsByText(
              q,
              limit: fetchLimit,
              offset: 0,
              startMillis: startMs,
              endMillis: endMs,
            );
        if (segHits.isNotEmpty) {
          int idx = 0;
          return segHits
              .map((m) {
                idx += 1;
                final int s = (m['start_time'] as int?) ?? 0;
                final int e = (m['end_time'] as int?) ?? 0;
                final String window = _fmtWindowShort(s, e);
                final String raw =
                    (m['output_text'] as String?)?.trim().isNotEmpty == true
                    ? (m['output_text'] as String).trim()
                    : ((m['structured_json'] as String?)?.trim() ?? '');
                final String summary = _clipOneLine(raw, 80);
                return _ProbeCandidate(
                  index: idx,
                  startMs: s,
                  endMs: e,
                  kind: _ProbeKind.segments,
                  title: window.isEmpty ? '候选 $idx' : window,
                  subtitle: summary.isEmpty ? '（匹配到段落，但缺少摘要文本）' : summary,
                );
              })
              .toList(growable: false);
        }
      } catch (_) {}

      // 2) 回退 OCR 搜索（按 capture_time 取附近时间窗）
      try {
        final List<ScreenshotRecord> shots = await ScreenshotDatabase.instance
            .searchScreenshotsByOcr(
              q,
              limit: fetchLimit,
              offset: 0,
              startMillis: startMs,
              endMillis: endMs,
            );
        if (shots.isNotEmpty) {
          int idx = 0;
          return shots
              .map((r) {
                idx += 1;
                final int t = r.captureTime.millisecondsSinceEpoch;
                final int s = (t - const Duration(minutes: 10).inMilliseconds);
                final int e = (t + const Duration(minutes: 10).inMilliseconds);
                final String title =
                    '${DateFormat('MM-dd HH:mm').format(r.captureTime)} ${r.appName}';
                final String subtitle = _clipOneLine(
                  r.ocrText ?? r.pageUrl ?? '',
                  80,
                );
                return _ProbeCandidate(
                  index: idx,
                  startMs: s < 0 ? 0 : s,
                  endMs: e,
                  kind: _ProbeKind.ocr,
                  title: title,
                  subtitle: subtitle.isEmpty ? '（OCR 命中）' : subtitle,
                );
              })
              .toList(growable: false);
        }
      } catch (_) {}

      return null;
    }

    // 缺时间时：允许逐步扩大窗口，提高“先找找看”的命中率
    if (state?.hintStartMs != null) {
      final int startMs = state!.hintStartMs!;
      final List<_ProbeCandidate>? res = await searchInRange(startMs, endMs);
      return res ?? const <_ProbeCandidate>[];
    }

    final List<int> windowsDays = state?.reason == _ClarifyReason.missingTime
        ? const <int>[30, 180, 365]
        : const <int>[30];
    for (final days in windowsDays) {
      final int startMsRaw = endMs - Duration(days: days).inMilliseconds;
      final int startMs = startMsRaw < 0 ? 0 : startMsRaw;
      final List<_ProbeCandidate>? res = await searchInRange(startMs, endMs);
      if (res != null && res.isNotEmpty) return res;
    }

    return const <_ProbeCandidate>[];
  }

  int? _parsePickIndex(String text, int max) {
    final String t = text.trim();
    if (t.isEmpty) return null;
    final RegExp m = RegExp(r'^(\d{1,2})$');
    final Match? mm = m.firstMatch(t);
    if (mm == null) return null;
    final int n = int.tryParse(mm.group(1) ?? '') ?? 0;
    if (n <= 0 || n > max) return null;
    return n;
  }

  String _composeProbePickLlmPrompt(
    _ClarifyState state,
    List<_ProbeCandidate> cands,
  ) {
    final bool zh = _isZhLocale();
    final String q = state.originalQuestion.trim();
    final String supplements = state.supplements
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => '- $s')
        .join('\n');
    if (cands.isEmpty) {
      if (zh) {
        return [
          '你是 Screen Memo 的对话助手，正在帮助用户在截图/屏幕记录里定位信息。',
          '你刚做了一次快速检索，但没有找到明显候选。',
          '',
          '上下文：',
          '- 用户原问题：${q.isEmpty ? '（空）' : q}',
          '- 已补充线索：${supplements.isEmpty ? '（无）' : '\n$supplements'}',
          '',
          '请生成一条要发给用户的消息：',
          '- 语气温和自然，不反问、不阴阳怪气、不责备',
          '- 不要使用固定模板套话，尽量结合用户提问自然表达',
          '- 不要说“现在开始搜索/正在深度搜索”等；你已经做完快速检索，只需说明“没找到明显候选”',
          '- 不要编造查找结果，不要给最终答案',
          '- 引导用户只补充 1 条最关键线索（时间范围 或 关键词/应用/场景）',
          '- 允许用户回复「取消」结束本次查找',
          '- 只输出消息正文（不要标题/JSON/代码块）',
        ].join('\n');
      }
      return [
        'You are a Screen Memo assistant helping users locate info from screenshots/records.',
        'You just ran a quick scan but found no strong candidates.',
        '',
        'Context:',
        '- User question: ${q.isEmpty ? '(empty)' : q}',
        '- Collected clues: ${supplements.isEmpty ? '(none)' : '\n$supplements'}',
        '',
        'Write ONE message to the user:',
        '- Warm, polite; no rhetorical questions, no sarcasm, no blame.',
        '- Avoid canned/template-like phrasing; make it feel specific to the user question.',
        '- Do NOT say you are \"starting a search now\"; you already finished a quick scan and found no strong candidates.',
        '- Do not fabricate results; do not answer yet.',
        '- Ask the user for ONE key clue (time window OR keyword/app/scenario).',
        '- Allow user to reply \"cancel\" to stop.',
        '- Output only the message text (no title/JSON/code fences).',
      ].join('\n');
    }

    if (zh) {
      final List<Map<String, String>> candList = cands
          .map(
            (c) => <String, String>{
              'index': c.index.toString(),
              'time': _fmtWindowShort(c.startMs, c.endMs),
              'kind': c.kind.name,
              'title': _clipOneLine(c.title, 80),
              'subtitle': _clipOneLine(c.subtitle, 120),
            },
          )
          .toList();
      return [
        '你是 Screen Memo 的对话助手，正在帮助用户在截图/屏幕记录里定位信息。',
        '你已经做了快速检索，下面给你“候选输入”（顺序固定，不要增删改，不要虚构信息）：',
        '',
        '上下文：',
        '- 用户原问题：${q.isEmpty ? '（空）' : q}',
        '- 已补充线索：${supplements.isEmpty ? '（无）' : '\n$supplements'}',
        '- 候选数量：${cands.length}（items 必须同样数量）',
        '',
        '候选输入(JSON)：',
        jsonEncode(candList),
        '',
        '请只输出一个 JSON 对象（不要标题/解释/代码块），结构如下：',
        '{"intro":"...","items":["..."],"outro":"..."}',
        '',
        '要求：',
        '- items 必须是数组，长度必须等于候选数量，并且顺序与候选输入一致',
        '- items 里每个元素是一条候选描述（不要带序号；序号由 App 自动添加）',
        '- intro/outro 是面向用户的自然表达：温和、不反问、不阴阳怪气、不责备，不要使用固定模板套话',
        '- 不要编造候选信息，不要给最终答案',
        '- outro 里引导用户回复序号选择（如 2），或回复「都不是」并补充 1 条新线索；也允许回复「取消」结束',
        '- 整体语言使用中文',
        '',
      ].join('\n');
    }

    final List<Map<String, String>> candList = cands
        .map(
          (c) => <String, String>{
            'index': c.index.toString(),
            'time': _fmtWindowShort(c.startMs, c.endMs),
            'kind': c.kind.name,
            'title': _clipOneLine(c.title, 80),
            'subtitle': _clipOneLine(c.subtitle, 120),
          },
        )
        .toList();
    return [
      'You are a Screen Memo assistant helping users locate info from screenshots/records.',
      'You already ran a quick scan. Here are the candidates input (fixed order; do not add/remove; do not invent).',
      '',
      'Context:',
      '- User question: ${q.isEmpty ? '(empty)' : q}',
      '- Collected clues: ${supplements.isEmpty ? '(none)' : '\n$supplements'}',
      '- Candidate count: ${cands.length} (items must match this count)',
      '',
      'Candidates input (JSON):',
      jsonEncode(candList),
      '',
      'Output ONLY one JSON object (no title/explanations/code fences) with this structure:',
      '{"intro":"...","items":["..."],"outro":"..."}',
      '',
      'Requirements:',
      '- items must be an array with EXACTLY the same length as the candidate count and in the same order.',
      '- Each items[i] is a user-facing description for candidate i (do NOT include numbering; the app will add numbers).',
      '- intro/outro should be warm and natural (no rhetorical questions, no sarcasm, no blame; avoid canned phrasing).',
      '- Do not fabricate candidate info; do not answer yet.',
      '- In outro, ask the user to reply with the number (e.g., 2), or reply \"none\" with ONE more clue; allow \"cancel\" to stop.',
      '- Use English.',
      '',
    ].join('\n');
  }

  String _buildProbePickMessageFallback(
    _ClarifyState state,
    List<_ProbeCandidate> cands,
  ) {
    final bool zh = _isZhLocale();
    if (cands.isEmpty) {
      if (zh) {
        return [
          '我先根据现有线索做了一次小范围查找，但没有找到明显候选。',
          '你可以再补充其中一条线索：',
          '1) 更具体的日期/时间段',
          '2) App 名 / 关键词 / 标题里的词',
          '（也可以回复「取消」结束本次查找）',
        ].join('\n');
      }
      return [
        'I tried a quick scan but found no strong candidates.',
        'Please add ONE clue: time window OR app/keyword.',
        '(Or reply \"cancel\" to stop.)',
      ].join('\n');
    }

    final List<String> lines = <String>[];
    if (zh) {
      lines.add('我先根据你给的线索做了一次小范围查找，找到了这些可能的候选：');
      for (final c in cands) {
        lines.add('${c.index}) ${c.title}');
        if (c.subtitle.trim().isNotEmpty) {
          lines.add('   - ${c.subtitle}');
        }
      }
      lines.add('');
      lines.add('你可以回复序号（如 2），或回复「都不是」并补充一条新线索。');
      lines.add('（也可以回复「取消」结束本次查找）');
      return lines.join('\n');
    }

    lines.add('I did a quick scan and found these candidates:');
    for (final c in cands) {
      lines.add('${c.index}) ${c.title}');
      if (c.subtitle.trim().isNotEmpty) lines.add('   - ${c.subtitle}');
    }
    lines.add('');
    lines.add(
      'Reply with the number (e.g., 2), or reply \"none\" with one more clue.',
    );
    lines.add('(Or reply \"cancel\" to stop.)');
    return lines.join('\n');
  }

  Future<String> _buildProbePickMessage(
    _ClarifyState state,
    List<_ProbeCandidate> cands,
  ) async {
    if (cands.isEmpty) {
      try {
        final String prompt = _composeProbePickLlmPrompt(state, cands);
        final AIMessage resp = await _chat.sendMessageOneShot(
          prompt,
          context: 'chat',
          timeout: const Duration(seconds: 25),
        );
        final String t = resp.content.trim();
        if (t.isNotEmpty) return t;
      } catch (_) {}
      return _buildProbePickMessageFallback(state, cands);
    }

    String lastRaw = '';
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final bool zh = _isZhLocale();
        final String retryHint = zh
            ? '上一条输出不符合要求（必须是严格 JSON，且 items 数量匹配）。请你只输出符合结构的 JSON，不要任何多余文字。'
            : 'Your previous output is invalid (must be strict JSON and items length must match). Please output ONLY valid JSON with the required structure. No extra text.';
        final String prevLabel = zh
            ? '上次输出(供参考)：'
            : 'Previous output (for reference):';
        final String prompt = attempt == 0
            ? _composeProbePickLlmPrompt(state, cands)
            : [
                _composeProbePickLlmPrompt(state, cands),
                '',
                retryHint,
                prevLabel,
                _clipOneLine(lastRaw, 800),
              ].join('\n');
        final AIMessage resp = await _chat.sendMessageOneShot(
          prompt,
          context: 'chat',
          timeout: const Duration(seconds: 25),
        );
        final String raw = resp.content.trim();
        lastRaw = raw;
        if (raw.isEmpty) continue;

        final Map<String, dynamic>? obj = _tryParseJsonMap(raw);
        if (obj == null) continue;
        final dynamic itemsDyn = obj['items'];
        if (itemsDyn is! List || itemsDyn.length != cands.length) continue;

        final String intro = (obj['intro'] as String? ?? '').trim();
        final String outro = (obj['outro'] as String? ?? '').trim();
        final List<String> items = itemsDyn
            .map((e) => e.toString().trim())
            .toList();

        final List<String> lines = <String>[];
        if (intro.isNotEmpty) lines.add(intro);
        for (int i = 0; i < items.length; i++) {
          final String it = items[i].trim();
          final String fallback = _clipOneLine(
            [
              cands[i].title,
              cands[i].subtitle,
            ].where((s) => s.trim().isNotEmpty).join(' · '),
            120,
          );
          lines.add('${i + 1}) ${it.isEmpty ? fallback : it}');
        }
        if (outro.isNotEmpty) {
          lines.add('');
          lines.add(outro);
        }
        final String msg = lines.join('\n').trim();
        if (msg.isNotEmpty) return msg;
      } catch (_) {
        continue;
      }
    }

    return _buildProbePickMessageFallback(state, cands);
  }
}
