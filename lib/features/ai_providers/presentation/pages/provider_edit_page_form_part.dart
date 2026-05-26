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
        if (_type == AIProviderTypes.openai ||
            _type == AIProviderTypes.custom) ...[
          const SizedBox(height: AppTheme.spacing4),
          _buildApiModeCards(),
        ],
      ],
    );
  }

  Widget _buildKeysHeaderCard(ThemeData theme) {
    final keyCountText = _keys.length > 99 ? '99+' : '${_keys.length}';
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
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacing2),
            UIActionMenuButton<_ProviderKeySortMode>(
              selectedValue: _keySortMode,
              onSelected: (mode) =>
                  _providerEditSetState(() => _keySortMode = mode),
              minWidth: 204,
              items: [
                for (final mode in _ProviderKeySortMode.values)
                  UIActionMenuItem<_ProviderKeySortMode>(
                    value: mode,
                    label: _keySortModeLabel(mode),
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
                    (_loaded == null ||
                        _keys.isEmpty ||
                        _saving ||
                        _fetching ||
                        _batchRunning)
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
        if (_loaded != null && _keys.isEmpty)
          Text(
            AppLocalizations.of(context).providerNoApiKeys,
            style: theme.textTheme.bodySmall,
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

  Widget _buildTypePicker() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final items = <UISelectItem<String>>[
      UISelectItem<String>(
        value: AIProviderTypes.openai,
        label: l10n.providerTypeOpenAI,
      ),
      UISelectItem<String>(
        value: AIProviderTypes.claude,
        label: l10n.providerTypeClaude,
      ),
      UISelectItem<String>(
        value: AIProviderTypes.gemini,
        label: l10n.providerTypeGemini,
      ),
      UISelectItem<String>(
        value: AIProviderTypes.custom,
        label: l10n.customLabel,
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
        UISelectField<String>(
          value: _type,
          items: items,
          onChanged: (v) {
            if (v == null) return;
            _providerEditSetState(() {
              _applyTypeDefaults(v);
            });
          },
        ),
      ],
    );
  }

  Widget _buildApiModeCards() {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final chatCard = _buildApiModeCard(
          selected: !_useResponseApi,
          title: l10n.providerApiModeChatTitle,
          icon: Icons.chat_bubble_outline_rounded,
          compact: compact,
          onTap: () => _providerEditSetState(() => _useResponseApi = false),
        );
        final responsesCard = _buildApiModeCard(
          selected: _useResponseApi,
          title: l10n.providerApiModeResponsesTitle,
          icon: Icons.auto_awesome_outlined,
          compact: compact,
          onTap: () => _providerEditSetState(() => _useResponseApi = true),
        );

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: chatCard),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(child: responsesCard),
            ],
          ),
        );
      },
    );
  }

  Widget _buildApiModeCard({
    required bool selected,
    required String title,
    required IconData icon,
    required bool compact,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bgColor = selected
        ? colorScheme.primaryContainer.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.22 : 0.42,
          )
        : colorScheme.surface;
    final borderColor = selected
        ? colorScheme.primary
        : colorScheme.outline.withValues(alpha: 0.55);
    final titleColor = selected ? colorScheme.primary : colorScheme.onSurface;
    final contentColor = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.all(
              compact ? AppTheme.spacing2 : AppTheme.spacing3,
            ),
            constraints: BoxConstraints(minHeight: compact ? 48 : 52),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: compact ? 18 : 20, color: titleColor),
                SizedBox(
                  width: compact ? AppTheme.spacing2 : AppTheme.spacing3,
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: contentColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spacing2),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: compact ? 18 : 20,
                  color: titleColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
