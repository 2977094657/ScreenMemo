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
  bool _shouldAnalyzeIntentForConversation(
    String cid, {
    required bool isFirstUserTurn,
  }) {
    if (!isFirstUserTurn) return false;
    final String key = cid.trim().isEmpty ? 'default' : cid.trim();
    return !_intentAnalyzedConversationCids.contains(key);
  }

  void _markIntentAnalyzedForConversation(String cid) {
    final String key = cid.trim().isEmpty ? 'default' : cid.trim();
    _intentAnalyzedConversationCids.add(key);
  }

  bool _sameAssistantDisplayMetadata(AIMessage a, AIMessage b) {
    return a.content == b.content &&
        a.reasoningContent == b.reasoningContent &&
        a.reasoningDuration == b.reasoningDuration &&
        a.uiThinkingJson == b.uiThinkingJson &&
        a.usagePromptTokens == b.usagePromptTokens &&
        a.usageCompletionTokens == b.usageCompletionTokens &&
        a.usageTotalTokens == b.usageTotalTokens &&
        a.usageCacheHitTokens == b.usageCacheHitTokens &&
        a.usageCacheMissTokens == b.usageCacheMissTokens &&
        a.responseDuration == b.responseDuration;
  }

  AIMessage _mergeCompletedAssistantForDisplay(
    AIMessage target,
    AIMessage completed,
  ) {
    final String completedContent = completed.content.trim();
    final String? targetUi = (target.uiThinkingJson ?? '').trim().isEmpty
        ? null
        : target.uiThinkingJson;
    final String? completedUi = (completed.uiThinkingJson ?? '').trim().isEmpty
        ? null
        : completed.uiThinkingJson;

    return AIMessage(
      role: 'assistant',
      content: completedContent.isNotEmpty ? completed.content : target.content,
      createdAt: target.createdAt,
      reasoningContent: completed.reasoningContent ?? target.reasoningContent,
      reasoningDuration:
          completed.reasoningDuration ?? target.reasoningDuration,
      uiThinkingJson: targetUi ?? completedUi,
      usagePromptTokens:
          completed.usagePromptTokens ?? target.usagePromptTokens,
      usageCompletionTokens:
          completed.usageCompletionTokens ?? target.usageCompletionTokens,
      usageTotalTokens: completed.usageTotalTokens ?? target.usageTotalTokens,
      usageCacheHitTokens:
          completed.usageCacheHitTokens ?? target.usageCacheHitTokens,
      usageCacheMissTokens:
          completed.usageCacheMissTokens ?? target.usageCacheMissTokens,
      responseDuration: completed.responseDuration ?? target.responseDuration,
    );
  }

  bool _mergeCompletedAssistantIntoCurrentBubble(AIMessage completed) {
    bool changed = false;
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

      final AIMessage updated = _mergeCompletedAssistantForDisplay(
        target,
        completed,
      );
      if (_sameAssistantDisplayMetadata(target, updated)) return;

      final List<AIMessage> newList = List<AIMessage>.from(_messages);
      newList[targetIdx] = updated;
      _messages = newList;
      changed = true;

      if (currentIdx != null && completed.content.trim().isNotEmpty) {
        if (_replaceAssistantContentOnNextToken) {
          _finishActiveThinkingBlock(currentIdx);
          _appendContentChunk(currentIdx, completed.content);
        } else {
          _syncContentSegmentsForFullContent(currentIdx, updated.content);
        }
        _replaceAssistantContentOnNextToken = false;
      }
    });
    return changed;
  }

  String _mimeForComposerImagePath(String path) {
    final String ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'png':
        return 'image/png';
      default:
        return 'image/png';
    }
  }

  String _extensionForComposerImagePath(String path) {
    final String fileName = path
        .replaceAll('\\', '/')
        .split('/')
        .last
        .split('?')
        .first;
    final int dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot >= fileName.length - 1) return 'jpg';
    final String ext = fileName.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'gif':
      case 'bmp':
      case 'heic':
      case 'heif':
        return ext;
      default:
        return 'jpg';
    }
  }

  Future<String> _copyComposerImageToPrivate(String sourcePath) async {
    final File source = File(sourcePath);
    if (!await source.exists()) {
      throw Exception('Selected image file does not exist.');
    }
    if (await source.length() <= 0) {
      throw Exception('Selected image file is empty.');
    }
    final DateTime now = DateTime.now();
    final String month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final Directory? dir = await PathService.getPersistentPrivateDir(
      'ai/chat_attachments/$month',
    );
    if (dir == null) {
      throw Exception('Failed to resolve chat attachment output directory.');
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final String ext = _extensionForComposerImagePath(source.path);
    final String name =
        'selected_${DateTime.now().microsecondsSinceEpoch}.$ext';
    final File out = File('${dir.path}${Platform.pathSeparator}$name');
    await source.copy(out.path);
    return out.path;
  }

  Future<void> _pickComposerImages() async {
    if (_pickingComposerImages) return;
    _setState(() {
      _pickingComposerImages = true;
      _composerImageSkeletonCount = 0;
    });
    final List<String> createdTempPaths = <String>[];
    bool committed = false;
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        // file_picker 在 Android 上默认压缩图片时会写入公共 Pictures 目录。
        // 这里关闭插件压缩，避免仅选择附件就在系统相册生成副本。
        allowCompression: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      if (!mounted) return;
      final int remainingSlots = (_maxComposerImages - _composerImages.length)
          .clamp(0, _maxComposerImages);
      final int pendingCount = result.files.length
          .clamp(1, remainingSlots <= 0 ? 1 : remainingSlots)
          .toInt();
      _setState(() {
        _processingComposerImages = true;
        _composerImageSkeletonCount = pendingCount;
      });
      await WidgetsBinding.instance.endOfFrame;
      final List<_ComposerImageAttachment> next =
          List<_ComposerImageAttachment>.from(_composerImages);
      final Set<String> existing = next.map((e) => e.path).toSet();
      final int initialCount = next.length;
      for (final PlatformFile file in result.files) {
        if (next.length >= _maxComposerImages) break;
        final String? rawPath = file.path?.trim();
        if (rawPath == null || rawPath.isEmpty) continue;
        final String tempPath = await _copyComposerImageToPrivate(rawPath);
        createdTempPaths.add(tempPath);
        if (!existing.add(tempPath)) {
          unawaited(File(tempPath).delete().catchError((_) => File(tempPath)));
          continue;
        }
        next.add(
          _ComposerImageAttachment(
            path: tempPath,
            name: file.name.trim().isEmpty ? 'image.png' : file.name.trim(),
            mimeType: _mimeForComposerImagePath(tempPath),
          ),
        );
      }
      if (!mounted) return;
      _setState(() {
        _composerImages = next;
      });
      committed = true;
      if (result.files.length > next.length - initialCount) {
        UINotifier.info(
          context,
          AppLocalizations.of(
            context,
          ).composerImageLimitToast(_maxComposerImages),
        );
      }
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).composerImageSelectionFailed(e.toString()),
      );
    } finally {
      if (mounted) {
        _setState(() {
          _pickingComposerImages = false;
        });
      } else {
        _pickingComposerImages = false;
      }
      if (mounted) {
        _setState(() {
          _processingComposerImages = false;
          _composerImageSkeletonCount = 0;
        });
      } else {
        _processingComposerImages = false;
        _composerImageSkeletonCount = 0;
      }
      if (!committed) {
        for (final String path in createdTempPaths) {
          unawaited(File(path).delete().catchError((_) => File(path)));
        }
      }
      if (Platform.isAndroid || Platform.isIOS) {
        unawaited(
          FilePicker.platform.clearTemporaryFiles().catchError((_) => false),
        );
      }
    }
  }

  List<EvidenceImageAttachment> _composerImagesToMessageAttachments(
    List<_ComposerImageAttachment> images,
  ) {
    return images
        .map(
          (image) => EvidenceImageAttachment(
            path: image.path,
            label: image.name.trim().isEmpty ? 'image' : image.name.trim(),
          ),
        )
        .toList(growable: false);
  }

  String _composerImageAttachmentMarker(EvidenceImageAttachment image) {
    final String path = Uri.encodeComponent(image.path.trim());
    final String label = Uri.encodeComponent(image.label.trim());
    if (path.isEmpty) return '';
    return '[[composer-image:$path|$label]]';
  }

  String _withComposerImageMarkers(
    String text,
    List<EvidenceImageAttachment> images,
  ) {
    if (images.isEmpty) return text;
    final List<String> markers = images
        .map(_composerImageAttachmentMarker)
        .where((marker) => marker.trim().isNotEmpty)
        .toList(growable: false);
    if (markers.isEmpty) return text;
    return '$text\n\n${markers.join('\n')}';
  }

  void _removeComposerImage(String path) {
    final String target = path.trim();
    if (target.isEmpty) return;
    _setState(() {
      _composerImages = _composerImages
          .where((item) => item.path != target)
          .toList(growable: false);
    });
    unawaited(File(target).delete().catchError((_) => File(target)));
  }

  void _clearComposerImages({bool deleteFiles = true}) {
    final List<_ComposerImageAttachment> old =
        List<_ComposerImageAttachment>.from(_composerImages);
    _setState(() {
      _composerImages = <_ComposerImageAttachment>[];
    });
    if (deleteFiles) {
      for (final _ComposerImageAttachment item in old) {
        unawaited(File(item.path).delete().catchError((_) => File(item.path)));
      }
    }
  }

  Future<List<Map<String, Object?>>> _buildComposerImageApiParts(
    List<_ComposerImageAttachment> images,
  ) async {
    final List<Map<String, Object?>> parts = <Map<String, Object?>>[];
    for (final _ComposerImageAttachment image in images) {
      final File file = File(image.path);
      if (!await file.exists()) {
        throw Exception('Selected image file does not exist.');
      }
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Selected image file is empty.');
      }
      final String mime = image.mimeType.trim().isEmpty
          ? _mimeForComposerImagePath(image.path)
          : image.mimeType.trim();
      parts.add(<String, Object?>{
        'type': 'image_url',
        'image_url': <String, Object?>{
          'url': 'data:$mime;base64,${base64Encode(bytes)}',
        },
      });
    }
    return parts;
  }

  List<String> _generatedImageFilenamesFromVisibleHistory({
    required int limit,
    List<AIMessage>? messages,
  }) {
    if (limit <= 0) return const <String>[];
    final RegExp markerPattern = RegExp(
      r'\[\s*generated-image\s*:\s*([^\]\s]+)\s*\]',
      caseSensitive: false,
    );
    final List<String> names = <String>[];
    final Set<String> seen = <String>{};
    for (final AIMessage message in messages ?? _messages) {
      for (final RegExpMatch match in markerPattern.allMatches(
        message.content,
      )) {
        final String name = (match.group(1) ?? '').trim();
        if (name.isEmpty) continue;
        if (!seen.add(name)) continue;
        names.add(name);
      }
    }
    if (names.length <= limit) return names;
    return names.sublist(names.length - limit);
  }

  Future<List<_ComposerImageAttachment>>
  _buildGeneratedImageHistoryAttachments({
    required int limit,
    List<AIMessage>? messages,
  }) async {
    final List<String> names = _generatedImageFilenamesFromVisibleHistory(
      limit: limit,
      messages: messages,
    );
    if (names.isEmpty) return const <_ComposerImageAttachment>[];
    final Map<String, String> paths = await ScreenshotDatabase.instance
        .findAiGeneratedImagePathsByFilenames(names.toSet());
    final List<_ComposerImageAttachment> out = <_ComposerImageAttachment>[];
    for (final String name in names) {
      final String path = (paths[name] ?? '').trim();
      if (path.isEmpty) continue;
      try {
        if (!await File(path).exists()) continue;
      } catch (_) {
        continue;
      }
      out.add(
        _ComposerImageAttachment(
          path: path,
          name: name,
          mimeType: _mimeForComposerImagePath(path),
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  }

  Future<Object?> _buildChatUserApiContent({
    required String text,
    required List<_ComposerImageAttachment> currentImages,
    List<AIMessage>? historyMessages,
  }) async {
    final int historyLimit = (_maxComposerImages - currentImages.length)
        .clamp(0, _maxComposerImages)
        .toInt();
    final List<_ComposerImageAttachment> generatedHistoryImages =
        await _buildGeneratedImageHistoryAttachments(
          limit: historyLimit,
          messages: historyMessages,
        );
    final List<_ComposerImageAttachment> allImages = <_ComposerImageAttachment>[
      ...generatedHistoryImages,
      ...currentImages,
    ];
    if (allImages.isEmpty) return null;
    final String apiText = generatedHistoryImages.isEmpty
        ? text
        : '$text\n\nPrevious generated images from this conversation are attached for context.';
    return <Map<String, Object?>>[
      <String, Object?>{'type': 'text', 'text': apiText},
      ...await _buildComposerImageApiParts(allImages),
    ];
  }

  Future<void> _sendImageGenerationMessage({
    required String text,
    required List<_ComposerImageAttachment> images,
    required String requestCid,
    required int sendEpoch,
  }) async {
    void setStateIfActive(VoidCallback fn) {
      if (!mounted) return;
      if (_activeSendEpoch != sendEpoch) return;
      _setState(fn);
    }

    final DateTime userCreatedAt = DateTime.now();
    final DateTime assistantCreatedAt = DateTime.now();
    final int assistantIdx = _messages.length + 1;
    final String callId =
        'manual_${DateTime.now().millisecondsSinceEpoch}_$sendEpoch';
    final String loadingContent = _generatedImageLoadingMarkers(
      callId,
      1,
    ).join('\n\n');
    final List<EvidenceImageAttachment> userAttachments =
        _composerImagesToMessageAttachments(images);
    setStateIfActive(() {
      _messages = List<AIMessage>.from(_messages)
        ..add(
          AIMessage(
            role: 'user',
            content: _withComposerImageMarkers(text, userAttachments),
            createdAt: userCreatedAt,
          ),
        )
        ..add(
          AIMessage(
            role: 'assistant',
            content: loadingContent,
            createdAt: assistantCreatedAt,
          ),
        );
      _inStreaming = true;
      _thinkingText = '';
      _showThinkingContent = false;
      _currentAssistantIndex = assistantIdx;
      _reasoningByIndex[assistantIdx] = '';
      _reasoningDurationByIndex.remove(assistantIdx);
      _thinkingBlocksByIndex[assistantIdx] = <_ThinkingBlock>[
        _ThinkingBlock(createdAt: assistantCreatedAt),
      ];
      _setTransientThinkingStep(
        assistantIdx,
        title: images.isEmpty
            ? AppLocalizations.of(context).composerGeneratingImage
            : AppLocalizations.of(context).composerGeneratingWithReferences,
        icon: Icons.image_outlined,
      );
      _contentSegmentsByIndex[assistantIdx] = loadingContent.trim().isEmpty
          ? <String>[]
          : <String>[loadingContent];
      if (userAttachments.isNotEmpty) {
        _attachmentsByIndex[assistantIdx - 1] = userAttachments;
        _sentComposerImagePaths.addAll(images.map((e) => e.path));
      }
    });
    _markInFlightHistoryDirty();
    _inputController.clear();
    _clearComposerImages(deleteFiles: false);
    _scheduleAutoScroll();

    try {
      final AIImageGenerationResult result = await AIImageGenerationService
          .instance
          .generate(
            params: AIImageGenerationParams(
              prompt: text,
              referenceImagePaths: images.map((e) => e.path).toList(),
            ),
            conversationId: requestCid,
            assistantCreatedAtMs: assistantCreatedAt.millisecondsSinceEpoch,
            toolCallId: callId,
          );
      if (!result.ok) {
        throw Exception(result.error ?? 'Image generation failed.');
      }
      final List<String> markers = result.images
          .map((e) => (e['marker'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      final String content = markers.isEmpty
          ? (result.error ?? 'Image generation completed without images.')
          : markers.join('\n\n');
      setStateIfActive(() {
        if (assistantIdx >= 0 && assistantIdx < _messages.length) {
          final AIMessage current = _messages[assistantIdx];
          _messages[assistantIdx] = AIMessage(
            role: 'assistant',
            content: content,
            createdAt: current.createdAt,
            responseDuration: DateTime.now().difference(assistantCreatedAt),
          );
          _contentSegmentsByIndex[assistantIdx] = <String>[content];
          _finishActiveThinkingBlock(assistantIdx);
        }
      });
      await _enqueueChatHistorySaveByCid(
        requestCid,
        _mergeReasoningForPersistence(List<AIMessage>.from(_messages)),
      );
    } catch (e) {
      final String message = e.toString().replaceFirst('Exception: ', '');
      setStateIfActive(() {
        if (assistantIdx >= 0 && assistantIdx < _messages.length) {
          final AIMessage current = _messages[assistantIdx];
          _messages[assistantIdx] = AIMessage(
            role: 'error',
            content: message,
            createdAt: current.createdAt,
          );
          _contentSegmentsByIndex[assistantIdx] = <String>[message];
          _finishActiveThinkingBlock(assistantIdx);
        }
      });
      if (mounted) UINotifier.error(context, message);
      await _enqueueChatHistorySaveByCid(
        requestCid,
        _mergeReasoningForPersistence(List<AIMessage>.from(_messages)),
      );
    } finally {
      setStateIfActive(() {
        _sending = false;
        _inStreaming = false;
        _currentAssistantIndex = null;
      });
      _inFlightConversationCid = null;
      _scheduleAutoScroll();
    }
  }

  void _removeChatUiStateFromIndex(int startIndex) {
    _thinkingBlocksByIndex.removeWhere((key, _) => key >= startIndex);
    _contentSegmentsByIndex.removeWhere((key, _) => key >= startIndex);
    _reasoningByIndex.removeWhere((key, _) => key >= startIndex);
    _gatewayLogsByIndex.removeWhere((key, _) => key >= startIndex);
    _gatewayLogFilePathByIndex.removeWhere((key, _) => key >= startIndex);
    _reasoningDurationByIndex.removeWhere((key, _) => key >= startIndex);
    _attachmentsByIndex.removeWhere((key, _) => key >= startIndex);
  }

  Future<void> _retryMessageAt(int index) async {
    if (_sending) return;
    if (index < 0 || index >= _messages.length) return;

    int userIndex = -1;
    final AIMessage selected = _messages[index];
    if (selected.role == 'user') {
      userIndex = index;
    } else {
      for (int i = index - 1; i >= 0; i--) {
        if (_messages[i].role == 'user') {
          userIndex = i;
          break;
        }
      }
    }
    if (userIndex < 0 || userIndex >= _messages.length) return;
    final String text = _messages[userIndex].content.trim();
    if (text.isEmpty) return;
    final String conversationCid = (_activeConversationCid ?? '').trim().isEmpty
        ? (await _settings.getActiveConversationCid()).trim()
        : (_activeConversationCid ?? '').trim();
    final int cutoffCreatedAt =
        _messages[userIndex].createdAt.millisecondsSinceEpoch;
    final List<AIMessage> trimmedMessages = List<AIMessage>.from(
      _messages.take(userIndex),
    );

    await _sendMessage(
      overrideText: text,
      retryBaseMessages: trimmedMessages,
      retryConversationCid: conversationCid,
      retryCutoffCreatedAtMs: cutoffCreatedAt,
    );
  }

  Future<void> _sendMessage({
    String? overrideText,
    List<AIMessage>? retryBaseMessages,
    String? retryConversationCid,
    int? retryCutoffCreatedAtMs,
  }) async {
    if (_sending) return;
    final String? override = overrideText?.trim();
    final rawText = (override != null && override.isNotEmpty)
        ? override
        : _inputController.text.trim();
    final List<_ComposerImageAttachment> sendImages =
        (override != null && override.isNotEmpty)
        ? const <_ComposerImageAttachment>[]
        : List<_ComposerImageAttachment>.from(_composerImages);
    if (rawText.isEmpty && sendImages.isEmpty) {
      UINotifier.error(
        context,
        AppLocalizations.of(context).messageCannotBeEmpty,
      );
      return;
    }
    if (_imageDrawMode && override == null && rawText.isEmpty) {
      UINotifier.error(
        context,
        AppLocalizations.of(context).composerImagePromptRequired,
      );
      return;
    }
    final text = rawText.isNotEmpty
        ? rawText
        : AppLocalizations.of(context).composerAnalyzeImageFallbackPrompt;
    _setState(() {
      _sending = true;
    });

    final int sendEpoch = ++_sendEpoch;
    _activeSendEpoch = sendEpoch;
    _ctxDebounceTimer?.cancel();
    _ctxDebounceTimer = null;
    final String retryCid = (retryConversationCid ?? '').trim();
    final int retryCutoff = retryCutoffCreatedAtMs ?? 0;
    final bool isRetry = retryBaseMessages != null && retryCutoff > 0;
    final List<AIMessage>? retryBase = retryBaseMessages == null
        ? null
        : List<AIMessage>.from(retryBaseMessages);
    final String initialCid = retryCid.isNotEmpty
        ? retryCid
        : (_activeConversationCid ?? '').trim();
    String requestCid = initialCid;
    try {
      if (requestCid.isEmpty) {
        requestCid = await _settings.getActiveConversationCid();
      }
      requestCid = requestCid.trim();
      _inFlightConversationCid = requestCid.isEmpty ? null : requestCid;
      if (isRetry && requestCid.isNotEmpty) {
        _chatHistoryWriteEpoch++;
        _chat.blockConversationPersistenceBefore(
          cid: requestCid,
          createdAtMs: retryCutoff,
        );
        await _settings.truncateConversationAfterCreatedAt(
          requestCid,
          retryCutoff,
          notify: false,
        );
      }
      final List<AIMessage> baseMessagesForNewTurn =
          retryBase ?? List<AIMessage>.from(_messages);
      final bool shouldAnalyzeInitialIntent =
          _shouldAnalyzeIntentForConversation(
            requestCid,
            isFirstUserTurn: !baseMessagesForNewTurn.any(
              (m) => m.role == 'user',
            ),
          );
      if (_imageDrawMode && override == null) {
        await _sendImageGenerationMessage(
          text: text,
          images: sendImages,
          requestCid: requestCid,
          sendEpoch: sendEpoch,
        );
        return;
      }

      final Object? userApiContent = await _buildChatUserApiContent(
        text: text,
        currentImages: sendImages,
        historyMessages: baseMessagesForNewTurn,
      );
      void setStateIfActive(VoidCallback fn) {
        if (!mounted) return;
        if (_activeSendEpoch != sendEpoch) return;
        _setState(fn);
      }

      // 先本地追加用户消息，提升即时反馈
      final DateTime userCreatedAt = DateTime.now();
      final int userIdx = baseMessagesForNewTurn.length;
      final List<EvidenceImageAttachment> userAttachments =
          _composerImagesToMessageAttachments(sendImages);
      final String localUserContent = _withComposerImageMarkers(
        text,
        userAttachments,
      );
      setStateIfActive(() {
        if (retryBase != null) {
          _removeChatUiStateFromIndex(userIdx);
        }
        _messages = List<AIMessage>.from(baseMessagesForNewTurn)
          ..add(
            AIMessage(
              role: 'user',
              content: localUserContent,
              createdAt: userCreatedAt,
            ),
          );
        if (userAttachments.isNotEmpty) {
          _attachmentsByIndex[userIdx] = userAttachments;
          _sentComposerImagePaths.addAll(sendImages.map((e) => e.path));
        }
      });
      if (override == null || override.isEmpty) {
        _inputController.clear();
        _clearComposerImages(deleteFiles: false);
      }
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
          _thinkingBlocksByIndex[assistantIdx] = <_ThinkingBlock>[first];
          _setTransientThinkingStep(
            assistantIdx,
            title: _isZhLocale() ? '正在准备请求' : 'Preparing request',
            icon: Icons.autorenew_rounded,
          );
          _contentSegmentsByIndex[assistantIdx] = <String>[];
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

        try {
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

            final bool shouldAnalyzeIntent =
                clarifyAsk != null || shouldAnalyzeInitialIntent;
            if (!localOnlyResponse && shouldAnalyzeIntent) {
              await FlutterLogger.nativeInfo(
                'ChatFlow',
                'phase1 intent begin text="${text.length > 200 ? (text.substring(0, 200) + '…') : text}"',
              );
              _appendAgentLog(
                _isZhLocale() ? '阶段 1/4：意图分析' : 'Phase 1/4: intent analysis',
                bullet: false,
              );
              setStateIfActive(() {
                _setTransientThinkingStep(
                  assistantIdx,
                  title: _isZhLocale() ? '正在分析问题' : 'Analyzing request',
                  icon: Icons.search_outlined,
                );
              });
              final String preview = _clipOneLine(analyzeInput, 80);
              _appendAgentLog(
                _isZhLocale()
                    ? '调用意图分析模型…${preview.isEmpty ? '' : ' input="' + preview + '"'}'
                    : 'Calling intent model…${preview.isEmpty ? '' : ' input=\"' + preview + '\"'}',
              );
              setStateIfActive(() {
                _setTransientThinkingStep(
                  assistantIdx,
                  title: _isZhLocale() ? '正在调用意图分析模型' : 'Calling intent model',
                  icon: Icons.manage_search_rounded,
                );
              });
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
              _markIntentAnalyzedForConversation(requestCid);
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
            final IntentResult? resolvedIntent = intent;

            // 清理澄清状态，避免污染下一轮
            if (_clarifyState != null) {
              _appendAgentLog(
                _isZhLocale()
                    ? '当前不预设固定时间窗：退出澄清流程'
                    : 'No fixed time range preset: exiting clarification flow',
              );
              _clarifyState = null;
            }

            if (resolvedIntent != null) {
              await FlutterLogger.nativeInfo(
                'ChatFlow',
                'phase1 intent ok (no-preset-window) intent=${resolvedIntent.intent} summary=${resolvedIntent.intentSummary}',
              );
              _appendAgentLog(
                _isZhLocale()
                    ? '意图已确认：${resolvedIntent.intentSummary}（不预设时间窗，由模型按需检索）'
                    : 'Intent confirmed: ${resolvedIntent.intentSummary} (no preset time window; model retrieves as needed)',
              );
              setStateIfActive(() {
                _setTransientThinkingStep(
                  assistantIdx,
                  title: _isZhLocale() ? '正在更新对话标题' : 'Updating chat title',
                  subtitle: _formatIntentSubtitle(resolvedIntent),
                  icon: Icons.drive_file_rename_outline_rounded,
                );
              });
              _renameActiveConversationTo(
                resolvedIntent.intentSummary,
                conversationCid: requestCid,
              );
            }
            _appendAgentLog(
              resolvedIntent == null
                  ? (_isZhLocale() ? '生成回答' : 'Generating answer')
                  : (_isZhLocale()
                        ? '阶段 3/4：生成回答'
                        : 'Phase 3/4: generating answer'),
              bullet: false,
            );
            setStateIfActive(() {
              _setTransientThinkingStep(
                assistantIdx,
                title: _isZhLocale() ? '正在生成回答' : 'Generating answer',
                icon: Icons.auto_awesome_outlined,
              );
            });
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
              uiUserCreatedAtMs: userCreatedAt.millisecondsSinceEpoch,
              uiAssistantCreatedAtMs: createdAt.millisecondsSinceEpoch,
              reasoningLevel: _reasoningLevel,
              userApiContent: userApiContent,
              localUserMessageForHistory: localUserContent,
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
                        if (t == 'tool_batch_begin' || t == 'tool_call_end') {
                          unawaited(
                            FlutterLogger.nativeInfo(
                              'AI_IMAGE',
                              'ui.stream_event type=$t idx=$idx payload=${evt.data}',
                            ),
                          );
                        }
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
                      _appendReasoningDeltaToTimeline(idx, reasoningDelta);
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
                    final bool hasGeneratedImageMarker = target.content
                        .contains(RegExp(r'\[generated-image(?:-loading)?:'));
                    final String base =
                        _replaceAssistantContentOnNextToken &&
                            !hasGeneratedImageMarker
                        ? ''
                        : target.content;
                    final String incoming = evt.data;
                    final updated = AIMessage(
                      role: 'assistant',
                      content: base + incoming,
                      createdAt: target.createdAt, // 保留初始创建时间以准确计算思考耗时
                      reasoningContent: target.reasoningContent,
                      reasoningDuration: target.reasoningDuration,
                      uiThinkingJson: target.uiThinkingJson,
                      usagePromptTokens: target.usagePromptTokens,
                      usageCompletionTokens: target.usageCompletionTokens,
                      usageTotalTokens: target.usageTotalTokens,
                      usageCacheHitTokens: target.usageCacheHitTokens,
                      usageCacheMissTokens: target.usageCacheMissTokens,
                      responseDuration: target.responseDuration,
                    );
                    final newList = List<AIMessage>.from(_messages);
                    newList[targetIdx] = updated;
                    _messages = newList;
                    _replaceAssistantContentOnNextToken = false;

                    if (currentIdx != null && incoming.isNotEmpty) {
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

            // Providers usually return usage only in the terminal response. Merge
            // final metadata independently from final text so input/output/tok/s
            // stats are not lost when the text has already streamed into the UI.
            if (_mergeCompletedAssistantIntoCurrentBubble(completed)) {
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
                if (assistantIdx >= 0 && assistantIdx < _messages.length) {
                  _syncContentSegmentsForFullContent(
                    assistantIdx,
                    _messages[assistantIdx].content,
                  );
                }
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
        final DateTime assistantCreatedAt = DateTime.now();
        setStateIfActive(() {
          _thinkingText = '';
          _reasoningByIndex[assistantIdx] = '';
          _reasoningDurationByIndex.remove(assistantIdx);
          _messages = List<AIMessage>.from(_messages)
            ..add(
              AIMessage(
                role: 'assistant',
                content: '',
                createdAt: assistantCreatedAt,
              ),
            );
          _currentAssistantIndex = assistantIdx;
          _inStreaming = true;
          final _ThinkingBlock first = _ThinkingBlock(
            createdAt: assistantCreatedAt,
          );
          _thinkingBlocksByIndex[assistantIdx] = <_ThinkingBlock>[first];
          _setTransientThinkingStep(
            assistantIdx,
            title: _isZhLocale() ? '正在准备请求' : 'Preparing request',
            icon: Icons.autorenew_rounded,
          );
          _contentSegmentsByIndex[assistantIdx] = <String>[];
        });
        _appendAgentLog(
          _isZhLocale() ? '开始处理本次请求' : 'Start handling request',
          assistantIndex: assistantIdx,
          bullet: false,
        );

        try {
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

            final bool shouldAnalyzeIntent =
                clarifyAsk != null || shouldAnalyzeInitialIntent;
            if (!localOnlyResponse && shouldAnalyzeIntent) {
              _appendAgentLog(
                _isZhLocale() ? '阶段 1/4：意图分析' : 'Phase 1/4: intent analysis',
                assistantIndex: assistantIdx,
                bullet: false,
              );
              setStateIfActive(() {
                _setTransientThinkingStep(
                  assistantIdx,
                  title: _isZhLocale() ? '正在分析问题' : 'Analyzing request',
                  icon: Icons.search_outlined,
                );
              });
              await FlutterLogger.nativeInfo(
                'ChatFlow',
                'phase1 intent(begin, non-stream)',
              );
              final String preview = _clipOneLine(analyzeInput, 80);
              _appendAgentLog(
                _isZhLocale()
                    ? '调用意图分析模型…${preview.isEmpty ? '' : ' input="' + preview + '"'}'
                    : 'Calling intent model…${preview.isEmpty ? '' : ' input=\"' + preview + '\"'}',
                assistantIndex: assistantIdx,
              );
              setStateIfActive(() {
                _setTransientThinkingStep(
                  assistantIdx,
                  title: _isZhLocale() ? '正在调用意图分析模型' : 'Calling intent model',
                  icon: Icons.manage_search_rounded,
                );
              });
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
              _markIntentAnalyzedForConversation(requestCid);
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
              _finishActiveThinkingBlock(assistantIdx);
              _inStreaming = false;
              _currentAssistantIndex = null;
              _messages[lastIdx] = AIMessage(
                role: 'assistant',
                content: localAssistantText,
                createdAt: last.createdAt,
              );
              _syncContentSegmentsForFullContent(
                assistantIdx,
                localAssistantText,
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

          final IntentResult? resolvedIntent = intent;

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

          if (resolvedIntent != null) {
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
            setStateIfActive(() {
              _setTransientThinkingStep(
                assistantIdx,
                title: _isZhLocale() ? '正在更新对话标题' : 'Updating chat title',
                subtitle: _formatIntentSubtitle(resolvedIntent),
                icon: Icons.drive_file_rename_outline_rounded,
              );
            });
            _renameActiveConversationTo(
              resolvedIntent.intentSummary,
              conversationCid: requestCid,
            );
          }
          _appendAgentLog(
            resolvedIntent == null
                ? (_isZhLocale() ? '生成回答' : 'Generating answer')
                : (_isZhLocale()
                      ? '阶段 3/4：生成回答'
                      : 'Phase 3/4: generating answer'),
            assistantIndex: assistantIdx,
            bullet: false,
          );
          setStateIfActive(() {
            _setTransientThinkingStep(
              assistantIdx,
              title: _isZhLocale() ? '正在生成回答' : 'Generating answer',
              icon: Icons.auto_awesome_outlined,
            );
          });
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
            uiUserCreatedAtMs: userCreatedAt.millisecondsSinceEpoch,
            uiAssistantCreatedAtMs: assistantCreatedAt.millisecondsSinceEpoch,
            reasoningLevel: _reasoningLevel,
            userApiContent: userApiContent,
            localUserMessageForHistory: localUserContent,
            emitEvent: (evt) {
              if (!mounted) return;
              if (_activeSendEpoch != sendEpoch) return;
              if (evt.kind == 'ui') {
                final Map<String, dynamic>? payload = _tryParseJsonMap(
                  evt.data,
                );
                if (payload == null) return;
                final String t = (payload['type'] as String?)?.trim() ?? '';
                if (t == 'gateway_log') return;
                if (t == 'tool_batch_begin' || t == 'tool_call_end') {
                  unawaited(
                    FlutterLogger.nativeInfo(
                      'AI_IMAGE',
                      'ui.emit_event type=$t idx=$assistantIdx payload=${evt.data}',
                    ),
                  );
                }
                setStateIfActive(() => _handleAiUiEvent(assistantIdx, payload));
                _scheduleAutoScroll();
                return;
              }
              if (evt.kind != 'reasoning') return;
              final String reasoningDelta = _showAgentProgressLogs
                  ? evt.data
                  : _filterReasoningChunkForUi(evt.data);
              if (reasoningDelta.trim().isEmpty) return;
              setStateIfActive(() {
                _appendReasoningDeltaToTimeline(assistantIdx, reasoningDelta);
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
            _finishActiveThinkingBlock(assistantIdx);
            _inStreaming = false;
            _currentAssistantIndex = null;
            _messages[lastIdx] = AIMessage(
              role: 'assistant',
              content: assistant.content,
              createdAt: _messages[lastIdx].createdAt,
              reasoningContent: assistant.reasoningContent,
              reasoningDuration: assistant.reasoningDuration,
              uiThinkingJson: assistant.uiThinkingJson,
              usagePromptTokens: assistant.usagePromptTokens,
              usageCompletionTokens: assistant.usageCompletionTokens,
              usageTotalTokens: assistant.usageTotalTokens,
              usageCacheHitTokens: assistant.usageCacheHitTokens,
              usageCacheMissTokens: assistant.usageCacheMissTokens,
              responseDuration: assistant.responseDuration,
            );
            _syncContentSegmentsForFullContent(assistantIdx, assistant.content);
          });
          _scheduleAutoScroll();
          if (resolvedIntent != null) {
            _lastIntent = resolvedIntent;
          }
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
            _finishActiveThinkingBlock(assistantIdx);
            _inStreaming = false;
            _currentAssistantIndex = null;
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
