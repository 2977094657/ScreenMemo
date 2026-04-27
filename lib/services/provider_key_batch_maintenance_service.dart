import 'dart:convert';
import 'dart:math';

import 'ai_providers_service.dart';
import 'ai_request_gateway.dart';
import 'ai_settings_service.dart';
import 'flutter_logger.dart';
import 'screenshot_database.dart';

class ProviderKeyModelRefreshFailure {
  const ProviderKeyModelRefreshFailure({
    required this.key,
    required this.errorMessage,
  });

  final AIProviderKey key;
  final String errorMessage;
}

class ProviderKeyProbeResult {
  const ProviderKeyProbeResult({
    required this.key,
    required this.success,
    required this.deleted,
    required this.attemptsUsed,
    required this.modelsTried,
    required this.failureMessages,
    this.successModel,
    this.responsePreview,
    this.skipped = false,
  });

  final AIProviderKey key;
  final bool success;
  final bool deleted;
  final bool skipped;
  final int attemptsUsed;
  final List<String> modelsTried;
  final List<String> failureMessages;
  final String? successModel;
  final String? responsePreview;
}

class ProviderKeyBatchRefreshResult {
  const ProviderKeyBatchRefreshResult({
    required this.processedKeyCount,
    required this.refreshedKeys,
    required this.modelFailures,
    required this.probeResults,
  });

  final int processedKeyCount;
  final List<AIProviderKey> refreshedKeys;
  final List<ProviderKeyModelRefreshFailure> modelFailures;
  final List<ProviderKeyProbeResult> probeResults;

  int get refreshedCount => refreshedKeys.length;

  int get rescuedCount => probeResults.where((item) => item.success).length;

  int get deletedCount => probeResults.where((item) => item.deleted).length;

  int get skippedProbeCount =>
      probeResults.where((item) => item.skipped).length;
}

typedef ProviderKeyBatchProgressCallback =
    void Function(ProviderKeyBatchProgress progress);

class ProviderKeyBatchProgress {
  const ProviderKeyBatchProgress({
    required this.phaseLabel,
    required this.current,
    required this.total,
    required this.message,
  });

  final String phaseLabel;
  final int current;
  final int total;
  final String message;

  double get progressValue {
    if (total <= 0) return 0;
    final int safeCurrent = min(max(current, 0), total);
    return safeCurrent / total;
  }

  String get fractionLabel {
    final int safeTotal = total <= 0 ? 1 : total;
    final int safeCurrent = min(max(current, 0), safeTotal);
    return '$safeCurrent/$safeTotal';
  }
}

class ProviderKeyBatchMaintenanceService {
  ProviderKeyBatchMaintenanceService._();

  static final ProviderKeyBatchMaintenanceService instance =
      ProviderKeyBatchMaintenanceService._();

  final AIProvidersService _providers = AIProvidersService.instance;
  final AIRequestGateway _gateway = AIRequestGateway.instance;
  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  final Random _random = Random();

