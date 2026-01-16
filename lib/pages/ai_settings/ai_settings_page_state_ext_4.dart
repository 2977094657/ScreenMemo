part of '../ai_settings_page.dart';

extension _AISettingsPageStateExt4 on _AISettingsPageState {
  Widget _buildChatList() {
    if (_messages.isEmpty) {
      final l10n = AppLocalizations.of(context);
      try {
        FlutterLogger.nativeInfo(
          'UI',
          'ChatEmpty: assistant=1 useGradientGlow=1',
        );
      } catch (_) {}
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildMagicIcon(size: 40, withGlow: false),
            const SizedBox(height: AppTheme.spacing4),
            Text(
              l10n.aiEmptySelfTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacing2),
            Text(
              l10n.aiEmptySelfSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final Widget list = ListView.builder(
      controller: _chatScrollController,
      itemCount: _messages.length,
      reverse: false,
      // 仅渲染视口上下各一屏，减少离屏图片的构建与解码
      cacheExtent: MediaQuery.of(context).size.height,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      addSemanticIndexes: false,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacing4,
        0,
        AppTheme.spacing4,
        AppTheme.spacing2,
      ),
      itemBuilder: (context, index) {
        final m = _messages[index];
        final isUser = m.role == 'user';
        final isError =
            m.role == 'error' ||
            m.content.contains('"error"') ||
            m.content.toLowerCase().contains('server_error') ||
            m.content.toLowerCase().contains('request failed') ||
            m.content.toLowerCase().contains('no candidates returned');
        final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
        final bg = isUser
            ? Theme.of(context).colorScheme.primary
            : isError
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.surfaceVariant;
        final fg = isUser
            ? Theme.of(context).colorScheme.onPrimary
            : isError
            ? Theme.of(context).colorScheme.onErrorContainer
            : Theme.of(context).colorScheme.onSurface;

        // 正文渲染：流式期间对当前消息使用轻量文本，完成后再进行 Markdown 解析
        final bool isCurrentStreaming =
            _inStreaming && (_currentAssistantIndex == index);
        // 隐藏 system 消息（用于保存最终提示但不显示）
        final bool isSystem = m.role == 'system';
        if (isSystem) {
          return const SizedBox.shrink();
        }

        final bool isAssistant = !isUser && !isError;
        if (isAssistant) {
          final List<_ThinkingBlock> blocks = _blocksForMessageIndex(index);
          final List<String> segs = _contentSegmentsForMessageIndex(index);
          final int n = (blocks.length > segs.length)
              ? blocks.length
              : segs.length;

          final List<Widget> children = <Widget>[];
          for (int i = 0; i < n; i++) {
            if (i < blocks.length) {
              final b = blocks[i];
              // Only show legacy fallback reasoning while the block is still loading.
              // For completed turns, prefer the structured timeline events; avoid
              // dumping internal logs on restore.
              final String? fallbackReasoning = (i == 0 && b.isLoading)
                  ? (_reasoningByIndex[index] ?? m.reasoningContent)
                  : null;
              children.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                  child: _ThinkingTimelineCard(
                    key: ValueKey(
                      'think:${m.createdAt.millisecondsSinceEpoch}:$i',
                    ),
                    createdAt: b.createdAt,
                    finishedAt: b.finishedAt,
                    events: b.events,
                    fallbackReasoning: fallbackReasoning,
                    autoCloseOnFinish: true,
                  ),
                ),
              );
            }
            if (i < segs.length) {
              final String seg = segs[i];
              if (seg.trim().isNotEmpty) {
                children.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                    child: _buildMarkdownForMessage(
                      message: m,
                      messageIndex: index,
                      content: seg,
                      fg: fg,
                      isCurrentStreaming: isCurrentStreaming,
                    ),
                  ),
                );
              }
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.zero,
                child: Text(
                  DateFormat('HH:mm:ss').format(
                    (m.role == 'assistant' &&
                            _reasoningDurationByIndex[index] != null)
                        ? m.createdAt.add(_reasoningDurationByIndex[index]!)
                        : m.createdAt,
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
              Padding(
                padding: EdgeInsets.zero,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () async {
                        try {
                          await Clipboard.setData(
                            ClipboardData(
                              text: _buildMessageCopyText(m, index),
                            ),
                          );
                          if (mounted)
                            UINotifier.success(
                              context,
                              AppLocalizations.of(context).copySuccess,
                            );
                        } catch (_) {}
                      },
                      constraints: const BoxConstraints.tightFor(
                        width: 24,
                        height: 24,
                      ),
                      padding: const EdgeInsets.all(0),
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                      splashRadius: 16,
                      iconSize: 16,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: AppLocalizations.of(context).actionCopy,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ],
          );
        }

        final Widget mdWidget = _buildMarkdownForMessage(
          message: m,
          messageIndex: index,
          content: m.content,
          fg: fg,
          isCurrentStreaming: isCurrentStreaming,
        ); /* Legacy inline markdown builder:
            (isCurrentStreaming && !_renderImagesDuringStreaming)
            // 流式期间渲染轻量文本，避免高频 Markdown 重建
            ? SelectableText(
                m.content,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: fg),
              )
            : (() {
                // 非流式：构建 Markdown 与 evidence 解析
                final String preprocessedMd = preprocessForChatMarkdown(
                  m.content,
                );
                final Map<String, String> evidenceNameToPath =
                    <String, String>{};
                final List<EvidenceImageAttachment> atts =
                    _attachmentsByIndex[index] ??
                    const <EvidenceImageAttachment>[];
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
                  evidenceNameToPath: evidenceNameToPath,
                  orderedEvidencePaths: orderedEvidencePathsFromAtts,
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

                // 流式期间（且允许渲染图片）尽量只用预加载附件映射，避免高频重建触发扫库
                if (isCurrentStreaming) {
                  return MarkdownBody(
                    data: preprocessedMd,
                    builders: mathConfig.builders,
                    inlineSyntaxes: mathConfig.inlineSyntaxes,
                    styleSheet: _mdStyle(context).copyWith(
                      p: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: fg),
                    ),
                    onTapLink: (text, href, title) async {
                      if (href == null) return;
                      final uri = Uri.tryParse(href);
                      if (uri != null) {
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {}
                      }
                    },
                  );
                }

                if (evidenceNames.isEmpty) {
                  return MarkdownBody(
                    data: preprocessedMd,
                    builders: mathConfig.builders,
                    inlineSyntaxes: mathConfig.inlineSyntaxes,
                    styleSheet: _mdStyle(context).copyWith(
                      p: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: fg),
                    ),
                    onTapLink: (text, href, title) async {
                      if (href == null) return;
                      final uri = Uri.tryParse(href);
                      if (uri != null) {
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {}
                      }
                    },
                  );
                }

                final String msgKey = _evidenceMsgKey(m);
                final Map<String, String> cached =
                    _evidenceResolvedByMsgKey[msgKey] ??
                    const <String, String>{};
                final Map<String, String> baseMap = <String, String>{
                  ...evidenceNameToPath,
                  ...cached,
                };
                final Set<String> missing = evidenceNames
                    .where((n) => !baseMap.containsKey(n))
                    .toSet();

                List<String> orderedEvidencePathsFromMap(
                  Map<String, String> map,
                ) {
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
                    evidenceNameToPath: baseMap,
                    orderedEvidencePaths: orderedEvidencePathsFromMap(baseMap),
                  );
                  return MarkdownBody(
                    data: preprocessedMd,
                    builders: resolved.builders,
                    inlineSyntaxes: resolved.inlineSyntaxes,
                    styleSheet: _mdStyle(context).copyWith(
                      p: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: fg),
                    ),
                    onTapLink: (text, href, title) async {
                      if (href == null) return;
                      final uri = Uri.tryParse(href);
                      if (uri != null) {
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {}
                      }
                    },
                  );
                }

                return FutureBuilder<Map<String, String>>(
                  future: _resolveEvidencePathsCached(
                    msgKey: msgKey,
                    missingNames: missing,
                  ),
                  builder: (context, snap) {
                    final Map<String, String> map =
                        snap.data ?? const <String, String>{};
                    final merged = <String, String>{...baseMap, ...map};
                    final resolved = MarkdownMathConfig(
                      inlineTextStyle: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: fg),
                      blockTextStyle: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: fg),
                      evidenceNameToPath: merged,
                      orderedEvidencePaths: orderedEvidencePathsFromMap(merged),
                    );
                    return MarkdownBody(
                      data: preprocessedMd,
                      builders: resolved.builders,
                      inlineSyntaxes: resolved.inlineSyntaxes,
                      styleSheet: _mdStyle(context).copyWith(
                        p: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: fg),
                      ),
                      onTapLink: (text, href, title) async {
                        if (href == null) return;
                        final uri = Uri.tryParse(href);
                        if (uri != null) {
                          try {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (_) {}
                        }
                      },
                    );
                  },
                );
              })(); */

        // 取消底部缩略图展示：图片仅通过正文中的 [evidence: FILENAME.EXT] 内联渲染

        // 组合：上方时间，中间消息气泡，下方操作区
        return Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // 上方：时间（HH:mm:ss）
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 6),
              child: Text(
                DateFormat('HH:mm:ss').format(
                  (m.role == 'assistant' &&
                          _reasoningDurationByIndex[index] != null)
                      ? m.createdAt.add(_reasoningDurationByIndex[index]!)
                      : m.createdAt,
                ),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
            ),
            Align(
              alignment: align,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing3,
                  vertical: AppTheme.spacing2,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [mdWidget],
                ),
              ),
            ),
            // 下方：操作区（复制、重新生成）——与气泡边缘对齐（左对齐助手，右对齐用户）
            Align(
              alignment: align,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 复制（Material Icon）
                    IconButton(
                      onPressed: () async {
                        try {
                          await Clipboard.setData(
                            ClipboardData(
                              text: _buildMessageCopyText(m, index),
                            ),
                          );
                          if (mounted)
                            UINotifier.success(
                              context,
                              AppLocalizations.of(context).copySuccess,
                            );
                        } catch (_) {}
                      },
                      constraints: const BoxConstraints.tightFor(
                        width: 24,
                        height: 24,
                      ),
                      padding: const EdgeInsets.all(0),
                      visualDensity: const VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                      splashRadius: 16,
                      iconSize: 16,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: AppLocalizations.of(context).actionCopy,
                    ),
                    const SizedBox(width: 4),
                    // 重新生成（仅对助手消息提供）
                    // 移除"重试/重新生成"功能
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            // 根据位置更新粘底标志：仅在接近底部时视为粘底
            final double distanceToBottom =
                (metrics.maxScrollExtent - metrics.pixels).clamp(
                  0.0,
                  double.infinity,
                );
            _stickToBottom =
                distanceToBottom <= _AISettingsPageState._autoScrollProximity;
            return false;
          },
          child: list,
        ),
        if (!_stickToBottom)
          Positioned(
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Material(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.92),
                elevation: 2,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    _stickToBottom = true;
                    _scrollToBottom(animated: true);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAttachmentThumb(
    EvidenceImageAttachment att,
    int index,
    Color fg,
  ) {
    final file = File(att.path);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ScreenshotImageWidget(
              file: file,
              privacyMode: true,
              width: 88,
              height: 158,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(8),
              targetWidth: 176,
            ),
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '[图$index]',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 88,
          child: Text(
            att.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg.withOpacity(0.9), fontSize: 10),
          ),
        ),
      ],
    );
  }

  // "思考过程"面板：显示 reasoning 实时内容（流式期间展示，可折叠）
  Widget _buildThinkingRow() {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing3,
          vertical: AppTheme.spacing2,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRect(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: SvgPicture.asset(
                      'assets/icons/think.svg',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      colorFilter: ColorFilter.mode(
                        theme.colorScheme.onSurfaceVariant,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context).deepThinkingLabel +
                          (_inStreaming ? _thinkingDots : ''),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _thinkingTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Builder(
                      builder: (ctx) {
                        if (!_inStreaming || _currentAssistantIndex == null)
                          return const SizedBox.shrink();
                        final idx = _currentAssistantIndex!;
                        if (idx < 0 || idx >= _messages.length)
                          return const SizedBox.shrink();
                        final dur = DateTime.now().difference(
                          _messages[idx].createdAt,
                        );
                        if (dur.inMilliseconds <= 0)
                          return const SizedBox.shrink();
                        final secs = (dur.inMilliseconds / 1000.0)
                            .toStringAsFixed(1);
                        return Text(
                          '($secs s)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _thinkingTextColor,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  tooltip: _showThinkingContent
                      ? AppLocalizations.of(context).collapse
                      : AppLocalizations.of(context).expandMore,
                  onPressed: () => _setState(
                    () => _showThinkingContent = !_showThinkingContent,
                  ),
                  splashRadius: 16,
                  icon: Icon(
                    _showThinkingContent
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (_showThinkingContent) ...[
              const SizedBox(height: 6),
              if (_thinkingText.isEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context).thinkingInProgress,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _thinkingTextColor,
                      ),
                    ),
                  ],
                )
              else if (_inStreaming)
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 200),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: _ScrollMaskWrapper(
                    controller: _reasoningPanelScrollController,
                    maskColor: theme.colorScheme.surfaceVariant,
                    child: Scrollbar(
                      child: ListView.builder(
                        controller: _reasoningPanelScrollController,
                        physics: const ClampingScrollPhysics(),
                        itemCount: _thinkingText
                            .replaceAll('\r\n', '\n')
                            .split('\n')
                            .length,
                        itemBuilder: (context, i) {
                          final parts = _thinkingText
                              .replaceAll('\r\n', '\n')
                              .split('\n');
                          return Text(
                            parts[i],
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _thinkingTextColor,
                              fontFamily: 'monospace',
                              height: 1.20,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 200),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: _ScrollMaskWrapper(
                    controller: _reasoningPanelScrollController,
                    maskColor: theme.colorScheme.surfaceVariant,
                    child: Scrollbar(
                      child: ListView.builder(
                        controller: _reasoningPanelScrollController,
                        physics: const ClampingScrollPhysics(),
                        itemCount: _thinkingText
                            .replaceAll('\r\n', '\n')
                            .split('\n')
                            .length,
                        itemBuilder: (context, i) {
                          final parts = _thinkingText
                              .replaceAll('\r\n', '\n')
                              .split('\n');
                          return Text(
                            parts[i],
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _thinkingTextColor,
                              fontFamily: 'monospace',
                              height: 1.20,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // 新的底部输入栏（现代化圆角胶囊样式，带流光边框效果和展开按钮）
  Widget _buildComposerBar() {
    final theme = Theme.of(context);
    String _middleEllipsis(String s, int maxChars) {
      if (s.length <= maxChars) return s;
      if (maxChars <= 3) return s.substring(0, maxChars);
      final keep = maxChars - 1; // one char for ellipsis
      final head = (keep / 2).floor();
      final tail = keep - head;
      return s.substring(0, head) + '…' + s.substring(s.length - tail);
    }

    final String modelLabel = (() {
      final mctx = (_ctxChatModel ?? '').trim();
      if (mctx.isNotEmpty) return _middleEllipsis(mctx, 18);
      final legacy = _modelController.text.trim();
      return legacy.isEmpty ? 'AI' : _middleEllipsis(legacy, 18);
    })();
    final placeholder = AppLocalizations.of(
      context,
    ).sendMessageToModelPlaceholder(modelLabel);

    Widget barInner = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24), // 胶囊形状
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 左侧个人助手状态提示
          Tooltip(
            message: AppLocalizations.of(context).aiSelfModeEnabledToast,
            preferBelow: false,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(child: _buildMagicIcon(size: 18, withGlow: true)),
            ),
          ),
          const SizedBox(width: AppTheme.spacing1),
          Expanded(
            child: TextField(
              controller: _inputController,
              minLines: _inputExpanded ? 3 : 1,
              maxLines: null,
              textAlignVertical: TextAlignVertical.center,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: placeholder,
                hintMaxLines: 1,
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                ),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing2,
                  vertical: AppTheme.spacing2,
                ),
                filled: false,
              ),
              onTap: () {
                _setState(() {
                  _connExpanded = false; // 点击输入收起连接设置
                });
              },
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          // 圆形发送/停止按钮（保持触达安全但略微更紧凑）
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _sending
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.error,
                        theme.colorScheme.error.withOpacity(0.8),
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primary.withOpacity(0.8),
                      ],
                    ),
              boxShadow: [
                BoxShadow(
                  color:
                      (_sending
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary)
                          .withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _sending ? _cancelRequest : _sendMessage,
                child: Center(
                  child: Icon(
                    _sending ? Icons.close_rounded : Icons.arrow_upward_rounded,
                    color: theme.colorScheme.onPrimary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return _ShimmerBorder(active: _inStreaming || _sending, child: barInner);
  }

  // 统一的小型选项芯片
  Widget _buildChip(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primary.withOpacity(0.10)
        : theme.colorScheme.surfaceVariant;
    final fg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
    final bd = selected ? theme.colorScheme.primary : theme.colorScheme.outline;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: AppTheme.spacing1,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(color: bd, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
