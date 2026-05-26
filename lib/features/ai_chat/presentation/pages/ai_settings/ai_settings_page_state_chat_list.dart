part of '../ai_settings_page.dart';

extension _AISettingsPageStateChatListExt on _AISettingsPageState {
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
          final String? messageReasoningContent =
              _reasoningByIndex[index] ?? m.reasoningContent;
          final List<_ThinkingBlock> blocks = _blocksForMessageIndex(index);

          final List<Widget> children = <Widget>[];
          void addThinkingBlock(int i) {
            if (i >= blocks.length) return;
            final b = blocks[i];
            // Only show legacy fallback reasoning while the block is still loading.
            // For completed turns, prefer the structured timeline events; avoid
            // dumping internal logs on restore.
            final bool showStreamingFallbackReasoning =
                i == 0 &&
                b.isLoading &&
                (_reasoningByIndex[index] ?? '').trim().isNotEmpty;
            final bool showCompletedFallbackReasoning =
                i == 0 &&
                !b.isLoading &&
                (m.reasoningContent ?? '').trim().isNotEmpty &&
                !_looksLikeOnlyInternalReasoningProgress(
                  m.reasoningContent ?? '',
                );
            final bool hasReasoningEvents = b.events.any(
              (e) =>
                  e.type == _ThinkingEventType.reasoning &&
                  (e.reasoningStart ?? -1) >= 0 &&
                  (e.reasoningLength ?? 0) > 0,
            );
            final bool showFallbackReasoning =
                !hasReasoningEvents &&
                (showStreamingFallbackReasoning ||
                    showCompletedFallbackReasoning);
            final String? fallbackReasoning = showFallbackReasoning
                ? messageReasoningContent
                : null;
            final bool hasDisplayContent = _thinkingBlockHasDisplayContent(
              b,
              reasoningContent: messageReasoningContent ?? '',
              fallbackReasoning: fallbackReasoning,
              includeTransient: b.isLoading,
            );
            if (hasDisplayContent) {
              children.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                  child: _ThinkingTimelineCard(
                    key: ValueKey(
                      'think:${m.createdAt.millisecondsSinceEpoch}:$i',
                    ),
                    conversationId: (_activeConversationCid ?? '').trim(),
                    assistantCreatedAt: m.createdAt.millisecondsSinceEpoch,
                    createdAt: b.createdAt,
                    finishedAt: b.finishedAt,
                    events: b.events,
                    reasoningContent: messageReasoningContent,
                    fallbackReasoning: fallbackReasoning,
                    autoCloseOnFinish:
                        !(m.content.trim().isEmpty &&
                            ((fallbackReasoning ?? '').trim().isNotEmpty ||
                                (hasReasoningEvents &&
                                    (messageReasoningContent ?? '')
                                        .trim()
                                        .isNotEmpty))),
                  ),
                ),
              );
            }
          }

          for (int i = 0; i < blocks.length; i++) {
            addThinkingBlock(i);
          }

          final String content = m.content.trim().isNotEmpty
              ? m.content
              : _contentSegmentsForMessageIndex(index).join();
          if (content.trim().isNotEmpty) {
            children.add(
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                child: _buildMarkdownForMessage(
                  message: m,
                  messageIndex: index,
                  content: content,
                  fg: fg,
                  isCurrentStreaming: isCurrentStreaming,
                ),
              ),
            );
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
                child: _buildMessageFooter(m, index, isAssistant: true),
              ),
            ],
          );
        }

        final String displayContent = isUser
            ? _stripComposerImageMarkers(m.content)
            : m.content;
        final Widget mdWidget = _buildMarkdownForMessage(
          message: m,
          messageIndex: index,
          content: displayContent,
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

        final List<EvidenceImageAttachment> messageAttachments =
            _attachmentsForMessage(index, m);

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
                  children: [
                    if (isUser && messageAttachments.isNotEmpty) ...[
                      _buildUserMessageAttachments(messageAttachments),
                      if (displayContent.trim().isNotEmpty)
                        const SizedBox(height: AppTheme.spacing2),
                    ],
                    mdWidget,
                  ],
                ),
              ),
            ),
            // 下方：操作区（复制、重新生成）——与气泡边缘对齐（左对齐助手，右对齐用户）
            Align(
              alignment: align,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _buildMessageFooter(m, index, isAssistant: isAssistant),
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
            // Scroll-to-top: load older full-transcript pages (best-effort).
            if (metrics.pixels <= 80.0 &&
                _olderHasMore &&
                !_olderLoading &&
                !_inStreaming &&
                !_sending) {
              unawaited(_loadOlderPage());
            }
            return false;
          },
          child: list,
        ),
        if (_olderLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUserMessageAttachments(List<EvidenceImageAttachment> images) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppTheme.spacing2),
        itemBuilder: (context, index) {
          final EvidenceImageAttachment image = images[index];
          return Tooltip(
            message: image.label,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                onTap: () => _showComposerImagePreview(image),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  child: Container(
                    width: 132,
                    height: 132,
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.45),
                    child: Image.file(
                      File(image.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<EvidenceImageAttachment> _attachmentsForMessage(
    int index,
    AIMessage message,
  ) {
    final List<EvidenceImageAttachment> indexed =
        _attachmentsByIndex[index] ?? const <EvidenceImageAttachment>[];
    final List<EvidenceImageAttachment> marked = _composerImageMarkersFromText(
      message.content,
    );
    if (indexed.isEmpty) return marked;
    if (marked.isEmpty) return indexed;
    final List<EvidenceImageAttachment> out = <EvidenceImageAttachment>[];
    final Set<String> seen = <String>{};
    for (final EvidenceImageAttachment image in <EvidenceImageAttachment>[
      ...indexed,
      ...marked,
    ]) {
      final String path = image.path.trim();
      if (path.isEmpty || !seen.add(path)) continue;
      out.add(image);
    }
    return out;
  }

  List<EvidenceImageAttachment> _composerImageMarkersFromText(String text) {
    final RegExp pattern = RegExp(
      r'\[\[composer-image:([^|\]]+)(?:\|([^\]]*))?\]\]',
    );
    final List<EvidenceImageAttachment> out = <EvidenceImageAttachment>[];
    final Set<String> seen = <String>{};
    for (final RegExpMatch match in pattern.allMatches(text)) {
      final String encodedPath = (match.group(1) ?? '').trim();
      if (encodedPath.isEmpty) continue;
      String path;
      String label;
      try {
        path = Uri.decodeComponent(encodedPath).trim();
        label = Uri.decodeComponent((match.group(2) ?? '').trim()).trim();
      } catch (_) {
        path = encodedPath;
        label = (match.group(2) ?? '').trim();
      }
      if (path.isEmpty || !seen.add(path)) continue;
      out.add(
        EvidenceImageAttachment(
          path: path,
          label: label.isEmpty ? _basenameFromPath(path) : label,
        ),
      );
    }
    return out;
  }

  String _stripComposerImageMarkers(String text) {
    return text
        .replaceAll(
          RegExp(
            r'^[ \t]*\[\[composer-image:[^|\]]+(?:\|[^\]]*)?\]\][ \t]*$',
            multiLine: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Future<void> _showComposerImagePreview(EvidenceImageAttachment image) async {
    final String path = image.path.trim();
    if (path.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.all(AppTheme.spacing4),
          backgroundColor: theme.colorScheme.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          image.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          dialogContext,
                        ).closeButtonTooltip,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ClipRect(
                    child: InteractiveViewer(
                      minScale: 0.6,
                      maxScale: 5,
                      child: Image.file(
                        File(path),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Padding(
                          padding: const EdgeInsets.all(AppTheme.spacing6),
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _looksLikeOnlyInternalReasoningProgress(String text) {
    final List<String> lines = text
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return true;
    return lines.every(_isInternalReasoningProgressLine);
  }

  String _fmtStatInt(int value) => NumberFormat.compact().format(value);

  String _fmtDurationShort(Duration duration) {
    final int ms = duration.inMilliseconds;
    if (ms <= 0) return '';
    if (ms < 1000) return '${ms}ms';
    final double seconds = ms / 1000.0;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final int minutes = seconds ~/ 60;
    final double rest = seconds - minutes * 60;
    return '${minutes}m ${rest.toStringAsFixed(0)}s';
  }

  Widget _buildStatsItem(IconData icon, String text) {
    final theme = Theme.of(context);
    final Color color = theme.colorScheme.onSurfaceVariant.withOpacity(0.68);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(color: color, height: 1),
        ),
      ],
    );
  }

  Widget _buildMessageNerdLine(AIMessage message) {
    final Stopwatch sw = Stopwatch()..start();
    final int? prompt = message.usagePromptTokens;
    final int? completion = message.usageCompletionTokens;
    final int? cacheHit = message.usageCacheHitTokens;
    final int? cacheMiss = message.usageCacheMissTokens;
    final Duration? duration = message.responseDuration;
    final String logKey = [
      message.role,
      message.createdAt.millisecondsSinceEpoch,
      prompt ?? '-',
      completion ?? '-',
      message.usageTotalTokens ?? '-',
      duration?.inMilliseconds ?? '-',
    ].join(':');
    final bool shouldLogStatsBuild = _usageStatsUiLoggedKeys.add(logKey);
    if (shouldLogStatsBuild) {
      unawaited(
        FlutterLogger.nativeDebug(
          'AIUsageTrace',
          [
            'UI_STATS_BUILD',
            'role=${message.role} createdAt=${message.createdAt.millisecondsSinceEpoch} contentLen=${message.content.length}',
            'prompt=${prompt ?? '-'} completion=${completion ?? '-'} total=${message.usageTotalTokens ?? '-'} cacheHit=${cacheHit ?? '-'} cacheMiss=${cacheMiss ?? '-'} responseMs=${duration?.inMilliseconds ?? '-'}',
          ].join('\n'),
        ).catchError((_) {}),
      );
    }
    final List<Widget> items = <Widget>[];
    if (prompt != null) {
      items.add(
        _buildStatsItem(Icons.upload_rounded, '${_fmtStatInt(prompt)} tokens'),
      );
    }
    if (completion != null) {
      items.add(
        _buildStatsItem(
          Icons.download_rounded,
          '${_fmtStatInt(completion)} tokens',
        ),
      );
    }
    if (cacheHit != null) {
      items.add(
        _buildStatsItem(Icons.memory_rounded, '${_fmtStatInt(cacheHit)} cache'),
      );
    }
    if (cacheMiss != null) {
      items.add(
        _buildStatsItem(
          Icons.memory_outlined,
          '${_fmtStatInt(cacheMiss)} miss',
        ),
      );
    }
    if (completion != null && duration != null && duration.inMilliseconds > 0) {
      final double tps = completion / duration.inMilliseconds * 1000.0;
      items.add(
        _buildStatsItem(Icons.bolt_rounded, '${tps.toStringAsFixed(1)} tok/s'),
      );
    }
    if (duration != null && duration.inMilliseconds > 0) {
      final String text = _fmtDurationShort(duration);
      if (text.isNotEmpty) {
        items.add(_buildStatsItem(Icons.schedule_rounded, text));
      }
    }
    if (shouldLogStatsBuild) {
      _logChatPerf(
        'messageNerdLine.build.done',
        stopwatch: sw,
        detail:
            'role=${message.role} createdAt=${message.createdAt.millisecondsSinceEpoch} items=${items.length} contentLen=${message.content.length}',
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: items,
      ),
    );
  }

  Widget _buildFooterIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
      padding: const EdgeInsets.all(0),
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      splashRadius: 16,
      iconSize: 16,
      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8),
      icon: Icon(icon),
      tooltip: tooltip,
    );
  }

  Widget _buildMessageFooter(
    AIMessage message,
    int index, {
    required bool isAssistant,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFooterIconButton(
              icon: Icons.copy_rounded,
              tooltip: AppLocalizations.of(context).actionCopy,
              onPressed: () async {
                try {
                  await Clipboard.setData(
                    ClipboardData(text: _buildMessageCopyText(message, index)),
                  );
                  if (mounted) {
                    UINotifier.success(
                      context,
                      AppLocalizations.of(context).copySuccess,
                    );
                  }
                } catch (_) {}
              },
            ),
            const SizedBox(width: 4),
            _buildFooterIconButton(
              icon: Icons.refresh_rounded,
              tooltip: _isZhLocale() ? '重试' : 'Retry',
              onPressed: _sending ? null : () => _retryMessageAt(index),
            ),
          ],
        ),
        if (isAssistant) _buildMessageNerdLine(message),
      ],
    );
  }

  Widget _buildAttachmentThumb(
    EvidenceImageAttachment att,
    int index,
    Color fg,
  ) {
    final file = File(att.path);
    final String p = att.path.trim();
    final ScreenshotRecord? screenshot = _evidenceScreenshotByPath[p];
    final bool extraNsfwMask =
        NsfwPreferenceService.instance.isAiNsfwCached(filePath: p) ||
        NsfwPreferenceService.instance.isSegmentNsfwCached(filePath: p);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ScreenshotImageWidget(
              file: file,
              privacyMode: true,
              extraNsfwMask: extraNsfwMask,
              screenshot: screenshot,
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
                Icon(
                  Icons.tips_and_updates_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
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

  Widget _buildComposerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    Color? color,
    Color? background,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: background ?? Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Icon(
              icon,
              size: 22,
              color: onTap == null
                  ? theme.colorScheme.onSurfaceVariant.withOpacity(0.38)
                  : (color ?? theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposerAttachments() {
    final int skeletonCount = _processingComposerImages
        ? (_composerImageSkeletonCount <= 0 ? 1 : _composerImageSkeletonCount)
        : 0;
    if (_composerImages.isEmpty && skeletonCount == 0) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _composerImages.length + skeletonCount,
        separatorBuilder: (_, __) => const SizedBox(width: AppTheme.spacing2),
        itemBuilder: (context, index) {
          if (index >= _composerImages.length) {
            return _buildComposerImageSkeleton();
          }
          final _ComposerImageAttachment item = _composerImages[index];
          final EvidenceImageAttachment previewImage = EvidenceImageAttachment(
            path: item.path,
            label: item.name.trim().isEmpty
                ? _basenameFromPath(item.path)
                : item.name,
          );
          final String deleteTooltip = MaterialLocalizations.of(
            context,
          ).deleteButtonTooltip;
          return SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      onTap: () => _showComposerImagePreview(previewImage),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        child: Container(
                          width: 56,
                          height: 56,
                          color: theme.colorScheme.surfaceVariant,
                          child: Image.file(File(item.path), fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Semantics(
                    button: true,
                    label: deleteTooltip,
                    child: Tooltip(
                      message: deleteTooltip,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _removeComposerImage(item.path),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Align(
                            alignment: Alignment.topRight,
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: Material(
                                color: theme.colorScheme.inverseSurface,
                                shape: const CircleBorder(),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: theme.colorScheme.onInverseSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildComposerImageSkeleton() {
    final theme = Theme.of(context);
    final Color base = theme.colorScheme.surfaceVariant;
    final Color highlight = theme.colorScheme.surface;
    return SizedBox(
      width: 64,
      height: 64,
      child: Align(
        alignment: Alignment.topLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: _Shimmer(
            active: true,
            baseColor: base,
            highlightColor: highlight,
            period: const Duration(milliseconds: 1100),
            child: Container(
              width: 56,
              height: 56,
              color: base,
              child: Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.45),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 常规底部输入栏：圆角容器内第一行输入，第二行功能键。
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
    final Color drawColor = _imageDrawMode
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant.withOpacity(0.45);
    final l10n = AppLocalizations.of(context);
    final String sendTooltip = _sending
        ? l10n.composerStopTooltip
        : (_imageDrawMode
              ? l10n.composerGenerateImageTooltip
              : l10n.composerSendTooltip);
    final Color sendBackground = _sending
        ? Color.alphaBlend(
            theme.colorScheme.error.withValues(alpha: 0.12),
            theme.colorScheme.surfaceContainerHighest,
          )
        : theme.colorScheme.primary;
    final Color sendForeground = _sending
        ? theme.colorScheme.error
        : theme.colorScheme.onPrimary;

    final Widget barInner = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.65),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        AppTheme.spacing3,
        AppTheme.spacing2,
        AppTheme.spacing3,
        AppTheme.spacing2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildComposerAttachments(),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: _composerInputRowHeight,
              maxHeight: _composerInputRowHeight * 6.0,
            ),
            child: TextField(
              controller: _inputController,
              keyboardType: TextInputType.multiline,
              minLines: 1,
              maxLines: _composerInputMaxLines,
              textInputAction: TextInputAction.newline,
              textAlignVertical: TextAlignVertical.top,
              scrollPhysics: const ClampingScrollPhysics(),
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: placeholder,
                hintMaxLines: 2,
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
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                filled: false,
              ),
              onTap: () {
                _setState(() {
                  _connExpanded = false;
                });
              },
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Row(
            children: [
              _buildComposerIconButton(
                icon: Icons.add_rounded,
                tooltip: l10n.composerAttachImageTooltip,
                onTap: _pickingComposerImages ? null : _pickComposerImages,
              ),
              const SizedBox(width: AppTheme.spacing1),
              _buildComposerIconButton(
                icon: Icons.image_outlined,
                tooltip: _imageDrawMode
                    ? l10n.composerDrawingModeOnTooltip
                    : l10n.composerEnableDrawingModeTooltip,
                color: drawColor,
                background: _imageDrawMode
                    ? theme.colorScheme.primaryContainer.withOpacity(0.55)
                    : null,
                onTap: () {
                  final bool next = !_imageDrawMode;
                  _setState(() {
                    _imageDrawMode = next;
                  });
                  UINotifier.info(
                    context,
                    next
                        ? l10n.composerDrawingModeEnabledToast
                        : l10n.composerDrawingModeDisabledToast,
                  );
                },
              ),
              const Spacer(),
              _buildReasoningMenuButton(),
              const SizedBox(width: AppTheme.spacing2),
              _buildComposerIconButton(
                icon: _sending
                    ? Icons.close_rounded
                    : Icons.arrow_upward_rounded,
                tooltip: sendTooltip,
                color: sendForeground,
                background: sendBackground,
                onTap: _sending ? _cancelRequest : _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTheme.spacing4,
        AppTheme.spacing2,
        AppTheme.spacing4,
        MediaQuery.of(context).padding.bottom + AppTheme.spacing4,
      ),
      child: barInner,
    );
  }

  Widget _buildReasoningMenuButton() {
    final theme = Theme.of(context);
    final Color foreground = _reasoningLevel.isEnabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return UIActionMenuButton<AIReasoningLevel>(
      tooltip: _reasoningLevelLabel(_reasoningLevel),
      selectedValue: _reasoningLevel,
      minWidth: 180,
      maxWidth: 220,
      offset: const Offset(0, -8),
      onSelected: (level) async {
        _setState(() {
          _reasoningLevel = level;
        });
        await _settings.setChatReasoningLevel(level);
      },
      items: AIReasoningLevel.values
          .map(
            (level) => UIActionMenuItem<AIReasoningLevel>(
              value: level,
              label: _reasoningLevelLabel(level),
            ),
          )
          .toList(growable: false),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing2,
          vertical: AppTheme.spacing1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 108),
              child: Text(
                _reasoningLevelLabel(_reasoningLevel),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded, size: 18, color: foreground),
          ],
        ),
      ),
    );
  }

  String _reasoningLevelLabel(AIReasoningLevel level) {
    final bool zh = _isZhLocale();
    switch (level) {
      case AIReasoningLevel.off:
        return zh ? '思考：关闭' : 'Reasoning: Off';
      case AIReasoningLevel.auto:
        return zh ? '思考：自动' : 'Reasoning: Auto';
      case AIReasoningLevel.low:
        return zh ? '思考：低' : 'Reasoning: Low';
      case AIReasoningLevel.medium:
        return zh ? '思考：中等' : 'Reasoning: Medium';
      case AIReasoningLevel.high:
        return zh ? '思考：高' : 'Reasoning: High';
      case AIReasoningLevel.xhigh:
        return zh ? '思考：超高' : 'Reasoning: XHigh';
    }
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