  Future<ProviderKeyBatchRefreshResult> refreshModelsAndProbeFailures({
    required AIProvider provider,
    required List<AIProviderKey> keys,
    int probeAttempts = 3,
    bool deleteAfterFailedProbe = true,
    Duration timeout = const Duration(seconds: 20),
    ProviderKeyBatchProgressCallback? onProgress,
  }) async {
    final List<AIProviderKey> enabledKeys = keys
        .where(
          (key) =>
              key.enabled && key.id != null && key.apiKey.trim().isNotEmpty,
        )
        .toList(growable: false);
    final refreshedKeys = <AIProviderKey>[];
    final modelFailures = <ProviderKeyModelRefreshFailure>[];
    final successfulModelPool = <String>[];

    void emitProgress({
      required String phaseLabel,
      required int current,
      required int total,
      required String message,
    }) {
      final callback = onProgress;
      if (callback == null) return;
      callback(
        ProviderKeyBatchProgress(
          phaseLabel: phaseLabel,
          current: current,
          total: total,
          message: message,
        ),
      );
    }

    for (int index = 0; index < enabledKeys.length; index++) {
      final key = enabledKeys[index];
      emitProgress(
        phaseLabel: '刷新模型',
        current: index + 1,
        total: enabledKeys.length,
        message: '正在刷新 ${key.name} 的模型列表',
      );
      try {
        final List<String> models = await _providers.fetchModels(
          provider: provider,
          apiKey: key.apiKey,
        );
        await _saveKeyModels(
          keyId: key.id!,
          models: models,
          clearErrorState: true,
        );
        await _providers.markProviderKeySuccess(key.id!);
        refreshedKeys.add(key);
        successfulModelPool.addAll(models);
        emitProgress(
          phaseLabel: '刷新模型',
          current: index + 1,
          total: enabledKeys.length,
          message: '${key.name} 模型列表刷新成功，获取到 ${models.length} 个模型',
        );
      } catch (error) {
        final String errorText = _clip(error.toString(), 800);
        await _providers.markProviderKeyFailure(
          keyId: key.id!,
          errorType: 'models_fetch_failed',
          errorMessage: errorText,
          incrementFailure: true,
        );
        modelFailures.add(
          ProviderKeyModelRefreshFailure(key: key, errorMessage: errorText),
        );
        await _logWarn(
          '[ProviderKeyBatch] fetch models failed key=${key.name}#${key.id} error=$errorText',
        );
        emitProgress(
          phaseLabel: '刷新模型',
          current: index + 1,
          total: enabledKeys.length,
          message: '${key.name} 模型列表刷新失败：${_clip(errorText, 120)}',
        );
      }
    }

    if (provider.id != null) {
      await _providers.syncProviderModelsFromKeys(provider.id!);
    }

    final currentKeys = provider.id == null
        ? enabledKeys
        : await _providers.listProviderKeys(provider.id!);
    final modelPool = _mergeModels(<Iterable<String>>[
      successfulModelPool,
      currentKeys.expand((key) => key.models),
      provider.models,
      _defaultProbeModels(provider.type),
    ]);

    final probeResults = <ProviderKeyProbeResult>[];
    for (int failureIndex = 0;
        failureIndex < modelFailures.length;
        failureIndex++) {
      final failure = modelFailures[failureIndex];
      final AIProviderKey latestKey = currentKeys.firstWhere(
        (item) => item.id == failure.key.id,
        orElse: () => failure.key,
      );
      final List<String> candidates = _resolveProbeModels(
        key: latestKey,
        provider: provider,
        sharedModels: modelPool,
      );
      if (candidates.isEmpty) {
        probeResults.add(
          ProviderKeyProbeResult(
            key: latestKey,
            success: false,
            deleted: false,
            skipped: true,
            attemptsUsed: 0,
            modelsTried: const <String>[],
            failureMessages: const <String>['未找到可用于连续测试的候选模型'],
          ),
        );
        emitProgress(
          phaseLabel: '连续测试',
          current: failureIndex + 1,
          total: modelFailures.length,
          message: '检测到 ${latestKey.name} 刷新失败，但没有可用模型，已跳过连续测试',
        );
        continue;
      }

      emitProgress(
        phaseLabel: '连续测试',
        current: failureIndex + 1,
        total: modelFailures.length,
        message:
            '检测到 ${latestKey.name} 刷新失败，准备进行最多 $probeAttempts 次连续测试',
      );
      final ProviderKeyProbeResult probe = await _probeKey(
        provider: provider,
        key: latestKey,
        candidateModels: candidates,
        attempts: probeAttempts,
        timeout: timeout,
        onAttemptStart: (attemptNumber, totalAttempts, model) {
          emitProgress(
            phaseLabel: '连续测试',
            current: failureIndex + 1,
            total: modelFailures.length,
            message:
                '检测到 ${latestKey.name} 刷新失败，正在进行第 $attemptNumber/$totalAttempts 次连续测试（模型：$model）',
          );
        },
        onAttemptFailure: (attemptNumber, totalAttempts, model, errorText) {
          final bool willRetry = attemptNumber < totalAttempts;
          emitProgress(
            phaseLabel: '连续测试',
            current: failureIndex + 1,
            total: modelFailures.length,
            message: willRetry
                ? '${latestKey.name} 第 $attemptNumber/$totalAttempts 次连续测试失败：${_clip(errorText, 120)}，准备重试'
                : '${latestKey.name} 第 $attemptNumber/$totalAttempts 次连续测试失败：${_clip(errorText, 120)}',
          );
        },
      );
      probeResults.add(probe);

      if (probe.success && probe.successModel != null && latestKey.id != null) {
        final List<String> mergedModels = _mergeModels(<Iterable<String>>[
          latestKey.models,
          <String>[probe.successModel!],
        ]);
        await _saveKeyModels(
          keyId: latestKey.id!,
          models: mergedModels,
          clearErrorState: false,
        );
        emitProgress(
          phaseLabel: '连续测试',
          current: failureIndex + 1,
          total: modelFailures.length,
          message: '${latestKey.name} 连续测试成功，恢复模型 ${probe.successModel!}',
        );
      } else if (!probe.success && probe.deleted && latestKey.id != null) {
        await _providers.deleteProviderKey(latestKey.id!);
        emitProgress(
          phaseLabel: '连续测试',
          current: failureIndex + 1,
          total: modelFailures.length,
          message: '${latestKey.name} 连续测试失败，已删除该 Key',
        );
      } else if (!probe.success &&
          deleteAfterFailedProbe &&
          !probe.deleted &&
          latestKey.id != null) {
        await _providers.deleteProviderKey(latestKey.id!);
        probeResults[probeResults.length - 1] = ProviderKeyProbeResult(
          key: probe.key,
          success: false,
          deleted: true,
          skipped: probe.skipped,
          attemptsUsed: probe.attemptsUsed,
          modelsTried: probe.modelsTried,
          failureMessages: probe.failureMessages,
          successModel: probe.successModel,
          responsePreview: probe.responsePreview,
        );
        emitProgress(
          phaseLabel: '连续测试',
          current: failureIndex + 1,
          total: modelFailures.length,
          message: '${latestKey.name} 连续测试全部失败，已删除该 Key',
        );
      } else if (!probe.success && probe.skipped) {
        emitProgress(
          phaseLabel: '连续测试',
          current: failureIndex + 1,
          total: modelFailures.length,
          message: '${latestKey.name} 连续测试已跳过',
        );
      } else if (!probe.success) {
        emitProgress(
          phaseLabel: '连续测试',
          current: failureIndex + 1,
          total: modelFailures.length,
          message: '${latestKey.name} 连续测试全部失败，但保留该 Key',
        );
      }
    }

    if (provider.id != null) {
      await _providers.syncProviderModelsFromKeys(provider.id!);
    }

    return ProviderKeyBatchRefreshResult(
      processedKeyCount: enabledKeys.length,
      refreshedKeys: refreshedKeys,
      modelFailures: modelFailures,
      probeResults: probeResults,
    );
  }

