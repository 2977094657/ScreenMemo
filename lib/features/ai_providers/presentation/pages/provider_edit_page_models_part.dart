part of 'provider_edit_page.dart';

extension _ProviderEditModelsPart on _ProviderEditPageState {
  Widget _buildLifecycleItem({
    required IconData icon,
    required String label,
    required String value,
    bool alignEnd = false,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: alignEnd
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            value,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildModelCard(
    BuildContext context,
    String model, {
    required VoidCallback onRemove,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final meta = _metadataForModel(model);
    final costItems = _modelCostItems(meta, l10n);
    final lifecycleRow = _buildModelLifecycleRow(meta, l10n);
    final status = _modelStatusLabel(meta?.status, l10n);

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
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildModelLogoBox(model: model, meta: meta),
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                model,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (status != null) ...[
                              const SizedBox(width: AppTheme.spacing2),
                              _buildModelStatusBadge(status, theme),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _modelLimitLine(model, l10n),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context).actionDelete,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    color: theme.colorScheme.onSurfaceVariant,
                    onPressed: onRemove,
                  ),
                ],
              ),
            ),
            if (costItems.isNotEmpty) _buildModelCostBand(context, costItems),
            if (lifecycleRow != null) lifecycleRow,
            _buildModelCapabilitySection(context, meta),
          ],
        ),
      ),
    );
  }

  Widget _buildModelLogoBox({
    required String model,
    required ModelsDevModelInfo? meta,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.42),
          width: 0.7,
        ),
      ),
      child: ModelLogo(modelId: model, metadata: meta, size: 24),
    );
  }

  String? _modelStatusLabel(String? status, AppLocalizations l10n) {
    final raw = (status ?? '').trim();
    if (raw.isEmpty) return null;
    final normalized = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    switch (normalized) {
      case 'flagship':
        return l10n.modelStatusFlagship;
      case 'preview':
        return l10n.modelStatusPreview;
      case 'beta':
        return l10n.modelStatusBeta;
      case 'deprecated':
        return l10n.modelStatusDeprecated;
      case 'experimental':
        return l10n.modelStatusExperimental;
      case 'stable':
        return l10n.modelStatusStable;
      default:
        return raw;
    }
  }

  Widget _buildModelStatusBadge(String status, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: AppTheme.warning.withValues(alpha: 0.4),
          width: 0.7,
        ),
      ),
      child: Text(
        status,
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppTheme.warning,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildModelCostBand(
    BuildContext context,
    List<_ModelCostDisplayItem> items,
  ) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.scaffoldBackgroundColor.withValues(alpha: 0.72),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool fillWidth =
              items.length <= 4 && constraints.maxWidth.isFinite;
          final double cellWidth = fillWidth
              ? (constraints.maxWidth - (items.length - 1)) / items.length
              : 112;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  SizedBox(
                    width: fillWidth
                        ? cellWidth.clamp(0.0, double.infinity)
                        : (cellWidth < 92.0 ? 92.0 : cellWidth),
                    child: _buildModelCostCell(context, items[i]),
                  ),
                  if (i != items.length - 1) _buildThinVerticalDivider(theme),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildModelCostCell(BuildContext context, _ModelCostDisplayItem item) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          item.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildModelCapabilitySection(
    BuildContext context,
    ModelsDevModelInfo? meta,
  ) {
    if (meta == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final abilityChips = <Widget>[];
    final inputChips = <Widget>[];
    final outputChips = <Widget>[];

    if (meta.reasoning == true) {
      abilityChips.add(
        _buildMetaChip(
          context,
          icon: Icons.psychology,
          label: l10n.modelCapabilityReasoningLabel,
          tooltip: l10n.modelCapabilityReasoningLabel,
        ),
      );
    }
    if (meta.toolCall == true) {
      abilityChips.add(
        _buildMetaChip(
          context,
          icon: Icons.build,
          label: l10n.modelCapabilityToolsLabel,
          tooltip: l10n.modelCapabilityToolsLabel,
        ),
      );
    }
    if (meta.structuredOutput == true) {
      abilityChips.add(
        _buildMetaChip(
          context,
          icon: Icons.code,
          label: l10n.modelCapabilityStructuredOutputLabel,
          tooltip: l10n.modelCapabilityStructuredOutputLabel,
        ),
      );
    }
    if (meta.attachment == true) {
      inputChips.add(
        _buildMetaChip(
          context,
          icon: Icons.attach_file,
          label: l10n.modelCapabilityAttachmentsLabel,
          tooltip: l10n.modelCapabilityAttachmentsLabel,
        ),
      );
    }
    for (final modality in _uniqueModalities(meta.inputModalities)) {
      inputChips.add(_buildModalityChip(context, modality, l10n: l10n));
    }
    for (final modality in _uniqueModalities(meta.outputModalities)) {
      outputChips.add(_buildModalityChip(context, modality, l10n: l10n));
    }

    final rows = <Widget>[
      if (abilityChips.isNotEmpty)
        _buildModelChipRow(l10n.modelCapabilitySectionLabel, abilityChips),
      if (inputChips.isNotEmpty)
        _buildModelChipRow(l10n.modelInputSupportSectionLabel, inputChips),
      if (outputChips.isNotEmpty)
        _buildModelChipRow(l10n.modelOutputSupportSectionLabel, outputChips),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _buildModelChipRow(String label, List<Widget> chips) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
      ],
    );
  }

  Iterable<String> _uniqueModalities(List<String> modalities) sync* {
    final seen = <String>{};
    for (final raw in modalities) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      if (seen.add(value.toLowerCase())) yield value;
    }
  }

  Widget _buildModalityChip(
    BuildContext context,
    String modality, {
    required AppLocalizations l10n,
  }) {
    final label = _modelModalityLabel(modality, l10n);
    return _buildMetaChip(
      context,
      icon: _modelModalityIcon(modality),
      label: label,
      tooltip: label,
    );
  }

  String _modelModalityLabel(String modality, AppLocalizations l10n) {
    final normalized = modality.trim().toLowerCase();
    if (normalized.isEmpty) return l10n.modelMetaUnknownValue;
    if (normalized.contains('image')) return l10n.modelModalityImageLabel;
    if (normalized.contains('audio')) return l10n.modelModalityAudioLabel;
    if (normalized.contains('video')) return l10n.modelModalityVideoLabel;
    if (normalized.contains('pdf')) return l10n.modelModalityPdfLabel;
    if (normalized.contains('text')) return l10n.modelModalityTextLabel;
    return modality.trim();
  }

  IconData _modelModalityIcon(String modality) {
    final normalized = modality.trim().toLowerCase();
    if (normalized.contains('image')) return Icons.image;
    if (normalized.contains('audio')) return Icons.graphic_eq;
    if (normalized.contains('video')) return Icons.videocam;
    if (normalized.contains('pdf')) return Icons.picture_as_pdf;
    if (normalized.contains('text')) return Icons.text_fields;
    return Icons.extension;
  }

  Widget _buildMetaChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String tooltip,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    // 用紧凑 chip 承载模型能力，Tooltip 保留完整本地化说明。
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.62),
              width: 0.7,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  label,
                  style: textStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
