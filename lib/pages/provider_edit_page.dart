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
  balanceDesc,
  balanceAsc,
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

  /// 余额查询接口类型，'none' / 'new_api' / 'sub2api'。
  String _balanceEndpointType = AIBalanceEndpointTypes.none;

  /// 余额为 0 时自动删除该 key。
  bool _balanceAutoDeleteZeroKey = false;

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
        _balanceEndpointType = p.balanceEndpointType;
        _balanceAutoDeleteZeroKey = p.balanceAutoDeleteZeroKey;
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
      case _ProviderKeySortMode.balanceDesc:
        list.sort((a, b) {
          final int balance = _compareKeyBalance(a, b, descending: true);
          if (balance != 0) return balance;
          return _compareDefaultKeyOrder(a, b);
        });
        return list;
      case _ProviderKeySortMode.balanceAsc:
        list.sort((a, b) {
          final int balance = _compareKeyBalance(a, b, descending: false);
          if (balance != 0) return balance;
          return _compareDefaultKeyOrder(a, b);
        });
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

  int _compareKeyBalance(
    AIProviderKey a,
    AIProviderKey b, {
    required bool descending,
  }) {
    final bool aKnown = a.balanceTotal != null;
    final bool bKnown = b.balanceTotal != null;
    if (aKnown != bKnown) return aKnown ? -1 : 1;
    if (!aKnown && !bKnown) {
      final int display = (a.balanceDisplay ?? '').compareTo(
        b.balanceDisplay ?? '',
      );
      return descending ? -display : display;
    }
    final int value = a.balanceTotal!.compareTo(b.balanceTotal!);
    return descending ? -value : value;
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

  String _formatBalanceTotal(double value) {
    final rounded = value.toStringAsFixed(value.abs() >= 100 ? 2 : 4);
    return rounded
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String? _keysBalanceSummary() {
    if (_loaded == null ||
        !AIBalanceEndpointTypes.isQueryable(_balanceEndpointType) ||
        _keys.isEmpty) {
      return null;
    }
    final known = _keys.where((key) => key.hasBalance).toList();
    if (known.isEmpty) return '总余额 —';
    final numeric = known.where((key) => key.balanceTotal != null).toList();
    if (numeric.isEmpty) {
      if (known.length == 1) {
        return '余额 ${known.first.balanceDisplay ?? '已获取'}';
      }
      return '余额已获取 ${known.length}/${_keys.length}';
    }
    final double total = numeric.fold<double>(
      0,
      (sum, key) => sum + (key.balanceTotal ?? 0),
    );
    final currencies = numeric
        .map((key) => (key.balanceCurrency ?? '').trim())
        .where((currency) => currency.isNotEmpty)
        .toSet();
    final currency = currencies.length == 1 ? ' ${currencies.first}' : '';
    final partial = numeric.length < _keys.length
        ? '（${numeric.length}/${_keys.length}）'
        : '';
    return '总余额 ${_formatBalanceTotal(total)}$currency$partial';
  }

  String _keySortModeLabel(_ProviderKeySortMode mode) {
    switch (mode) {
      case _ProviderKeySortMode.runtime:
        return '默认顺序';
      case _ProviderKeySortMode.balanceDesc:
        return '余额从高到低';
      case _ProviderKeySortMode.balanceAsc:
        return '余额从低到高';
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
      balanceEndpointType: _balanceEndpointType,
      balanceAutoDeleteZeroKey: _balanceAutoDeleteZeroKey,
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
      UINotifier.warning(
        context,
        'Please save the provider before refreshing models.',
      );
      return;
    }
    final AIProvider? provider = _currentProviderSnapshot();
    if (provider == null) return;
    final enabledKeys = _keys
        .where(
          (key) =>
              key.enabled && key.id != null && key.apiKey.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (enabledKeys.isEmpty) {
      UINotifier.error(
        context,
        AppLocalizations.of(context).providerAddAtLeastOneEnabledApiKey,
      );
      return;
    }
    final base = _baseUrlCtrl.text.trim();
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

    setState(() => _fetching = true);
    final List<String> fetchedModelPool = <String>[];
    int successCount = 0;
    int balanceSuccessCount = 0;
    final List<String> failureHints = <String>[];
    try {
      for (final key in enabledKeys) {
        try {
          final models = await _svc.refreshModelsForKey(
            providerId: providerId,
            keyId: key.id!,
            providerOverride: provider,
            awaitBalance: true,
          );
          fetchedModelPool.addAll(models);
          successCount++;
          final latestKey = await _svc.getProviderKey(key.id!);
          if (latestKey?.hasBalance ?? false) balanceSuccessCount++;
        } catch (e) {
          failureHints.add(
            '${key.name}: ${_clipDialogText(e.toString(), 120)}',
          );
        }
      }
      await _reloadKeys();
      if (!mounted) return;
      if (successCount > 0) {
        final fetchedCount = _mergeModelNames(<Iterable<String>>[
          fetchedModelPool,
        ]).length;
        final balanceHint = provider.hasBalanceQuery
            ? ', balance $balanceSuccessCount/$successCount'
            : '';
        final failedHint = failureHints.isNotEmpty
            ? ', failed ${failureHints.length} keys'
            : '';
        UINotifier.success(
          context,
          'Model refresh complete: $successCount/${enabledKeys.length} keys, $fetchedCount models$balanceHint$failedHint',
        );
      } else {
        UINotifier.error(
          context,
          '${AppLocalizations.of(context).fetchModelsFailedHint} Failed keys: ${enabledKeys.length}',
        );
      }
      if (failureHints.isNotEmpty) {
        try {
          await FlutterLogger.nativeWarn(
            'AI',
            'refreshModels all-key failures provider=$providerId ${failureHints.join(' | ')}',
          );
        } catch (_) {}
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
      UINotifier.warning(
        context,
        AppLocalizations.of(context).providerSaveBeforeBatchTest,
      );
      return;
    }
    final enabledKeys = _keys
        .where((key) => key.enabled && key.apiKey.trim().isNotEmpty)
        .toList(growable: false);
    if (enabledKeys.isEmpty) {
      UINotifier.error(
        context,
        AppLocalizations.of(context).providerKeepOneEnabledApiKey,
      );
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
        UINotifier.error(
          context,
          AppLocalizations.of(context).providerBatchTestFailed,
        );
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
        title: Text(AppLocalizations.of(context).providerBatchTestResultTitle),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(child: SelectableText(summary)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context).actionClose),
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
          balanceEndpointType: _balanceEndpointType,
          balanceAutoDeleteZeroKey: _balanceAutoDeleteZeroKey,
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
          balanceEndpointType: _balanceEndpointType,
          setBalanceEndpointType: true,
          balanceAutoDeleteZeroKey: _balanceAutoDeleteZeroKey,
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

  List<String> _mergeModelNames(Iterable<Iterable<String>> groups) {
    final seen = <String>{};
    final out = <String>[];
    for (final group in groups) {
      for (final raw in group) {
        final model = raw.trim();
        if (model.isEmpty) continue;
        if (seen.add(model.toLowerCase())) out.add(model);
      }
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
      UINotifier.warning(
        context,
        'Please save the provider before adding API keys.',
      );
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
    final enabled = key?.enabled ?? true;
    final fetchedBalancesByApiKey = <String, ProviderKeyBalance>{};
    bool dialogFetching = false;
    bool dialogSaving = false;
    ProviderKeyBatchProgress? dialogProgress;

    AIProvider buildDialogProviderSnapshot() {
      final base = _baseUrlCtrl.text.trim();
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
        models: const <String>[],
        extra: _buildExtra(),
        orderIndex: _loaded?.orderIndex ?? 0,
        balanceEndpointType: _balanceEndpointType,
        balanceAutoDeleteZeroKey: _balanceAutoDeleteZeroKey,
      );
    }

    List<String> parseDialogModels() {
      return modelsCtrl.text
          .split(RegExp(r'[\r\n,]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    String keyLabelForProgress({
      required int index,
      required int total,
      required String fallbackName,
    }) {
      if (total <= 1) {
        return fallbackName.trim().isEmpty
            ? 'Current key'
            : fallbackName.trim();
      }
      return _keyNameForBatch(
        baseName: fallbackName,
        batchIndex: index,
        batchTotal: total,
        existingCount: _keys.length,
      );
    }

    bool validateBaseUrlForDialog() {
      final base = _baseUrlCtrl.text.trim();
      if ((_type == AIProviderTypes.azureOpenAI ||
              _type == AIProviderTypes.claude ||
              _type == AIProviderTypes.gemini ||
              _type == AIProviderTypes.custom) &&
          base.isEmpty) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).baseUrlRequiredForAzureError,
        );
        return false;
      }
      return true;
    }

    Future<void> fetchModelsInDialog(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      if (dialogFetching || dialogSaving) return;
      final apiKeys = _parseApiKeys(apiCtrl.text);
      if (apiKeys.isEmpty) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).apiKeyRequiredError,
        );
        return;
      }
      if (!validateBaseUrlForDialog()) return;

      final provider = buildDialogProviderSnapshot();
      final initialModels = parseDialogModels();
      final fetchedModelPool = <String>[];
      final failureHints = <String>[];
      int modelSuccessCount = 0;
      int balanceSuccessCount = 0;

      setDialogState(() {
        dialogFetching = true;
        dialogProgress = ProviderKeyBatchProgress(
          phaseLabel: 'Fetch models',
          current: 0,
          total: apiKeys.length,
          message: 'Preparing to scan ${apiKeys.length} API keys...',
        );
      });

      try {
        for (var i = 0; i < apiKeys.length; i++) {
          final apiKey = apiKeys[i];
          final label = keyLabelForProgress(
            index: i,
            total: apiKeys.length,
            fallbackName: nameCtrl.text,
          );
          if (dialogContext.mounted) {
            setDialogState(() {
              dialogProgress = ProviderKeyBatchProgress(
                phaseLabel: 'Fetch models',
                current: i + 1,
                total: apiKeys.length,
                message: 'Fetching models for $label...',
              );
            });
          }

          List<String> fetched = const <String>[];
          bool modelOk = false;
          try {
            fetched = await _svc.fetchModels(
              provider: provider,
              apiKey: apiKey,
            );
            fetchedModelPool.addAll(fetched);
            modelSuccessCount++;
            modelOk = true;
            final merged = _mergeModelNames(<Iterable<String>>[
              initialModels,
              fetchedModelPool,
            ]);
            if (dialogContext.mounted) {
              setDialogState(() => modelsCtrl.text = merged.join('\n'));
            }
          } catch (e) {
            final errorText = _clipDialogText(e.toString(), 120);
            failureHints.add('$label model fetch failed: $errorText');
            try {
              await FlutterLogger.nativeWarn(
                'AI',
                'add-key dialog model fetch failed provider=$providerId keyIndex=${i + 1}/${apiKeys.length} error=$errorText',
              );
            } catch (_) {}
          }

          String balanceMessage = '';
          if (provider.hasBalanceQuery) {
            if (dialogContext.mounted) {
              setDialogState(() {
                dialogProgress = ProviderKeyBatchProgress(
                  phaseLabel: 'Fetch balance',
                  current: i + 1,
                  total: apiKeys.length,
                  message: 'Fetching balance for $label...',
                );
              });
            }
            try {
              final balance = await _svc.fetchBalance(
                provider: provider,
                apiKey: apiKey,
              );
              fetchedBalancesByApiKey[apiKey] = balance;
              balanceSuccessCount++;
              balanceMessage = ', balance: ${balance.display}';
            } catch (e) {
              final errorText = _clipDialogText(e.toString(), 120);
              balanceMessage = ', balance failed';
              failureHints.add('$label balance fetch failed: $errorText');
            }
          }

          if (dialogContext.mounted) {
            final modelMessage = modelOk
                ? '${fetched.length} models'
                : 'model fetch failed, skipped';
            setDialogState(() {
              dialogProgress = ProviderKeyBatchProgress(
                phaseLabel: 'Scan keys',
                current: i + 1,
                total: apiKeys.length,
                message: '$label: $modelMessage$balanceMessage',
              );
            });
          }
        }

        if (!mounted || !dialogContext.mounted) return;
        if (modelSuccessCount > 0) {
          final fetchedCount = _mergeModelNames(<Iterable<String>>[
            fetchedModelPool,
          ]).length;
          final balanceHint = provider.hasBalanceQuery
              ? ', balance $balanceSuccessCount/${apiKeys.length}'
              : '';
          final failedHint = failureHints.isNotEmpty
              ? ', ${failureHints.length} failed items'
              : '';
          UINotifier.success(
            context,
            'Model fetch complete: $modelSuccessCount/${apiKeys.length} keys succeeded, $fetchedCount models merged$balanceHint$failedHint',
          );
        } else {
          UINotifier.error(
            context,
            'No key returned models. The current manual model list is unchanged.',
          );
        }
      } finally {
        if (dialogContext.mounted) {
          setDialogState(() {
            dialogFetching = false;
            dialogProgress = ProviderKeyBatchProgress(
              phaseLabel: 'Fetch complete',
              current: apiKeys.length,
              total: apiKeys.length,
              message:
                  'Models $modelSuccessCount/${apiKeys.length}, balances $balanceSuccessCount/${provider.hasBalanceQuery ? apiKeys.length : 0}',
            );
          });
        }
      }
    }

    Future<void> saveKeyInDialog(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      if (dialogFetching || dialogSaving) return;
      final apiKeys = _parseApiKeys(apiCtrl.text);
      if (apiKeys.isEmpty) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).apiKeyRequiredError,
        );
        return;
      }
      if (key != null && apiKeys.length > 1) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).providerOnlyOneApiKeyCanEdit,
        );
        return;
      }
      final models = parseDialogModels();
      if (models.isEmpty) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).atLeastOneModelRequiredError,
        );
        return;
      }
      final providerSnapshot = _currentProviderSnapshot();
      if (providerSnapshot == null) {
        UINotifier.warning(
          context,
          'Please save the provider before adding API keys.',
        );
        return;
      }
      final priority =
          int.tryParse(priorityCtrl.text.trim()) ??
          AIProviderKey.defaultPriority;

      final existingApiKeys = _keys.map((k) => k.apiKey.trim()).toSet();
      final keysToCreate = key == null
          ? apiKeys
                .where((item) => !existingApiKeys.contains(item.trim()))
                .toList(growable: false)
          : const <String>[];
      final skipped = key == null ? apiKeys.length - keysToCreate.length : 0;
      if (key == null && keysToCreate.isEmpty) {
        UINotifier.warning(
          context,
          'No new key: all entered API keys already exist.',
        );
        return;
      }

      final total = key == null ? keysToCreate.length : 1;
      int savedCount = 0;
      int balanceUpdatedCount = 0;
      bool shouldCloseDialog = false;

      setDialogState(() {
        dialogSaving = true;
        dialogProgress = ProviderKeyBatchProgress(
          phaseLabel: 'Save keys',
          current: 0,
          total: total,
          message: 'Preparing to save...',
        );
      });

      try {
        if (key == null) {
          for (var i = 0; i < keysToCreate.length; i++) {
            final apiKey = keysToCreate[i];
            final keyName = _keyNameForBatch(
              baseName: nameCtrl.text,
              batchIndex: i,
              batchTotal: keysToCreate.length,
              existingCount: _keys.length,
            );
            if (dialogContext.mounted) {
              setDialogState(() {
                dialogProgress = ProviderKeyBatchProgress(
                  phaseLabel: 'Save keys',
                  current: i + 1,
                  total: total,
                  message: 'Saving $keyName...',
                );
              });
            }
            final newId = await _svc.createProviderKey(
              providerId: providerId,
              name: keyName,
              apiKey: apiKey,
              models: models,
              enabled: enabled,
              priority: priority,
              orderIndex: _keys.length + i,
            );
            if (newId == null) continue;
            savedCount++;

            if (providerSnapshot.hasBalanceQuery) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  dialogProgress = ProviderKeyBatchProgress(
                    phaseLabel: 'Save balance',
                    current: i + 1,
                    total: total,
                    message: 'Saving balance for $keyName...',
                  );
                });
              }
              final cachedBalance = fetchedBalancesByApiKey[apiKey];
              final balance = cachedBalance == null
                  ? await _svc.refreshBalanceForKey(
                      providerId: providerId,
                      keyId: newId,
                      providerOverride: providerSnapshot,
                    )
                  : await _svc.saveFetchedBalanceForKey(
                      providerId: providerId,
                      keyId: newId,
                      balance: cachedBalance,
                      providerOverride: providerSnapshot,
                    );
              if (balance != null) balanceUpdatedCount++;
            }
          }
        } else {
          if (dialogContext.mounted) {
            setDialogState(() {
              dialogProgress = ProviderKeyBatchProgress(
                phaseLabel: 'Save key',
                current: 1,
                total: 1,
                message:
                    'Saving ${nameCtrl.text.trim().isEmpty ? key.name : nameCtrl.text.trim()}...',
              );
            });
          }
          await _svc.updateProviderKey(
            id: key.id!,
            name: nameCtrl.text.trim(),
            apiKey: apiKeys.first,
            models: models,
            enabled: enabled,
            priority: priority,
          );
          savedCount = 1;
          if (providerSnapshot.hasBalanceQuery) {
            final cachedBalance = fetchedBalancesByApiKey[apiKeys.first];
            final balance = cachedBalance == null
                ? await _svc.refreshBalanceForKey(
                    providerId: providerId,
                    keyId: key.id!,
                    providerOverride: providerSnapshot,
                  )
                : await _svc.saveFetchedBalanceForKey(
                    providerId: providerId,
                    keyId: key.id!,
                    balance: cachedBalance,
                    providerOverride: providerSnapshot,
                  );
            if (balance != null) balanceUpdatedCount++;
          }
        }

        await _reloadKeys();
        if (!mounted || !dialogContext.mounted) return;
        final balanceHint = providerSnapshot.hasBalanceQuery
            ? ', balance $balanceUpdatedCount/$savedCount'
            : '';
        final skippedHint = skipped > 0
            ? ', skipped $skipped duplicate keys'
            : '';
        UINotifier.success(
          context,
          key == null
              ? 'Imported $savedCount API keys$balanceHint$skippedHint'
              : 'API Key saved$balanceHint',
        );
        shouldCloseDialog = true;
        Navigator.of(dialogContext).pop(true);
      } catch (e) {
        try {
          await FlutterLogger.nativeError(
            'AI',
            'save API key failed provider=$providerId key=${key?.id ?? 'new'} error=$e',
          );
        } catch (_) {}
        if (mounted) {
          UINotifier.error(
            context,
            'Failed to save API Key: ${_clipDialogText(e.toString())}',
          );
        }
        if (dialogContext.mounted) {
          setDialogState(() {
            dialogProgress = ProviderKeyBatchProgress(
              phaseLabel: 'Save failed',
              current: savedCount,
              total: total,
              message: _clipDialogText(e.toString(), 160),
            );
          });
        }
      } finally {
        if (!shouldCloseDialog && dialogContext.mounted) {
          setDialogState(() => dialogSaving = false);
        }
      }
    }

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          final busy = dialogFetching || dialogSaving;
          return AlertDialog(
            title: Text(
              key == null
                  ? AppLocalizations.of(context).providerAddApiKey
                  : AppLocalizations.of(context).providerEditApiKey,
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildKeyDialogTextField(
                      controller: nameCtrl,
                      label: 'Key name',
                    ),
                    _buildKeyDialogTextField(
                      controller: apiCtrl,
                      label: key == null ? 'API Key (one per line)' : 'API Key',
                      hint: key == null
                          ? 'One API Key per line. Fetch scans every key.'
                          : null,
                      obscure: key != null,
                      minLines: key == null ? 3 : 1,
                      maxLines: key == null ? 8 : 1,
                    ),
                    _buildKeyDialogTextField(
                      controller: priorityCtrl,
                      label: 'Priority (100 = dynamic allocation)',
                      keyboardType: TextInputType.number,
                    ),
                    _buildKeyDialogTextField(
                      controller: modelsCtrl,
                      label: 'Supported models (one per line)',
                      minLines: 5,
                      maxLines: 10,
                    ),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => fetchModelsInDialog(ctx, setDialogState),
                      icon: dialogFetching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_download_outlined, size: 18),
                      label: Text(
                        AppLocalizations.of(
                          context,
                        ).providerFetchModelsAndBalance,
                      ),
                    ),
                    if (dialogProgress != null) ...[
                      const SizedBox(height: AppTheme.spacing3),
                      _buildProviderKeyDialogProgress(theme, dialogProgress!),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
                child: Text(AppLocalizations.of(context).dialogCancel),
              ),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () => saveKeyInDialog(ctx, setDialogState),
                child: dialogSaving
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.of(context).actionSaving),
                        ],
                      )
                    : Text(AppLocalizations.of(context).actionSave),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _refreshProviderKey(AIProviderKey key) async {
    final providerId = _loaded?.id;
    if (providerId == null || key.id == null) return;
    final provider = _currentProviderSnapshot();
    if (provider == null) return;
    setState(() => _fetching = true);
    try {
      await _svc.refreshModelsForKey(
        providerId: providerId,
        keyId: key.id!,
        providerOverride: provider,
        awaitBalance: true,
      );
      await _reloadKeys();
      if (mounted) {
        UINotifier.success(
          context,
          provider.hasBalanceQuery ? '模型列表与余额已更新' : '模型列表已更新',
        );
      }
    } catch (_) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).providerFetchModelsFailedManual,
        );
      }
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
    UINotifier.success(
      context,
      AppLocalizations.of(context).providerDeletedApiKeys(deleted),
    );
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
                  if (AIBalanceEndpointTypes.isQueryable(
                    _balanceEndpointType,
                  )) ...[
                    _buildThinVerticalDivider(theme),
                    _buildKeyStatCell(
                      icon: Icons.account_balance_wallet_outlined,
                      value: key.balanceDisplay ?? '—',
                      label: '余额',
                      color: key.hasBalance
                          ? (key.isBalanceZero
                                ? theme.colorScheme.error
                                : AppTheme.info)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
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
        const SizedBox(height: AppTheme.spacing4),
        _buildBalanceEndpointPicker(),
        if (_balanceEndpointType != AIBalanceEndpointTypes.none) ...[
          const SizedBox(height: AppTheme.spacing4),
          _buildSwitchRow(
            label: '余额为 0 时自动删除该 Key',
            description: '检测到主余额为 0 时，自动从该提供商下移除对应 Key',
            value: _balanceAutoDeleteZeroKey,
            onChanged: (v) => setState(() => _balanceAutoDeleteZeroKey = v),
          ),
        ],
      ],
    );
  }

  Widget _buildKeysHeaderCard(ThemeData theme) {
    final badgeText = _keys.length > 99 ? '99+' : '${_keys.length}';
    final balanceSummary = _keysBalanceSummary();
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
        if (balanceSummary != null) ...[
          const SizedBox(height: AppTheme.spacing3),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing3,
              vertical: AppTheme.spacing2,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.22,
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.35),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 17,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  balanceSummary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppTheme.spacing4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_saving || _fetching || _batchRunning)
                    ? null
                    : () => _openKeyDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: Text(AppLocalizations.of(context).providerAddKeyButton),
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
                label: Text(
                  AppLocalizations.of(context).providerBatchTestButton,
                ),
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
                label: Text(AppLocalizations.of(context).providerDeleteAllKeys),
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
          Text(
            AppLocalizations.of(context).providerNoApiKeys,
            style: theme.textTheme.bodySmall,
          )
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

  Widget _buildProviderKeyDialogProgress(
    ThemeData theme,
    ProviderKeyBatchProgress progress,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.28,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progress.progressValue, minHeight: 4),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            '${progress.phaseLabel} ${progress.fractionLabel}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            progress.message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
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

  Widget _buildBalanceEndpointPicker() {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color fieldBg = isDark
        ? theme.colorScheme.surface
        : theme.scaffoldBackgroundColor;
    final l10n = AppLocalizations.of(context);
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: AIBalanceEndpointTypes.none,
        child: Text(l10n.balanceEndpointNone),
      ),
      DropdownMenuItem(
        value: AIBalanceEndpointTypes.newApi,
        child: Text(l10n.balanceEndpointNewApi),
      ),
      DropdownMenuItem(
        value: AIBalanceEndpointTypes.sub2api,
        child: Text(l10n.balanceEndpointSub2api),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '余额查询接口',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
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
        ),
        const SizedBox(height: AppTheme.spacing1),
        DropdownButtonFormField<String>(
          initialValue: _balanceEndpointType,
          isDense: true,
          style: theme.textTheme.bodyMedium,
          items: items,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _balanceEndpointType = AIBalanceEndpointTypes.normalize(v);
              if (_balanceEndpointType == AIBalanceEndpointTypes.none) {
                _balanceAutoDeleteZeroKey = false;
              }
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
    String? description,
  }) {
    final theme = Theme.of(context);
    final desc = description ?? '启用 OpenAI Responses 接口（实验性）';
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
                  desc,
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
