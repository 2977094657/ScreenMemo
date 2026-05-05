part of 'provider_edit_page.dart';

extension _ProviderEditFormPart on _ProviderEditPageState {
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
            onChanged: (v) => _providerEditSetState(() => _useResponseApi = v),
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
            onChanged: (v) =>
                _providerEditSetState(() => _balanceAutoDeleteZeroKey = v),
          ),
        ],
      ],
    );
  }

  Widget _buildKeysHeaderCard(ThemeData theme) {
    final keyCountText = _keys.length > 99 ? '99+' : '${_keys.length}';
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
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppTheme.spacing2,
                runSpacing: AppTheme.spacing1,
                children: [
                  Text(
                    'APIKey（$keyCountText）',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (balanceSummary != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.35,
                          ),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            balanceSummary,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacing2),
            PopupMenuButton<_ProviderKeySortMode>(
              initialValue: _keySortMode,
              onSelected: (mode) =>
                  _providerEditSetState(() => _keySortMode = mode),
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
    return Column(
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
                    hintText: AppLocalizations.of(context).inputAndAddModelHint,
                    hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mutedForeground,
                    ),
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
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _models.length,
            itemBuilder: (c, i) {
              final m = _models[i];
              return _buildModelCard(
                c,
                m,
                onRemove: () {
                  _providerEditSetState(() {
                    _models = List<String>.from(_models)..removeAt(i);
                    _modelInfoByName.remove(m.trim().toLowerCase());
                  });
                },
              );
            },
          ),
        ],
      ],
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
              _providerEditSetState(() {
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
            _providerEditSetState(() {
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
            _providerEditSetState(() {
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
