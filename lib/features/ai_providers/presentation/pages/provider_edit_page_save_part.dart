part of 'provider_edit_page.dart';

extension _ProviderEditSavePart on _ProviderEditPageState {
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

    _providerEditSetState(() => _saving = true);
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
      if (mounted) _providerEditSetState(() => _saving = false);
    }
  }

  void _addModelChip() {
    final m = _modelInputCtrl.text.trim();
    if (m.isEmpty) return;
    bool added = false;
    _providerEditSetState(() {
      if (!_models.contains(m)) {
        _models = List<String>.from(_models)..add(m);
        added = true;
      }
      _modelInputCtrl.clear();
    });
    if (added) unawaited(_loadModelMetadataFor(_models));
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

  ModelsDevModelInfo? _metadataForModel(String model) {
    return _modelInfoByName[model.trim().toLowerCase()];
  }

  String _formatTokens(int? tokens, AppLocalizations l10n) {
    if (tokens == null || tokens <= 0) return l10n.modelMetaUnknownValue;
    if (tokens >= 1000000) {
      final double m = tokens / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
    }
    if (tokens >= 1000) {
      final double k = tokens / 1000;
      return '${k.toStringAsFixed(k >= 100 ? 0 : 1)}K';
    }
    return '$tokens';
  }

  String _modelLimitLine(String model, AppLocalizations l10n) {
    final ModelsDevModelInfo? meta = _metadataForModel(model);
    final int? localContext = ModelsDevModelLimits.contextTokens(model);
    final bool usingFallbackContext = meta == null && localContext == null;
    final int context =
        meta?.contextTokens ??
        localContext ??
        AIContextBudgets.forModel(model).promptCapTokens;
    final int? input =
        meta?.inputTokens ?? ModelsDevModelLimits.inputTokens(model);
    final int? output =
        meta?.outputTokens ?? ModelsDevModelLimits.outputTokens(model);
    final parts = <String>[
      '${l10n.modelMetaContextLabel} ${_formatTokens(context, l10n)}',
    ];
    if (input != null && input > 0) {
      parts.add('${l10n.modelMetaInputLabel} ${_formatTokens(input, l10n)}');
    }
    if (output != null && output > 0) {
      parts.add('${l10n.modelMetaOutputLabel} ${_formatTokens(output, l10n)}');
    }
    if (usingFallbackContext) {
      parts.add(l10n.modelMetaFallback32k);
    }
    return parts.join(' · ');
  }

  String _formatUsdPerMillion(double value) {
    final String text = value
        .toStringAsFixed(value.abs() >= 100 ? 2 : 4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '\$$text/M';
  }

  List<_ModelCostDisplayItem> _modelCostItems(
    ModelsDevModelInfo? meta,
    AppLocalizations l10n,
  ) {
    if (meta == null || meta.cost.isEmpty) return const [];

    final labels = <String, String>{
      'input': l10n.modelMetaCostInputLabel,
      'output': l10n.modelMetaCostOutputLabel,
      'reasoning': l10n.modelMetaCostReasoningLabel,
      'cache_read': l10n.modelMetaCostCacheReadLabel,
      'cache_write': l10n.modelMetaCostCacheWriteLabel,
      'cache_create': l10n.modelMetaCostCacheWriteLabel,
      'cache_creation': l10n.modelMetaCostCacheWriteLabel,
      'cache_creation_input': l10n.modelMetaCostCacheWriteLabel,
      'input_cache_write': l10n.modelMetaCostCacheWriteLabel,
      'input_audio': l10n.modelMetaCostAudioInputLabel,
      'output_audio': l10n.modelMetaCostAudioOutputLabel,
    };

    final items = <_ModelCostDisplayItem>[];
    final seen = <String>{};
    for (final entry in labels.entries) {
      final value = meta.cost[entry.key];
      if (value == null) continue;
      seen.add(entry.key);
      items.add(
        _ModelCostDisplayItem(
          label: entry.value,
          value: _formatUsdPerMillion(value),
        ),
      );
    }
    for (final entry in meta.cost.entries) {
      if (seen.contains(entry.key)) continue;
      items.add(
        _ModelCostDisplayItem(
          label: entry.key.replaceAll('_', ' '),
          value: _formatUsdPerMillion(entry.value),
        ),
      );
    }
    return items;
  }

  Widget? _buildModelLifecycleRow(
    ModelsDevModelInfo? meta,
    AppLocalizations l10n,
  ) {
    if (meta == null) return null;
    final knowledge = (meta.knowledge ?? '').trim();
    final releaseDate = (meta.releaseDate ?? '').trim();
    if (knowledge.isEmpty && releaseDate.isEmpty) return null;

    final releaseItem = releaseDate.isEmpty
        ? null
        : _buildLifecycleItem(
            icon: Icons.event_available_outlined,
            label: l10n.modelMetaReleaseLabel,
            value: releaseDate,
          );
    final knowledgeItem = knowledge.isEmpty
        ? null
        : _buildLifecycleItem(
            icon: Icons.calendar_today_outlined,
            label: l10n.modelMetaKnowledgeLabel,
            value: knowledge,
            alignEnd: true,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          if (releaseItem != null)
            Expanded(child: releaseItem)
          else
            const Spacer(),
          if (knowledgeItem != null && releaseItem != null)
            const SizedBox(width: AppTheme.spacing4),
          if (knowledgeItem != null)
            Expanded(child: knowledgeItem)
          else
            const Spacer(),
        ],
      ),
    );
  }
}