  Future<ProviderKeyProbeResult> _probeKey({
    required AIProvider provider,
    required AIProviderKey key,
    required List<String> candidateModels,
    required int attempts,
    required Duration timeout,
    void Function(int attemptNumber, int totalAttempts, String model)?
    onAttemptStart,
    void Function(
      int attemptNumber,
      int totalAttempts,
      String model,
      String errorText,
    )?
    onAttemptFailure,
  }) async {
    if (key.id == null) {
      return ProviderKeyProbeResult(
        key: key,
        success: false,
        deleted: false,
        skipped: true,
        attemptsUsed: 0,
        modelsTried: const <String>[],
        failureMessages: const <String>['缺少 Key ID，无法执行连续测试'],
      );
    }

    final List<String> modelsTried = <String>[];
    final List<String> failureMessages = <String>[];
    final int safeAttempts = attempts <= 0 ? 1 : attempts;

    for (int attempt = 0; attempt < safeAttempts; attempt++) {
      final String model = candidateModels[attempt % candidateModels.length];
      modelsTried.add(model);
      final String token = _randomProbeToken();
      final String expected = token.substring(token.length - 12);
      onAttemptStart?.call(attempt + 1, safeAttempts, model);
      try {
        final AIEndpoint endpoint = AIEndpoint(
          groupId: -1 * (provider.id ?? 0).abs(),
          providerId: provider.id,
          providerName: provider.name,
          providerType: provider.type,
          providerKeyId: key.id,
          providerKeyName: key.name,
          providerKeyPriority: key.priority,
          baseUrl: _resolveBaseUrl(provider),
          apiKey: key.apiKey,
          model: model,
          chatPath: _resolveChatPath(provider),
          useResponseApi: provider.useResponseApi,
        );
        final List<AIMessage> messages = <AIMessage>[
          AIMessage(
            role: 'system',
            content:
                'Reply with exactly the requested substring. No markdown. No explanation. No punctuation.',
          ),
          AIMessage(
            role: 'user',
            content:
                'Return only the last 12 characters of this random string. Do not add punctuation or explanation.\n$token',
          ),
        ];
        final AIGatewayResult result = await _gateway.complete(
          endpoints: <AIEndpoint>[endpoint],
          messages: messages,
          responseStartMarker: '',
          timeout: timeout,
          preferStreaming: false,
          logContext: 'provider_key_probe',
          trackKeyStats: false,
        );
        final String response = result.content.trim();
        if (!_probeResponseMatches(response, expected)) {
          throw Exception(
            '连续测试响应不匹配：期望包含 $expected，实际返回 ${_clip(response, 120)}',
          );
        }
        await _providers.markProviderKeySuccess(key.id!);
        return ProviderKeyProbeResult(
          key: key,
          success: true,
          deleted: false,
          attemptsUsed: attempt + 1,
          modelsTried: List<String>.unmodifiable(modelsTried),
          failureMessages: List<String>.unmodifiable(failureMessages),
          successModel: model,
          responsePreview: _clip(response, 120),
        );
      } catch (error) {
        final String errorText = _clip(error.toString(), 800);
        failureMessages.add('Attempt ${attempt + 1}: $errorText');
        onAttemptFailure?.call(attempt + 1, safeAttempts, model, errorText);
        await _providers.markProviderKeyFailure(
          keyId: key.id!,
          errorType: _classifyError(error),
          errorMessage: errorText,
          incrementFailure: true,
        );
        await _logWarn(
          '[ProviderKeyBatch] probe failed key=${key.name}#${key.id} model=$model attempt=${attempt + 1}/$safeAttempts error=$errorText',
        );
      }
    }

    return ProviderKeyProbeResult(
      key: key,
      success: false,
      deleted: false,
      attemptsUsed: safeAttempts,
      modelsTried: List<String>.unmodifiable(modelsTried),
      failureMessages: List<String>.unmodifiable(failureMessages),
    );
  }

