part of 'provider_edit_page.dart';

extension _ProviderEditStatePart on _ProviderEditPageState {
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
    _providerEditSetState(() {
      _keys = keys;
      _models = _aggregateKeyModels(keys);
    });
    unawaited(_loadModelMetadataFor(_models));
  }

  Future<void> _loadModelMetadataFor(List<String> models) async {
    final int seq = ++_modelInfoLoadSeq;
    final List<String> target = List<String>.from(models);
    if (target.isEmpty) {
      if (!mounted || seq != _modelInfoLoadSeq) return;
      _providerEditSetState(() => _modelInfoByName.clear());
      return;
    }
    final Map<String, ModelsDevModelInfo> info = await _modelsDev.findModels(
      target,
      providerTypeHint: _type,
      providerBaseUrl: _baseUrlCtrl.text,
      providerName: _nameCtrl.text,
    );
    // 手动添加模型时也顺带把可解析到的上下文写入本地 prompt cap override。
    unawaited(
      _modelsDev.cachePromptCapsForModels(
        target,
        providerTypeHint: _type,
        providerBaseUrl: _baseUrlCtrl.text,
        providerName: _nameCtrl.text,
      ),
    );
    if (!mounted || seq != _modelInfoLoadSeq) return;
    _providerEditSetState(() {
      _modelInfoByName
        ..clear()
        ..addAll(info);
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
    _modelInfoByName.clear();
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
        AppLocalizations.of(context).providerSaveBeforeRefreshingModels,
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

    _providerEditSetState(() => _fetching = true);
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
      if (mounted) _providerEditSetState(() => _fetching = false);
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
}
