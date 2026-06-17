part of 'segment_status_page.dart';

// ========== 动态页提供商选择 ==========
extension _SegmentStatusProviderPart on _SegmentStatusPageState {
  Future<void> _loadDynamicEntryLogIconEnabled() async {
    try {
      final bool enabled = await UserSettingsService.instance.getBool(
        UserSettingKeys.dynamicEntryLogIconEnabled,
        defaultValue: false,
      );
      if (!mounted) return;
      _segmentStatusSetState(() => _dynamicEntryLogIconEnabled = enabled);
    } catch (_) {}
  }

  // 载入“动态(segments)”的提供商/模型选择（独立于对话页）
  Future<void> _loadSegmentsContextSelection() async {
    final Stopwatch sw = Stopwatch()..start();
    _beginEntryPerfLoad('segment.context');
    try {
      final svc = AIProvidersService.instance;
      final Stopwatch providersSw = Stopwatch()..start();
      final providers = await svc.listProviders();
      DynamicEntryPerfService.instance.mark(
        'segment.context.providers.done',
        detail:
            'ms=${providersSw.elapsedMilliseconds} count=${providers.length}',
      );
      if (providers.isEmpty) {
        if (mounted) {
          _segmentStatusSetState(() {
            _ctxSegProvider = null;
            _ctxSegModel = null;
          });
        }
        _endEntryPerfLoad(
          'segment.context',
          detail: 'ms=${sw.elapsedMilliseconds} providers=0',
        );
        return;
      }
      final Stopwatch contextRowSw = Stopwatch()..start();
      final ctxRow = await AISettingsService.instance.getAIContextRow(
        'segments',
      );
      DynamicEntryPerfService.instance.mark(
        'segment.context.selection.done',
        detail:
            'ms=${contextRowSw.elapsedMilliseconds} hasRow=${ctxRow != null} providerId=${ctxRow?['provider_id'] ?? ''}',
      );
      AIProvider? sel;
      AIProvider? defaultProvider;
      final int? selectedProviderId = ctxRow?['provider_id'] as int?;
      final Stopwatch resolveSw = Stopwatch()..start();
      for (final AIProvider provider in providers) {
        if (selectedProviderId != null && provider.id == selectedProviderId) {
          sel = provider;
        }
        if (defaultProvider == null && provider.isDefault) {
          defaultProvider = provider;
        }
      }
      sel ??= defaultProvider;
      sel ??= providers.first;

      String model =
          (ctxRow != null &&
              (ctxRow['model'] as String?)?.trim().isNotEmpty == true)
          ? (ctxRow['model'] as String).trim()
          : ((sel.extra['active_model'] as String?) ?? sel.defaultModel)
                .toString();
      if (model.isEmpty && sel.models.isNotEmpty) model = sel.models.first;
      DynamicEntryPerfService.instance.mark(
        'segment.context.resolve.done',
        detail:
            'ms=${resolveSw.elapsedMilliseconds} provider=${sel.name} model=$model',
      );

      if (mounted) {
        _segmentStatusSetState(() {
          _ctxSegProvider = sel;
          _ctxSegModel = model;
        });
      }
      _endEntryPerfLoad(
        'segment.context',
        detail:
            'ms=${sw.elapsedMilliseconds} providers=${providers.length} provider=${sel.name} model=$model',
      );
    } catch (e) {
      _failEntryPerfLoad(
        'segment.context',
        e,
        detail: 'ms=${sw.elapsedMilliseconds}',
      );
    }
  }

  Future<void> _showProviderSheetSegments() async {
    final svc = AIProvidersService.instance;
    final list = await svc.listProviders();
    if (!mounted) return;
    await showAIProviderPickerSheet(
      context: context,
      providers: list,
      currentProviderId: _ctxSegProvider?.id ?? -1,
      queryText: _segProviderQueryText,
      onQueryChanged: (value) => _segProviderQueryText = value,
      initialChildSize: 0.8,
      onSelected: (sheetContext, p) async {
        final String model = resolveModelForProvider(p, _ctxSegModel);
        await AISettingsService.instance.setAIContextSelection(
          context: 'segments',
          providerId: p.id!,
          model: model,
        );
        if (!mounted || !sheetContext.mounted) return;
        _segmentStatusSetState(() {
          _ctxSegProvider = p;
          _ctxSegModel = model;
        });
        Navigator.of(sheetContext).pop();
        UINotifier.success(
          context,
          AppLocalizations.of(context).providerSelectedToast(p.name),
        );
      },
    );
  }

  Future<void> _showModelSheetSegments() async {
    final p = _ctxSegProvider;
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
    await showAIModelPickerSheet(
      context: context,
      models: models,
      activeModel: (_ctxSegModel ?? '').trim(),
      queryText: _segModelQueryText,
      onQueryChanged: (value) => _segModelQueryText = value,
      initialChildSize: 0.85,
      onSelected: (sheetContext, m) async {
        await AISettingsService.instance.setAIContextSelection(
          context: 'segments',
          providerId: p.id!,
          model: m,
        );
        if (!mounted || !sheetContext.mounted) return;
        _segmentStatusSetState(() => _ctxSegModel = m);
        Navigator.of(sheetContext).pop();
        UINotifier.success(
          context,
          AppLocalizations.of(context).modelSwitchedToast(m),
        );
      },
    );
  }

  /// AppBar 顶部：仅显示内容并加下划线（provider / model），不显示“提供商”字样
  Widget _buildSegmentsProviderModelAppBarTitle() {
    final theme = Theme.of(context);
    final String providerName = _ctxSegProvider?.name ?? '—';
    final String modelName = _ctxSegModel ?? '—';
    final TextStyle? linkStyle = theme.textTheme.labelSmall?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.onSurface.withOpacity(0.6),
      color: theme.colorScheme.onSurface,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (modelName.trim().isNotEmpty && modelName != '—') ...[
          ModelLogo(modelId: modelName, size: 18),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: GestureDetector(
            onTap: _showProviderSheetSegments,
            behavior: HitTestBehavior.opaque,
            child: Text(
              providerName,
              style: linkStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: GestureDetector(
            onTap: _showModelSheetSegments,
            behavior: HitTestBehavior.opaque,
            child: Text(
              modelName,
              style: linkStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
