import 'dart:async';
import 'package:flutter/material.dart';
import 'package:screen_memo/widgets/ui_components.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../services/ai_providers_service.dart';
import '../services/provider_key_batch_maintenance_service.dart';
import '../theme/app_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/model_icon_utils.dart';
import '../widgets/ui_dialog.dart';
import '../services/flutter_logger.dart';

enum _ProviderKeySortMode {
  runtime,
  successDesc,
  recentSuccessDesc,
  failureDesc,
  continuousFailureDesc,
  newestDesc,
}

/// 提供商编辑页（新建/编辑）
class ProviderEditPage extends StatefulWidget {
  final int? providerId;

  const ProviderEditPage({super.key, this.providerId});

  @override
  State<ProviderEditPage> createState() => _ProviderEditPageState();
}

class _ProviderEditPageState extends State<ProviderEditPage> {
  final _svc = AIProvidersService.instance;
  final _batchSvc = ProviderKeyBatchMaintenanceService.instance;

  final _nameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _chatPathCtrl = TextEditingController(text: '/v1/chat/completions');
  final _modelsPathCtrl = TextEditingController(
    text: defaultModelsPathForType(AIProviderTypes.openai),
  );
  final _azureApiVerCtrl = TextEditingController(text: '2024-02-15');
  final _modelInputCtrl = TextEditingController();

  String _type = AIProviderTypes.openai;
  bool _useResponseApi = false;

  bool _loading = true;
  bool _saving = false;
  bool _fetching = false;
  bool _batchRunning = false;
  ProviderKeyBatchProgress? _batchProgress;

  _ProviderKeySortMode _keySortMode = _ProviderKeySortMode.runtime;

  List<String> _models = <String>[];
  List<AIProviderKey> _keys = <AIProviderKey>[];
  AIProvider? _loaded;
  bool _geminiNoticeShown = false;