  Future<void> _saveKeyModels({
    required int keyId,
    required List<String> models,
    required bool clearErrorState,
  }) async {
    await _db.updateAIProviderKey(
      id: keyId,
      modelsJson: jsonEncode(_mergeModels(<Iterable<String>>[models])),
      clearErrorState: clearErrorState,
    );
  }

  List<String> _resolveProbeModels({
    required AIProviderKey key,
    required AIProvider provider,
    required List<String> sharedModels,
  }) {
    return _mergeModels(<Iterable<String>>[
      key.models,
      <String>[provider.defaultModel],
      sharedModels,
      provider.models,
      _defaultProbeModels(provider.type),
    ]);
  }

  List<String> _mergeModels(Iterable<Iterable<String>> groups) {
    final seen = <String>{};
    final out = <String>[];
    for (final group in groups) {
      for (final raw in group) {
        final String model = raw.trim();
        if (model.isEmpty) continue;
        final String normalized = model.toLowerCase();
        if (seen.add(normalized)) {
          out.add(model);
        }
      }
    }
    return out;
  }

  Iterable<String> _defaultProbeModels(String type) sync* {
    switch (type.trim().toLowerCase()) {
      case AIProviderTypes.openai:
        yield 'gpt-4o-mini';
        break;
      case AIProviderTypes.claude:
        yield 'claude-3-5-haiku-latest';
        yield 'claude-3-haiku-20240307';
        break;
      case AIProviderTypes.gemini:
        yield 'gemini-2.0-flash';
        yield 'gemini-1.5-flash';
        break;
      default:
        break;
    }
  }

  String _resolveBaseUrl(AIProvider provider) {
    final String base = (provider.baseUrl ?? '').trim();
    if (base.isNotEmpty) return base;
    switch (provider.type.trim().toLowerCase()) {
      case AIProviderTypes.openai:
        return 'https://api.openai.com';
      case AIProviderTypes.claude:
        return 'https://api.anthropic.com';
      case AIProviderTypes.gemini:
        return 'https://generativelanguage.googleapis.com';
      default:
        throw Exception('Base URL is required for provider ${provider.type}.');
    }
  }

  String _resolveChatPath(AIProvider provider) {
    final String path = (provider.chatPath ?? '').trim();
    return path.isEmpty ? '/v1/chat/completions' : path;
  }

  bool _probeResponseMatches(String response, String expected) {
    final String normalized = response
        .replaceAll('`', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
    return normalized.contains(expected);
  }

  String _randomProbeToken() {
    final int stamp = DateTime.now().microsecondsSinceEpoch;
    return '${_randomAscii(10)}$stamp${_randomChinese(4)}${_randomAscii(8)}';
  }

  String _randomAscii(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(chars[_random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  String _randomChinese(int length) {
    const chars = <String>[
      'x',
      'q',
      'm',
      'z',
      'r',
      't',
      'p',
      'k',
      'y',
      'n',
      'd',
      'h',
    ];
    final buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(chars[_random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  String _classifyError(Object error) {
    final String text = error.toString().toLowerCase();
    final Match? codeMatch = RegExp(
      r'request failed:\s*(\d{3})',
    ).firstMatch(text);
    final int? code = codeMatch == null
        ? null
        : int.tryParse(codeMatch.group(1)!);
    if (code == 401 || code == 403) return 'auth_failed';
    if (text.contains('probe response mismatch') ||
        text.contains('连续测试响应不匹配')) {
      return 'probe_invalid_response';
    }
    if (text.contains('model_not_found') ||
        text.contains('unsupported_model') ||
        text.contains('does not exist') ||
        (text.contains('not found') && text.contains('model'))) {
      return 'model_not_found';
    }
    if (code == 408 || code == 429 || (code != null && code >= 500)) {
      return 'retryable';
    }
    if (text.contains('timeout') ||
        text.contains('socket') ||
        text.contains('connection') ||
        text.contains('network')) {
      return 'retryable';
    }
    if (code != null && code >= 400 && code < 500) return 'fatal';
    return 'probe_failed';
  }

  String _clip(String text, [int max = 240]) {
    final String value = text.trim();
    if (value.length <= max) return value;
    return '${value.substring(0, max)}...';
  }

  Future<void> _logWarn(String message) async {
    try {
      await FlutterLogger.nativeWarn('AI', message);
    } catch (_) {}
  }
}