  Future<void> _showGeminiRegionDialog() async {
    if (!mounted) return;
    await showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).geminiRegionDialogTitle,
      message: AppLocalizations.of(context).geminiRegionDialogMessage,
      actions: [UIDialogAction(text: AppLocalizations.of(context).gotIt)],
    );
  }

  void _showGeminiRegionNotice() {
    if (_geminiNoticeShown || !mounted) return;
    _geminiNoticeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      UINotifier.warning(
        context,
        l10n.geminiRegionToast,
        duration: const Duration(seconds: 4),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  Future<void> _initLoad() async {
    try {
      if (widget.providerId != null) {
        final p = await _svc.getProvider(widget.providerId!);
        if (p == null) {
          if (mounted) {
            UINotifier.error(
              context,
              AppLocalizations.of(context).providerNotFound,
            );
            Navigator.of(context).pop();
          }
          return;
        }
        _loaded = p;
        _keys = await _svc.listProviderKeys(p.id!);
        _nameCtrl.text = p.name;
        _type = p.type;
        _baseUrlCtrl.text = p.baseUrl ?? '';
        _chatPathCtrl.text = p.chatPath ?? '/v1/chat/completions';
        final path = p.modelsPath.trim();
        if (path.isEmpty) {
          _modelsPathCtrl.text = defaultModelsPathForType(_type);
        } else {
          _modelsPathCtrl.text = path;
        }
        _useResponseApi = p.useResponseApi;
        _models = _aggregateKeyModels(_keys);
        if (_models.isEmpty) _models = List<String>.from(p.models);
        if (p.type == AIProviderTypes.azureOpenAI) {
          final v = (p.extra['azure_api_version'] as String?) ?? '2024-02-15';
          _azureApiVerCtrl.text = v;
        }
        if (p.type == AIProviderTypes.gemini) {
          _showGeminiRegionNotice();
        }
      } else {
        _applyTypeDefaults(AIProviderTypes.openai, initial: true);
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).pleaseTryAgain);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _chatPathCtrl.dispose();
    _modelsPathCtrl.dispose();
    _azureApiVerCtrl.dispose();
    _modelInputCtrl.dispose();
    super.dispose();
  }

  List<String> _aggregateKeyModels(List<AIProviderKey> keys) {
    final seen = <String>{};
    final out = <String>[];
    for (final key in keys.where((k) => k.enabled)) {
      for (final model in key.models) {
        final m = model.trim();
        if (m.isEmpty) continue;
        if (seen.add(m.toLowerCase())) out.add(m);
      }
    }
    return out;
  }

  Future<void> _reloadKeys() async {
    final id = _loaded?.id;
    if (id == null) return;
    final keys = await _svc.listProviderKeys(id);
    if (!mounted) return;
    setState(() {
      _keys = keys;
      _models = _aggregateKeyModels(keys);
    });
  }

  List<AIProviderKey> get _displayKeys {
    if (_keys.length <= 1) return List<AIProviderKey>.from(_keys);
    final list = List<AIProviderKey>.from(_keys);
    switch (_keySortMode) {
      case _ProviderKeySortMode.runtime:
        return list;
      case _ProviderKeySortMode.successDesc:
        list.sort((a, b) {
          final int success = b.successCount.compareTo(a.successCount);
          if (success != 0) return success;
          final int last = (b.lastSuccessAt ?? 0).compareTo(
            a.lastSuccessAt ?? 0,
          );
          if (last != 0) return last;
          return _compareDefaultKeyOrder(a, b);
        });
        return list;
      case _ProviderKeySortMode.recentSuccessDesc:
        list.sort((a, b) {
          final int last = (b.lastSuccessAt ?? 0).compareTo(
            a.lastSuccessAt ?? 0,
          );
          if (last != 0) return last;
          final int success = b.successCount.compareTo(a.successCount);
          if (success != 0) return success;
          return _compareDefaultKeyOrder(a, b);
        });
        return list;
      case _ProviderKeySortMode.failureDesc:
        list.sort((a, b) {
          final int failure = b.failureTotalCount.compareTo(
            a.failureTotalCount,
          );
          if (failure != 0) return failure;
          final int last = (b.lastFailedAt ?? 0).compareTo(a.lastFailedAt ?? 0);
          if (last != 0) return last;
          return _compareDefaultKeyOrder(a, b);
        });
        return list;
      case _ProviderKeySortMode.continuousFailureDesc:
        list.sort((a, b) {
          final int failure = b.failureCount.compareTo(a.failureCount);
          if (failure != 0) return failure;
          final int last = (b.lastFailedAt ?? 0).compareTo(a.lastFailedAt ?? 0);
          if (last != 0) return last;
          return _compareDefaultKeyOrder(a, b);
        });
        return list;
      case _ProviderKeySortMode.newestDesc:
        list.sort((a, b) {
          final int newest = (b.id ?? 0).compareTo(a.id ?? 0);
          if (newest != 0) return newest;
          return _compareDefaultKeyOrder(a, b);
        });
        return list;
    }
  }

  int _compareDefaultKeyOrder(AIProviderKey a, AIProviderKey b) {
    final int enabled = (b.enabled ? 1 : 0).compareTo(a.enabled ? 1 : 0);
    if (enabled != 0) return enabled;
    final int priority = a.priority.compareTo(b.priority);
    if (priority != 0) return priority;
    final int order = a.orderIndex.compareTo(b.orderIndex);
    if (order != 0) return order;
    return (a.id ?? 0).compareTo(b.id ?? 0);
  }

  String _keySortModeLabel(_ProviderKeySortMode mode) {
    switch (mode) {
      case _ProviderKeySortMode.runtime:
        return '默认顺序';
      case _ProviderKeySortMode.successDesc:
        return '成功次数';
      case _ProviderKeySortMode.recentSuccessDesc:
        return '最近成功';
      case _ProviderKeySortMode.failureDesc:
        return '失败总数';
      case _ProviderKeySortMode.continuousFailureDesc:
        return '连续失败';
      case _ProviderKeySortMode.newestDesc:
        return '最新添加';
    }
  }

  AIProvider? _currentProviderSnapshot() {
    final int? providerId = _loaded?.id;
    if (providerId == null) return null;
    final String base = _baseUrlCtrl.text.trim();
    return AIProvider(
      id: providerId,
      name: _nameCtrl.text.trim().isEmpty
          ? (_loaded?.name ?? 'Provider')
          : _nameCtrl.text.trim(),
      type: _type,
      baseUrl: base.isEmpty ? null : base,
      chatPath: _chatPathCtrl.text.trim().isEmpty
          ? null
          : _chatPathCtrl.text.trim(),
      modelsPath: _effectiveModelsPath(),
      useResponseApi: _useResponseApi,
      enabled: true,
      isDefault: false,
      models: List<String>.from(_models),
      extra: _buildExtra(),
      orderIndex: _loaded?.orderIndex ?? 0,
    );
  }

  String _clipDialogText(String value, [int max = 240]) {
    final String text = value.trim();
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }

  void _applyTypeDefaults(String t, {bool initial = false}) {
    _type = t;
    String? baseDefault;
    switch (t) {
      case AIProviderTypes.openai:
        baseDefault = 'https://api.openai.com';
        break;
      case AIProviderTypes.claude:
        baseDefault = 'https://api.anthropic.com';
        break;
      case AIProviderTypes.gemini:
        baseDefault = 'https://generativelanguage.googleapis.com';
        _showGeminiRegionNotice();
        break;
      case AIProviderTypes.azureOpenAI:
        baseDefault = '';
        break;
      case AIProviderTypes.custom:
        baseDefault = '';
        break;
    }
    if (initial) {
      _baseUrlCtrl.text = baseDefault ?? '';
    } else {
      final cur = _baseUrlCtrl.text.trim();
      if (cur.isEmpty ||
          cur == 'https://api.openai.com' ||
          cur == 'https://api.anthropic.com' ||
          cur == 'https://generativelanguage.googleapis.com') {
        _baseUrlCtrl.text = baseDefault ?? '';
      }
    }
    final defaultModelsPath = defaultModelsPathForType(t);
    if (defaultModelsPath.isEmpty) {
      _modelsPathCtrl.clear();
    } else {
      _modelsPathCtrl.text = defaultModelsPath;
    }
    if (t == AIProviderTypes.openai || t == AIProviderTypes.custom) {
      _chatPathCtrl.text = _chatPathCtrl.text.isEmpty
          ? '/v1/chat/completions'
          : _chatPathCtrl.text;
    }
    _models = <String>[];
  }

  bool get _supportsModelsPath {
    return _type == AIProviderTypes.openai ||
        _type == AIProviderTypes.custom ||
        _type == AIProviderTypes.claude;
  }

  String _modelsPathHint() {
    final def = defaultModelsPathForType(_type);
    if (def.isNotEmpty) return def;
    return '/v1/models';
  }

  String _effectiveModelsPath() {
    if (!_supportsModelsPath) return '';
    final raw = _modelsPathCtrl.text.trim();
    if (raw.isNotEmpty) return raw;
    final def = defaultModelsPathForType(_type);
    return def.isNotEmpty ? def : '/v1/models';
  }

  String _baseUrlHint() {
    switch (_type) {
      case AIProviderTypes.openai:
        return AppLocalizations.of(context).baseUrlHintOpenAI;
      case AIProviderTypes.claude:
        return AppLocalizations.of(context).baseUrlHintClaude;
      case AIProviderTypes.gemini:
        return AppLocalizations.of(context).baseUrlHintGemini;
      case AIProviderTypes.azureOpenAI:
        return AppLocalizations.of(context).baseUrlHintAzure('{resource}');
      case AIProviderTypes.custom:
        return AppLocalizations.of(context).baseUrlHintCustom;
      default:
        return 'Base URL';
    }
  }

  Future<void> _refreshModels() async {
    if (_fetching) return;
    final providerId = _loaded?.id;
    if (providerId == null) {
      UINotifier.warning(context, '请先保存提供商，再在下方添加 Key 后获取模型。');
      return;
    }
    final enabledKeys = _keys.where((key) => key.enabled).toList();
    if (enabledKeys.isEmpty) {
      UINotifier.error(context, '请先在下方添加并启用至少一个 API Key。');
      return;
    }
    final base = _baseUrlCtrl.text.trim();
    if (_type == AIProviderTypes.azureOpenAI && base.isEmpty) {
      UINotifier.error(
        context,
        AppLocalizations.of(context).baseUrlRequiredForAzureError,
      );
      return;
    }

    setState(() => _fetching = true);
    try {
      final targetKey = enabledKeys.first;
      await _svc.refreshModelsForKey(
        providerId: providerId,
        keyId: targetKey.id!,
      );
      await _reloadKeys();
      if (mounted) {
        UINotifier.success(context, '模型列表已更新');
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).fetchModelsFailedHint,
        );
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Map<String, dynamic> _buildExtra() {
    final map = <String, dynamic>{};
    if (_type == AIProviderTypes.azureOpenAI) {
      map['azure_api_version'] = _azureApiVerCtrl.text.trim().isEmpty
          ? '2024-02-15'
          : _azureApiVerCtrl.text.trim();
    }
    if (_models.isNotEmpty) {
      map['default_model'] = _models.first;
    }
    return map;
  }

  Future<void> _refreshAllKeysAndProbeFailures() async {
    if (_batchRunning || _saving || _fetching) return;
    final AIProvider? provider = _currentProviderSnapshot();
    if (provider == null) {
      UINotifier.warning(context, '请先保存提供商，再执行批量测试。');
      return;
    }
    final enabledKeys = _keys
        .where((key) => key.enabled && key.apiKey.trim().isNotEmpty)
        .toList(growable: false);
    if (enabledKeys.isEmpty) {
      UINotifier.error(context, '请至少保留一个已启用且非空的 API Key。');
      return;
    }
    final String base = _baseUrlCtrl.text.trim();
    if ((_type == AIProviderTypes.azureOpenAI ||
            _type == AIProviderTypes.claude ||
            _type == AIProviderTypes.gemini ||
            _type == AIProviderTypes.custom) &&
        base.isEmpty) {
      UINotifier.error(
        context,
        AppLocalizations.of(context).baseUrlRequiredForAzureError,
      );
      return;
    }

    final bool confirm =
        await showUIDialog<bool>(
          context: context,
          title: '确认批量测试',
          message:
              '即将检查 ${enabledKeys.length} 个已启用 Key。系统会先刷新模型列表，再对失败的 Key 最多连续测试 3 次；若仍失败，将自动删除该 Key。',
          actions: [
            UIDialogAction<bool>(text: '取消', result: false),
            UIDialogAction<bool>(text: '开始测试', result: true),
          ],
        ) ??
        false;
    if (!confirm) return;

    setState(() {
      _batchRunning = true;
      _batchProgress = ProviderKeyBatchProgress(
        phaseLabel: '准备中',
        current: 0,
        total: enabledKeys.length,
        message: '正在准备批量测试任务...',
      );
    });
    try {
      final ProviderKeyBatchRefreshResult result = await _batchSvc
          .refreshModelsAndProbeFailures(
            provider: provider,
            keys: _keys,
            probeAttempts: 3,
            deleteAfterFailedProbe: true,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _batchProgress = progress);
            },
          );
      await _reloadKeys();
      if (!mounted) return;
      UINotifier.success(
        context,
        '批量测试完成：刷新 ${result.refreshedCount} 个 Key，恢复 ${result.rescuedCount} 个，删除 ${result.deletedCount} 个。',
      );
      await _showBatchMaintenanceResult(result);
    } catch (e) {
      try {
        await FlutterLogger.nativeError(
          'AI',
          '批量测试失败 provider=${provider.id} type=${provider.type} error=$e',
        );
      } catch (_) {}
      if (mounted) {
        UINotifier.error(context, '批量测试执行失败，请稍后重试。');
      }
    } finally {
      if (mounted) {
        setState(() {
          _batchRunning = false;
          _batchProgress = null;
        });
      }
    }
  }

  Future<void> _showBatchMaintenanceResult(
    ProviderKeyBatchRefreshResult result,
  ) async {
    if (!mounted) return;
    final String summary = _buildBatchMaintenanceSummary(result);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量测试结果'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(child: SelectableText(summary)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _buildBatchMaintenanceSummary(ProviderKeyBatchRefreshResult result) {
    final lines = <String>[
      '已处理 Key：${result.processedKeyCount}',
      '刷新成功：${result.refreshedCount}',
      '模型刷新失败：${result.modelFailures.length}',
      '连续测试恢复：${result.rescuedCount}',
      '已删除：${result.deletedCount}',
      '跳过测试：${result.skippedProbeCount}',
    ];

    if (result.modelFailures.isNotEmpty) {
      lines.add('');
      lines.add('模型刷新失败明细：');
      for (final item in result.modelFailures) {
        lines.add('- ${item.key.name}: ${_clipDialogText(item.errorMessage)}');
      }
    }

    if (result.probeResults.isNotEmpty) {
      lines.add('');
      lines.add('失败 Key 连续测试结果：');
      for (final item in result.probeResults) {
        final String models = item.modelsTried.isEmpty
            ? '-'
            : item.modelsTried.join(', ');
        final String status = item.success
            ? '恢复成功'
            : (item.deleted ? '已删除' : (item.skipped ? '已跳过' : '仍然失败'));
        final String detail = item.success
            ? '成功模型：${item.successModel ?? '-'}；返回片段：${item.responsePreview ?? '-'}'
            : (item.failureMessages.isEmpty
                  ? '未记录失败原因'
                  : _clipDialogText(item.failureMessages.last));
        lines.add(
          '- ${item.key.name} [$status] 连续测试：${item.attemptsUsed} 次；模型：$models；$detail',
        );
      }
    }

    return lines.join('\n');
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    String base = _baseUrlCtrl.text.trim();
    final chatPath = _chatPathCtrl.text.trim().isEmpty
        ? null
        : _chatPathCtrl.text.trim();
    final modelsPathValue = _supportsModelsPath ? _effectiveModelsPath() : null;

    if (name.isEmpty) {
      UINotifier.error(context, AppLocalizations.of(context).nameRequiredError);
      return;
    }
    final nameOk = await _svc.isNameAvailable(name, excludeId: _loaded?.id);
    if (!mounted) return;
    if (!nameOk) {
      UINotifier.error(
        context,
        AppLocalizations.of(context).nameAlreadyExistsError,
      );
      return;
    }
    if (_type.isEmpty) {
      UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      return;
    }
    if (_type == AIProviderTypes.azureOpenAI ||
        _type == AIProviderTypes.claude ||
        _type == AIProviderTypes.gemini ||
        _type == AIProviderTypes.custom) {
      if (base.isEmpty) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).baseUrlRequiredForAzureError,
        );
        return;
      }
    }
    if (_type == AIProviderTypes.openai && base.isEmpty) {
      base = 'https://api.openai.com';
    }

    setState(() => _saving = true);
    try {
      if (_loaded == null) {
        final id = await _svc.createProvider(
          name: name,
          type: _type,
          baseUrl: base,
          chatPath: chatPath,
          modelsPath: modelsPathValue,
          useResponseApi: _useResponseApi,
          enabled: true,
          isDefault: false,
          extra: _buildExtra(),
          models: _models,
        );
        if (id == null) {
          throw Exception('Insert failed');
        }
      } else {
        final ok = await _svc.updateProvider(
          id: _loaded!.id!,
          name: name,
          type: _type,
          baseUrl: base,
          chatPath: chatPath,
          modelsPath: modelsPathValue,
          useResponseApi: _useResponseApi,
          enabled: true,
          isDefault: false,
          extra: _buildExtra(),
          models: _models,
        );
        if (!ok) {
          throw Exception('Update failed');
        }
      }
      if (!mounted) return;
      UINotifier.success(context, AppLocalizations.of(context).saveSuccess);
      Navigator.of(context).pop(true);
    } catch (e) {
      try {
        await FlutterLogger.nativeError(
          'AI',
          '保存提供商失败 id=${_loaded?.id ?? 'new'} type=$_type error=$e',
        );
      } catch (_) {}
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addModelChip() {
    final m = _modelInputCtrl.text.trim();
    if (m.isEmpty) return;
    setState(() {
      if (!_models.contains(m)) {
        _models = List<String>.from(_models)..add(m);
      }
      _modelInputCtrl.clear();
    });
  }

  List<String> _parseApiKeys(String raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final line in raw.split(RegExp(r'[\r\n]+'))) {
      final key = line.trim();
      if (key.isEmpty) continue;
      if (seen.add(key)) out.add(key);
    }
    return out;
  }

  String _keyNameForBatch({
    required String baseName,
    required int batchIndex,
    required int batchTotal,
    required int existingCount,
  }) {
    final trimmed = baseName.trim();
    if (batchTotal <= 1) {
      return trimmed.isEmpty ? 'Key ${existingCount + 1}' : trimmed;
    }
    final defaultPrefix = RegExp(r'^Key\s+\d+$').hasMatch(trimmed);
    if (trimmed.isEmpty || defaultPrefix) {
      return 'Key ${existingCount + batchIndex + 1}';
    }
    return '$trimmed ${batchIndex + 1}';
  }

  Future<void> _openKeyDialog({AIProviderKey? key}) async {
    final providerId = _loaded?.id;
    if (providerId == null) {
      UINotifier.warning(context, '请先保存提供商，再添加更多 API Key。');
      return;
    }
    final nameCtrl = TextEditingController(
      text: key?.name ?? 'Key ${_keys.length + 1}',
    );
    final apiCtrl = TextEditingController(text: key?.apiKey ?? '');
    final priorityCtrl = TextEditingController(
      text: (key?.priority ?? AIProviderKey.defaultPriority).toString(),
    );
    final modelsCtrl = TextEditingController(
      text: (key?.models ?? const <String>[]).join('\n'),
    );
    // Key 的启停入口已移动到列表项右侧；弹窗仅负责编辑 Key 信息和模型。
    final enabled = key?.enabled ?? true;
    bool dialogFetching = false;

    Future<void> fetchModelsInDialog(
      BuildContext dialogContext,
      void Function(void Function()) setDialogState,
    ) async {
      final apiKeys = _parseApiKeys(apiCtrl.text);
      if (apiKeys.isEmpty) {
        UINotifier.error(context, 'API Key is required');
        return;
      }
      final apiKey = apiKeys.first;
      if (apiKeys.length > 1) {
        UINotifier.warning(
          context,
          'Multiple keys detected; using the first line to fetch models.',
        );
      }
      final base = _baseUrlCtrl.text.trim();
      if (_type == AIProviderTypes.azureOpenAI && base.isEmpty) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).baseUrlRequiredForAzureError,
        );
        return;
      }

      setDialogState(() => dialogFetching = true);
      try {
        final provider = AIProvider(
          id: providerId,
          name: _nameCtrl.text.trim().isEmpty
              ? (_loaded?.name ?? 'Provider')
              : _nameCtrl.text.trim(),
          type: _type,
          baseUrl: base.isEmpty ? null : base,
          chatPath: _chatPathCtrl.text.trim().isEmpty
              ? null
              : _chatPathCtrl.text.trim(),
          modelsPath: _effectiveModelsPath(),
          useResponseApi: _useResponseApi,
          enabled: true,
          isDefault: false,
          models: const <String>[],
          extra: _buildExtra(),
          orderIndex: _loaded?.orderIndex ?? 0,
        );
        final fetched = await _svc.fetchModels(
          provider: provider,
          apiKey: apiKey,
        );
        if (!mounted || !dialogContext.mounted) return;
        modelsCtrl.text = fetched.join('\n');
        UINotifier.success(
          context,
          AppLocalizations.of(context).modelsUpdatedToast(fetched.length),
        );
      } catch (_) {
        if (mounted) {
          UINotifier.error(context, '获取模型失败，可以手动添加。');
        }
      } finally {
        if (dialogContext.mounted) {
          setDialogState(() => dialogFetching = false);
        }
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(key == null ? '添加 API Key' : '编辑 API Key'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildKeyDialogTextField(
                    controller: nameCtrl,
                    label: 'Key 名称',
                  ),
                  _buildKeyDialogTextField(
                    controller: apiCtrl,
                    label: key == null ? 'API Key（可一行一个批量导入）' : 'API Key',
                    hint: key == null ? '一行一个 API Key；获取模型时默认使用第一行' : null,
                    obscure: key != null,
                    minLines: key == null ? 3 : 1,
                    maxLines: key == null ? 8 : 1,
                  ),
                  _buildKeyDialogTextField(
                    controller: priorityCtrl,
                    label: '优先级（默认 100 参与动态分配，其他数字固定排序）',
                    keyboardType: TextInputType.number,
                  ),
                  _buildKeyDialogTextField(
                    controller: modelsCtrl,
                    label: '支持的模型（每行一个）',
                    minLines: 5,
                    maxLines: 10,
                  ),
                  OutlinedButton.icon(
                    onPressed: dialogFetching
                        ? null
                        : () => fetchModelsInDialog(ctx, setDialogState),
                    icon: dialogFetching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('获取模型'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: dialogFetching
                  ? null
                  : () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: dialogFetching
                  ? null
                  : () => Navigator.of(ctx).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    final apiKeys = _parseApiKeys(apiCtrl.text);
    if (apiKeys.isEmpty) {
      UINotifier.error(context, 'API Key 必填');
      return;
    }
    if (key != null && apiKeys.length > 1) {
      UINotifier.error(context, '编辑单个 Key 时请只填写一个 API Key');
      return;
    }
    final models = modelsCtrl.text
        .split(RegExp(r'[\r\n,]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (models.isEmpty) {
      UINotifier.error(context, '至少需要填写一个模型');
      return;
    }
    final priority =
        int.tryParse(priorityCtrl.text.trim()) ?? AIProviderKey.defaultPriority;
    if (key == null) {
      final existingApiKeys = _keys.map((k) => k.apiKey.trim()).toSet();
      final keysToCreate = apiKeys
          .where((item) => !existingApiKeys.contains(item.trim()))
          .toList(growable: false);
      final skipped = apiKeys.length - keysToCreate.length;
      if (keysToCreate.isEmpty) {
        UINotifier.warning(context, '没有新增 Key：输入的 API Key 已存在。');
        return;
      }
      for (var i = 0; i < keysToCreate.length; i++) {
        await _svc.createProviderKey(
          providerId: providerId,
          name: _keyNameForBatch(
            baseName: nameCtrl.text,
            batchIndex: i,
            batchTotal: keysToCreate.length,
            existingCount: _keys.length,
          ),
          apiKey: keysToCreate[i],
          models: models,
          enabled: enabled,
          priority: priority,
          orderIndex: _keys.length + i,
        );
      }
      if (mounted && keysToCreate.length > 1) {
        UINotifier.success(
          context,
          '已导入 ${keysToCreate.length} 个 API Key${skipped > 0 ? '，跳过 $skipped 个重复 Key' : ''}',
        );
      } else if (mounted && skipped > 0) {
        UINotifier.success(context, '已添加 API Key，跳过 $skipped 个重复 Key');
      }
    } else {
      await _svc.updateProviderKey(
        id: key.id!,
        name: nameCtrl.text.trim(),
        apiKey: apiKeys.first,
        models: models,
        enabled: enabled,
        priority: priority,
      );
    }
    await _reloadKeys();
  }

  Future<void> _refreshProviderKey(AIProviderKey key) async {
    final providerId = _loaded?.id;
    if (providerId == null || key.id == null) return;
    setState(() => _fetching = true);
    try {
      await _svc.refreshModelsForKey(providerId: providerId, keyId: key.id!);
      await _reloadKeys();
      if (mounted) UINotifier.success(context, '模型列表已更新');
    } catch (_) {
      if (mounted) UINotifier.error(context, '获取模型失败，可以手动添加。');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _deleteProviderKey(AIProviderKey key) async {
    if (key.id == null) return;
    await _svc.deleteProviderKey(key.id!);
    await _reloadKeys();
  }

  Future<void> _deleteAllProviderKeys() async {
    final providerId = _loaded?.id;
    if (providerId == null || _keys.isEmpty) return;
    final confirm =
        await showUIDialog<bool>(
          context: context,
          title: '删除全部 API Key',
          message: '确定删除当前提供商下的全部 ${_keys.length} 个 API Key 吗？此操作不可恢复。',
          actions: [
            UIDialogAction<bool>(text: '取消', result: false),
            UIDialogAction<bool>(
              text: '全部删除',
              style: UIDialogActionStyle.destructive,
              result: true,
            ),
          ],
        ) ??
        false;
    if (!confirm) return;
    final deleted = await _svc.deleteAllProviderKeys(providerId);
    if (!mounted) return;
    await _reloadKeys();
    if (!mounted) return;
    UINotifier.success(context, '已删除 $deleted 个 API Key');
  }

  String _formatKeyTime(int? millis) {
    if (millis == null || millis <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.month}/${dt.day} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _normalizeOptionalLabel(String label) {
    return label
        .replaceAll(RegExp(r'（\s*可选\s*）'), '')
        .replaceAll(RegExp(r'\(\s*optional\s*\)', caseSensitive: false), '')
        .trim();
  }

  bool _labelLooksOptional(String label) {
    final lower = label.toLowerCase();
    return label.contains('可选') || lower.contains('optional');
  }

  String _priorityText(AIProviderKey key) {
    return key.usesDefaultPriority ? '动态分配' : '${key.priority}';
  }

  Widget _buildKeyStatCell({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinVerticalDivider(ThemeData theme) {
    return Container(
      width: 1,
      height: 32,
      color: theme.colorScheme.outline.withValues(alpha: 0.45),
    );
  }

  Widget _buildProviderKeyCard(AIProviderKey key, int displayIndex) {
    final theme = Theme.of(context);
    final cooling = key.isCoolingDown();
    final statusColor = key.enabled
        ? (cooling ? AppTheme.info : AppTheme.success)
        : theme.colorScheme.onSurfaceVariant;
    final lastError = (key.lastErrorType ?? '').trim();
    final errorMessage = (key.lastErrorMessage ?? '').trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing2),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.55),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.22),
                        width: 0.5,
                      ),
                    ),
                    child: Icon(
                      key.enabled
                          ? Icons.vpn_key_rounded
                          : Icons.key_off_rounded,
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          key.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '优先级 · ${_priorityText(key)} · ${key.models.length} 个模型',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor.withValues(
                        alpha: 0.8,
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(
                          alpha: 0.45,
                        ),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      '#${displayIndex + 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.86,
                    child: Switch.adaptive(
                      value: key.enabled,
                      onChanged: (_fetching || _batchRunning)
                          ? null
                          : (v) => _toggleProviderKey(key, v),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: theme.scaffoldBackgroundColor.withValues(alpha: 0.72),
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing2,
              ),
              child: Row(
                children: [
                  _buildKeyStatCell(
                    icon: Icons.check_rounded,
                    value: '${key.successCount}',
                    label: '成功',
                    color: AppTheme.success,
                  ),
                  _buildThinVerticalDivider(theme),
                  _buildKeyStatCell(
                    icon: Icons.error_outline_rounded,
                    value: '${key.failureTotalCount}',
                    label: '失败',
                    color: theme.colorScheme.error,
                  ),
                  _buildThinVerticalDivider(theme),
                  _buildKeyStatCell(
                    icon: Icons.sync_alt_rounded,
                    value: '${key.failureCount}',
                    label: '连续失败',
                    color: key.failureCount > 0
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '上次成功',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatKeyTime(key.lastSuccessAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '上次失败',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatKeyTime(key.lastFailedAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新模型',
                    icon: const Icon(Icons.refresh, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: (_fetching || _batchRunning)
                        ? null
                        : () => _refreshProviderKey(key),
                  ),
                  IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: (_fetching || _batchRunning)
                        ? null
                        : () => _openKeyDialog(key: key),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: theme.colorScheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                    onPressed: (_fetching || _batchRunning)
                        ? null
                        : () => _deleteProviderKey(key),
                  ),
                ],
              ),
            ),
            if (cooling || !key.enabled || lastError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(
                  lastError.isEmpty
                      ? (cooling ? '当前状态：冷却中' : '当前状态：已停用')
                      : (errorMessage.isEmpty
                            ? '最近错误：$lastError'
                            : '最近错误：$lastError  $errorMessage'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: lastError.isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.error,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleProviderKey(AIProviderKey key, bool enabled) async {
    if (key.id == null) return;
    final ok = await _svc.updateProviderKey(id: key.id!, enabled: enabled);
    if (!mounted) return;
    if (!ok) {
      UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      return;
    }
    await _reloadKeys();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.providerId == null
        ? AppLocalizations.of(context).createProviderTitle
        : AppLocalizations.of(context).editProviderTitle;
    final theme = Theme.of(context);
    final displayKeys = _displayKeys;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: Text(title),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(AppTheme.spacing4),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text(AppLocalizations.of(context).actionSave),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacing4,
                      AppTheme.spacing4,
                      AppTheme.spacing4,
                      0,
                    ),
                    sliver: SliverList.list(
                      children: [
                        _buildProviderConfigCard(theme),
                        const SizedBox(height: AppTheme.spacing5),
                        _buildKeysHeaderCard(theme),
                      ],
                    ),
                  ),
                  if (_loaded != null && displayKeys.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing4,
                      ),
                      sliver: SliverList.builder(
                        itemCount: displayKeys.length,
                        itemBuilder: (context, index) =>
                            _buildProviderKeyCard(displayKeys[index], index),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacing4,
                      AppTheme.spacing4,
                      AppTheme.spacing4,
                      AppTheme.spacing4,
                    ),
                    sliver: SliverList.list(
                      children: [
                        _buildModelsCard(theme),
                        const SizedBox(height: AppTheme.spacing6),
                        _buildBottomActions(),
                        const SizedBox(height: AppTheme.spacing4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildProviderConfigCard(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextInput(
          label: AppLocalizations.of(context).groupNameLabel,
          controller: _nameCtrl,
          hint: AppLocalizations.of(context).groupNameHint,
        ),
        const SizedBox(height: AppTheme.spacing4),
        _buildTypePicker(),
        const SizedBox(height: AppTheme.spacing4),
        _buildTextInput(
          label: AppLocalizations.of(context).baseUrlLabel,
          controller: _baseUrlCtrl,
          hint: _baseUrlHint(),
        ),
        if (_supportsModelsPath) ...[
          const SizedBox(height: AppTheme.spacing4),
          _buildTextInput(
            label: AppLocalizations.of(context).modelsPathOptionalLabel,
            controller: _modelsPathCtrl,
            hint: _modelsPathHint(),
          ),
        ],
        if (_type == AIProviderTypes.openai ||
            _type == AIProviderTypes.custom) ...[
          const SizedBox(height: AppTheme.spacing4),
          _buildTextInput(
            label: AppLocalizations.of(context).chatPathOptionalLabel,
            controller: _chatPathCtrl,
            hint: '/v1/chat/completions',
          ),
          const SizedBox(height: AppTheme.spacing5),
          _buildSwitchRow(
            label: (() {
              final s = AppLocalizations.of(context).useResponseApiLabel;
              return s
                  .replaceAll(
                    RegExp('[\uFF08][^\uFF09]*[\uFF09]|\\([^)]*\\)'),
                    '',
                  )
                  .trim();
            })(),
            value: _useResponseApi,
            onChanged: (v) => setState(() => _useResponseApi = v),
          ),
        ],
        if (_type == AIProviderTypes.azureOpenAI) ...[
          const SizedBox(height: AppTheme.spacing4),
          _buildTextInput(
            label: AppLocalizations.of(context).azureApiVersionLabel,
            controller: _azureApiVerCtrl,
            hint: AppLocalizations.of(context).azureApiVersionHint,
          ),
        ],
      ],
    );
  }

  Widget _buildKeysHeaderCard(ThemeData theme) {
    final badgeText = _keys.length > 99 ? '99+' : '${_keys.length}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.outline.withValues(alpha: 0.65),
        ),
        const SizedBox(height: AppTheme.spacing4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'API Key',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppTheme.spacing2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.65),
                  width: 1,
                ),
              ),
              child: Text(
                badgeText,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            PopupMenuButton<_ProviderKeySortMode>(
              initialValue: _keySortMode,
              onSelected: (mode) => setState(() => _keySortMode = mode),
              itemBuilder: (context) => [
                for (final mode in _ProviderKeySortMode.values)
                  PopupMenuItem<_ProviderKeySortMode>(
                    value: mode,
                    child: Text(_keySortModeLabel(mode)),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sort_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _keySortModeLabel(_keySortMode),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_saving || _fetching || _batchRunning)
                    ? null
                    : () => _openKeyDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增 Key'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  side: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.45),
                    width: 1,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTheme.spacing2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacing2),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    (_keys.isEmpty || _saving || _fetching || _batchRunning)
                    ? null
                    : _refreshAllKeysAndProbeFailures,
                icon: _batchRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('批量测试'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTheme.spacing2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacing2),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    (_keys.isEmpty || _saving || _fetching || _batchRunning)
                    ? null
                    : _deleteAllProviderKeys,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('删除全部'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.75),
                    width: 1,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTheme.spacing2,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing4),
        if (_batchRunning)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacing3),
            child: Builder(
              builder: (context) {
                final progress =
                    _batchProgress ??
                    const ProviderKeyBatchProgress(
                      phaseLabel: '准备中',
                      current: 0,
                      total: 1,
                      message: '正在准备批量测试任务...',
                    );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: progress.progressValue,
                      minHeight: 4,
                    ),
                    const SizedBox(height: AppTheme.spacing1),
                    Text(
                      '${progress.phaseLabel} ${progress.fractionLabel}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(progress.message, style: theme.textTheme.bodySmall),
                  ],
                );
              },
            ),
          ),
        if (_loaded == null)
          Text(
            '请先保存当前提供商，然后再添加或批量测试 API Key。',
            style: theme.textTheme.bodySmall,
          )
        else if (_keys.isEmpty)
          Text('暂无 API Key。', style: theme.textTheme.bodySmall)
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '批量测试会先刷新模型列表，再对失败 Key 最多连续测试 3 次。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildModelsCard(ThemeData theme) {
    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AppLocalizations.of(context).modelsCountLabel(_models.length),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: (_fetching || _batchRunning) ? null : _refreshModels,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing2,
                    vertical: AppTheme.spacing1,
                  ),
                ),
                icon: _fetching
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(AppLocalizations.of(context).actionRefresh),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing3),
          Text(
            AppLocalizations.of(context).manualAddModelLabel,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _modelInputCtrl,
                    textAlignVertical: TextAlignVertical.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: InputDecoration(
                      isDense: false,
                      hintText: AppLocalizations.of(
                        context,
                      ).inputAndAddModelHint,
                      hintStyle: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppTheme.mutedForeground),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.surface
                          : Theme.of(context).scaffoldBackgroundColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing3,
                        vertical: 0,
                      ),
                    ),
                    onSubmitted: (_) => _addModelChip(),
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacing2),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: _addModelChip,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing4,
                    ),
                  ),
                  child: Text(AppLocalizations.of(context).actionAdd),
                ),
              ),
            ],
          ),
          if (_models.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.spacing3),
              child: Text(
                AppLocalizations.of(context).fetchModelsHint,
                style: theme.textTheme.bodySmall,
              ),
            )
          else ...[
            const SizedBox(height: AppTheme.spacing3),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _models.length,
              separatorBuilder: (c, i) => Container(
                height: 1,
                color: Theme.of(c).colorScheme.outline.withValues(alpha: 0.6),
              ),
              itemBuilder: (c, i) {
                final m = _models[i];
                return ListTile(
                  leading: SvgPicture.asset(
                    ModelIconUtils.getIconPath(m),
                    width: 20,
                    height: 20,
                  ),
                  title: Text(m, style: Theme.of(c).textTheme.bodyMedium),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _models = List<String>.from(_models)..removeAt(i);
                      });
                    },
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing3),
            ),
            child: Text(AppLocalizations.of(context).dialogCancel),
          ),
        ),
        const SizedBox(width: AppTheme.spacing3),
        Expanded(
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing3),
            ),
            child: Text(AppLocalizations.of(context).actionSave),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color surface = isDark
        ? theme.colorScheme.surface
        : theme.scaffoldBackgroundColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: child,
    );
  }

  Widget _buildKeyDialogTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
    int minLines = 1,
    int? maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing3),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        minLines: obscure ? 1 : minLines,
        maxLines: obscure ? 1 : maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: AppTheme.spacing3,
          ),
        ),
      ),
    );
  }

  Widget _buildTextInput({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
  }) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color fieldBg = isDark
        ? theme.colorScheme.surface
        : theme.scaffoldBackgroundColor;
    final normalizedLabel = _normalizeOptionalLabel(label);
    final optional = _labelLooksOptional(label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              normalizedLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (optional) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: fieldBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.55),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  '可选',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppTheme.spacing1),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.mutedForeground,
            ),
            filled: true,
            fillColor: fieldBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing3,
              vertical: AppTheme.spacing2,
            ),
          ),
          onChanged: (v) {
            if (controller == _baseUrlCtrl || controller == _modelsPathCtrl) {
              setState(() {
                _models = <String>[];
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildTypePicker() {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color fieldBg = isDark
        ? theme.colorScheme.surface
        : theme.scaffoldBackgroundColor;
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: AIProviderTypes.openai,
        child: Text('OpenAI'),
      ),
      const DropdownMenuItem(
        value: AIProviderTypes.azureOpenAI,
        child: Text('Azure OpenAI'),
      ),
      const DropdownMenuItem(
        value: AIProviderTypes.claude,
        child: Text('Claude'),
      ),
      const DropdownMenuItem(
        value: AIProviderTypes.gemini,
        child: Text('Gemini'),
      ),
      DropdownMenuItem(
        value: AIProviderTypes.custom,
        child: Text(AppLocalizations.of(context).customLabel),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context).interfaceTypeLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_type == AIProviderTypes.gemini)
              Padding(
                padding: const EdgeInsets.only(left: AppTheme.spacing1),
                child: IconButton(
                  icon: const Icon(Icons.help_outline, size: 18),
                  color: Theme.of(context).colorScheme.outline,
                  tooltip: AppLocalizations.of(context).geminiRegionDialogTitle,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  onPressed: _showGeminiRegionDialog,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing1),
        DropdownButtonFormField<String>(
          initialValue: _type,
          isDense: true,
          style: theme.textTheme.bodyMedium,
          items: items,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _applyTypeDefaults(v);
            });
          },
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: fieldBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing3,
              vertical: AppTheme.spacing2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '启用 OpenAI Responses 接口（实验性）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.88,
            child: Switch.adaptive(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
