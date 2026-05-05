part of 'settings_page.dart';

// ========== 动态总结与 AI 设置 ==========
extension _SettingsSegmentPart on _SettingsPageState {
  Widget _buildSegmentSampleItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.photo_library_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).segmentSampleIntervalTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).segmentSampleIntervalDesc(_segmentSampleIntervalSec),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showSegmentSampleDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentDurationItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.schedule_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).segmentDurationTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).segmentDurationDesc(_segmentDurationMin),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showSegmentDurationDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  // ===== 动态合并限制 UI =====
  Widget _buildDynamicMergeMaxSpanItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: _settingsDividerSide(context),
          bottom: _settingsDividerSide(context),
        ),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.merge_type_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).dynamicMergeMaxSpanTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).dynamicMergeMaxSpanDesc(_dynamicMergeMaxSpanMin),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showDynamicMergeMaxSpanDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicMergeMaxGapItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.more_time_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).dynamicMergeMaxGapTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).dynamicMergeMaxGapDesc(_dynamicMergeMaxGapMin),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showDynamicMergeMaxGapDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicMergeMaxImagesItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.image_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).dynamicMergeMaxImagesTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).dynamicMergeMaxImagesDesc(_dynamicMergeMaxImages),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showDynamicMergeMaxImagesDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  // ===== AI请求间隔设置 UI =====
  Widget _buildAiRequestIntervalItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.speed_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).aiRequestIntervalTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).aiRequestIntervalDesc(_aiRequestIntervalSec),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showAiRequestIntervalDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  // ===== 动态总结格式自动重试次数 =====
  Widget _buildSegmentsJsonAutoRetryMaxItem(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.autorenew_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.segmentsJsonAutoRetryTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '${l10n.segmentsJsonAutoRetryDesc} ${l10n.settingCurrentValue(_segmentsJsonAutoRetryMax)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showSegmentsJsonAutoRetryMaxDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionSet),
          ),
        ],
      ),
    );
  }

  bool _isZhLocale(BuildContext context) {
    try {
      return Localizations.localeOf(
        context,
      ).languageCode.toLowerCase().startsWith('zh');
    } catch (_) {
      return true;
    }
  }

  Widget _buildAiRawResponseCleanupItem(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(context, Icons.cleaning_services_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.rawResponseCleanupTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            l10n.rawResponseCleanupKeepLabel,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(width: AppTheme.spacing1),
                          GestureDetector(
                            onTap: _showAiRawResponseCleanupDaysDialog,
                            child: Text(
                              l10n.rawResponseCleanupRetentionDays(
                                _aiRawResponseCleanupDays,
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing1),
                          Flexible(
                            child: Text(
                              l10n.rawResponseCleanupDesc,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: -1,
                  right: 0,
                  child: Transform.scale(
                    scale: 0.9,
                    child: Switch(
                      value: _aiRawResponseCleanupEnabled,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) async {
                        if (v) {
                          _showAiRawResponseCleanupEnableConfirmDialog();
                        } else {
                          _settingsSetState(() {
                            _aiRawResponseCleanupEnabled = false;
                          });
                          await _saveAiRawResponseCleanupSettings();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAiRequestIntervalDialog() {
    final TextEditingController controller = TextEditingController(
      text: _aiRequestIntervalSec.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).aiRequestIntervalTitle,
      content: _numberDialogContent(
        explanation: AppLocalizations.of(
          context,
        ).dynamicSettingAiRequestIntervalExplanation,
        controller: controller,
        hint: AppLocalizations.of(context).intervalInputHint,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed < 1) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).intervalInvalidError,
              );
              return;
            }
            final v = parsed.clamp(1, 60);
            try {
              const platform = MethodChannel(
                'com.fqyw.screen_memo/accessibility',
              );
              await platform.invokeMethod('setAiRequestIntervalSec', {
                'seconds': v,
              });
              if (mounted)
                _settingsSetState(() {
                  _aiRequestIntervalSec = v;
                });
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                UINotifier.success(
                  ctx,
                  AppLocalizations.of(ctx).intervalSavedSuccess(v),
                );
              }
            } catch (e) {
              if (ctx.mounted)
                UINotifier.error(
                  ctx,
                  AppLocalizations.of(
                    ctx,
                  ).requestPermissionFailed(e.toString()),
                );
            }
          },
        ),
      ],
    );
  }

  void _showSegmentsJsonAutoRetryMaxDialog() {
    final TextEditingController controller = TextEditingController(
      text: _segmentsJsonAutoRetryMax.toString(),
    );
    final l10n = AppLocalizations.of(context);

    showUIDialog<void>(
      context: context,
      title: l10n.segmentsJsonAutoRetryTitle,
      content: _numberDialogContent(
        explanation: l10n.dynamicSettingAutoRetryExplanation,
        controller: controller,
        hint: l10n.segmentsJsonAutoRetryHint,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).resetToDefault,
          style: UIDialogActionStyle.destructive,
          closeOnPress: false,
          onPressed: (ctx) async {
            const int v = 1;
            try {
              await AISettingsService.instance.setSegmentsJsonAutoRetryMax(v);
              if (mounted) {
                _settingsSetState(() {
                  _segmentsJsonAutoRetryMax = v;
                });
              }
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                UINotifier.success(
                  ctx,
                  AppLocalizations.of(ctx).resetToDefaultValue(v),
                );
              }
            } catch (e) {
              if (ctx.mounted) {
                UINotifier.error(
                  ctx,
                  AppLocalizations.of(ctx).saveFailedError(e.toString()),
                );
              }
            }
          },
        ),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).numberInputRequired,
              );
              return;
            }
            final v = parsed.clamp(0, 5);
            try {
              await AISettingsService.instance.setSegmentsJsonAutoRetryMax(v);
              if (mounted) {
                _settingsSetState(() {
                  _segmentsJsonAutoRetryMax = v;
                });
              }
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                UINotifier.success(ctx, AppLocalizations.of(ctx).valueSaved(v));
              }
            } catch (e) {
              if (ctx.mounted) {
                UINotifier.error(
                  ctx,
                  AppLocalizations.of(ctx).saveFailedError(e.toString()),
                );
              }
            }
          },
        ),
      ],
    );
  }

  void _showAiRawResponseCleanupEnableConfirmDialog() {
    final l10n = AppLocalizations.of(context);
    showUIDialog<void>(
      context: context,
      title: l10n.rawResponseCleanupEnableTitle,
      content: Text(
        l10n.rawResponseCleanupEnableMessage(_aiRawResponseCleanupDays),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: l10n.rawResponseCleanupEnableAction,
          style: UIDialogActionStyle.primary,
          onPressed: (ctx) async {
            _settingsSetState(() {
              _aiRawResponseCleanupEnabled = true;
            });
            await _saveAiRawResponseCleanupSettings();
            unawaited(
              AISettingsService.instance.cleanupExpiredRawResponsesIfNeeded(
                force: true,
              ),
            );
          },
        ),
      ],
    );
  }

  void _showAiRawResponseCleanupDaysDialog() {
    final TextEditingController controller = TextEditingController(
      text: _aiRawResponseCleanupDays.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).rawResponseRetentionDaysTitle,
      content: _numberDialogContent(
        explanation: AppLocalizations.of(
          context,
        ).dynamicSettingRawResponseRetentionExplanation,
        controller: controller,
        hint: AppLocalizations.of(context).rawResponseRetentionDaysLabel,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final int? days = int.tryParse(controller.text.trim());
            if (days == null || days < 1) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(context).rawResponseRetentionDaysHint,
              );
              return;
            }
            _settingsSetState(() {
              _aiRawResponseCleanupDays = days;
            });
            await _saveAiRawResponseCleanupSettings();
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(
                  context,
                ).rawResponseRetentionUpdatedDays(days),
              );
            }
            if (_aiRawResponseCleanupEnabled) {
              unawaited(
                AISettingsService.instance.cleanupExpiredRawResponsesIfNeeded(
                  force: true,
                ),
              );
            }
          },
        ),
      ],
    );
  }

  void _showDynamicMergeMaxSpanDialog() {
    final TextEditingController controller = TextEditingController(
      text: _dynamicMergeMaxSpanMin.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).dynamicMergeMaxSpanTitle,
      content: _numberDialogContent(
        explanation: AppLocalizations.of(
          context,
        ).dynamicSettingMergeMaxSpanExplanation,
        controller: controller,
        hint: AppLocalizations.of(context).dynamicMergeLimitInputHint,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed < 0) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).dynamicMergeLimitInvalidError,
              );
              return;
            }
            final v = parsed.clamp(0, 7 * 24 * 60);
            final ok = await _saveDynamicMergeLimits(
              maxSpanMin: v,
              maxGapMin: _dynamicMergeMaxGapMin,
              maxImages: _dynamicMergeMaxImages,
            );
            if (ctx.mounted && ok) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, AppLocalizations.of(ctx).saveSuccess);
            }
          },
        ),
      ],
    );
  }

  void _showDynamicMergeMaxGapDialog() {
    final TextEditingController controller = TextEditingController(
      text: _dynamicMergeMaxGapMin.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).dynamicMergeMaxGapTitle,
      content: _numberDialogContent(
        explanation: AppLocalizations.of(
          context,
        ).dynamicSettingMergeMaxGapExplanation,
        controller: controller,
        hint: AppLocalizations.of(context).dynamicMergeLimitInputHint,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed < 0) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).dynamicMergeLimitInvalidError,
              );
              return;
            }
            final v = parsed.clamp(0, 7 * 24 * 60);
            final ok = await _saveDynamicMergeLimits(
              maxSpanMin: _dynamicMergeMaxSpanMin,
              maxGapMin: v,
              maxImages: _dynamicMergeMaxImages,
            );
            if (ctx.mounted && ok) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, AppLocalizations.of(ctx).saveSuccess);
            }
          },
        ),
      ],
    );
  }

  void _showDynamicMergeMaxImagesDialog() {
    final TextEditingController controller = TextEditingController(
      text: _dynamicMergeMaxImages.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).dynamicMergeMaxImagesTitle,
      content: _numberDialogContent(
        explanation: AppLocalizations.of(
          context,
        ).dynamicSettingMergeMaxImagesExplanation,
        controller: controller,
        hint: AppLocalizations.of(context).dynamicMergeLimitInputHint,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed < 0) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).dynamicMergeLimitInvalidError,
              );
              return;
            }
            final v = parsed.clamp(0, 100000);
            final ok = await _saveDynamicMergeLimits(
              maxSpanMin: _dynamicMergeMaxSpanMin,
              maxGapMin: _dynamicMergeMaxGapMin,
              maxImages: v,
            );
            if (ctx.mounted && ok) {
              Navigator.of(ctx).pop();
              UINotifier.success(ctx, AppLocalizations.of(ctx).saveSuccess);
            }
          },
        ),
      ],
    );
  }

  Future<void> _loadSegmentSettings() async {
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      final res = await platform.invokeMethod('getSegmentSettings');
      final map = Map<String, dynamic>.from(res ?? {});
      if (mounted) {
        _settingsSetState(() {
          _segmentSampleIntervalSec = ((map['sampleIntervalSec'] as int?) ?? 20)
              .clamp(5, 3600);
          final durSec = ((map['segmentDurationSec'] as int?) ?? 300).clamp(
            60,
            24 * 3600,
          );
          _segmentDurationMin = (durSec / 60).round();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDynamicMergeLimits() async {
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      final res = await platform.invokeMethod('getDynamicMergeLimits');
      final map = Map<String, dynamic>.from(res ?? {});
      final int spanSec = (map['maxSpanSec'] as int?) ?? 3 * 3600;
      final int gapSec = (map['maxGapSec'] as int?) ?? 3600;
      final int maxImages = (map['maxImages'] as int?) ?? 200;
      if (mounted) {
        _settingsSetState(() {
          _dynamicMergeMaxSpanMin = ((spanSec / 60).round())
              .clamp(0, 7 * 24 * 60)
              .toInt();
          _dynamicMergeMaxGapMin = ((gapSec / 60).round())
              .clamp(0, 7 * 24 * 60)
              .toInt();
          _dynamicMergeMaxImages = maxImages.clamp(0, 100000).toInt();
        });
      }
    } catch (_) {
      // keep defaults
    }
  }

  // 读取AI请求最小间隔（秒），默认3，最低1
  Future<void> _loadAiRequestInterval() async {
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      final sec = await platform.invokeMethod('getAiRequestIntervalSec');
      final v = (sec as int?) ?? 3;
      if (mounted) {
        _settingsSetState(() {
          _aiRequestIntervalSec = v.clamp(1, 60);
        });
      }
    } catch (_) {
      if (mounted)
        _settingsSetState(() {
          _aiRequestIntervalSec = 3;
        });
    }
  }

  Future<void> _loadSegmentsJsonAutoRetryMax() async {
    try {
      final v = await AISettingsService.instance.getSegmentsJsonAutoRetryMax();
      if (mounted) {
        _settingsSetState(() {
          _segmentsJsonAutoRetryMax = v;
        });
      }
    } catch (_) {
      if (mounted) {
        _settingsSetState(() {
          _segmentsJsonAutoRetryMax = 1;
        });
      }
    }
  }

  Future<void> _loadAiRawResponseCleanupSettings() async {
    try {
      final bool enabled = await AISettingsService.instance
          .getRawResponseCleanupEnabled();
      final int days = await AISettingsService.instance
          .getRawResponseCleanupDays();
      if (mounted) {
        _settingsSetState(() {
          _aiRawResponseCleanupEnabled = enabled;
          _aiRawResponseCleanupDays = days < 1 ? 1 : days;
        });
      }
    } catch (_) {
      if (mounted) {
        _settingsSetState(() {
          _aiRawResponseCleanupEnabled = true;
          _aiRawResponseCleanupDays = 30;
        });
      }
    }
  }

  void _showSegmentSampleDialog() {
    final TextEditingController controller = TextEditingController(
      text: _segmentSampleIntervalSec.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).segmentSampleIntervalTitle,
      content: _numberDialogContent(
        explanation: AppLocalizations.of(
          context,
        ).dynamicSettingSampleExplanation,
        controller: controller,
        hint: AppLocalizations.of(context).intervalInputHint,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final v = int.tryParse(controller.text.trim());
            if (v == null || v < 5) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).intervalInvalidError,
              );
              return;
            }
            final ok = await _saveSegmentSettings(
              sample: v,
              durationMin: _segmentDurationMin,
            );
            if (ctx.mounted && ok) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).intervalSavedSuccess(v),
              );
            }
          },
        ),
      ],
    );
  }

  void _showSegmentDurationDialog() {
    final TextEditingController controller = TextEditingController(
      text: _segmentDurationMin.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).segmentDurationTitle,
      content: _numberDialogContent(
        explanation: AppLocalizations.of(
          context,
        ).dynamicSettingDurationExplanation,
        controller: controller,
        hint: AppLocalizations.of(context).intervalInputHint,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final v = int.tryParse(controller.text.trim());
            if (v == null || v < 1) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).intervalInvalidError,
              );
              return;
            }
            final ok = await _saveSegmentSettings(
              sample: _segmentSampleIntervalSec,
              durationMin: v,
            );
            if (ctx.mounted && ok) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).expireDaysSavedSuccess(v),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController c, {required String hint}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: hint,
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(AppTheme.spacing3),
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
      ),
    );
  }

  Widget _numberDialogContent({
    required String explanation,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          explanation,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppTheme.spacing3),
        _numberField(controller, hint: hint),
      ],
    );
  }

  Future<bool> _saveSegmentSettings({
    required int sample,
    required int durationMin,
  }) async {
    final sampleClamped = sample < 5 ? 5 : sample;
    final durationSec = (durationMin <= 0 ? 1 : durationMin) * 60;
    try {
      try {
        await FlutterLogger.nativeInfo(
          'Settings',
          '设置动态参数：sampleIntervalSec=$sampleClamped，segmentDurationSec=$durationSec',
        );
      } catch (_) {}
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      await platform.invokeMethod('setSegmentSettings', {
        'sampleIntervalSec': sampleClamped,
        'segmentDurationSec': durationSec,
      });
      try {
        final res = await platform.invokeMethod('getSegmentSettings');
        await FlutterLogger.nativeInfo(
          'Settings',
          '保存后读取 getSegmentSettings：$res',
        );
      } catch (e) {
        try {
          await FlutterLogger.nativeWarn(
            'Settings',
            '保存后读取 getSegmentSettings 失败：$e',
          );
        } catch (_) {}
      }
      _settingsSetState(() {
        _segmentSampleIntervalSec = sampleClamped;
        _segmentDurationMin = durationMin;
      });
      return true;
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
      try {
        await FlutterLogger.nativeError('Settings', 'setSegmentSettings 失败：$e');
      } catch (_) {}
      return false;
    }
  }

  Future<void> _saveAiRawResponseCleanupSettings() async {
    try {
      final int days = _aiRawResponseCleanupDays < 1
          ? 1
          : _aiRawResponseCleanupDays;
      await AISettingsService.instance.setRawResponseCleanupEnabled(
        _aiRawResponseCleanupEnabled,
      );
      await AISettingsService.instance.setRawResponseCleanupDays(days);
      if (mounted) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).rawResponseCleanupSaved,
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
    }
  }

  Future<bool> _saveDynamicMergeLimits({
    required int maxSpanMin,
    required int maxGapMin,
    required int maxImages,
  }) async {
    final int spanMinClamped = maxSpanMin < 0 ? 0 : maxSpanMin;
    final int gapMinClamped = maxGapMin < 0 ? 0 : maxGapMin;
    final int maxImagesClamped = maxImages.clamp(0, 100000).toInt();
    final int spanSec = spanMinClamped * 60;
    final int gapSec = gapMinClamped * 60;
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      await platform.invokeMethod('setDynamicMergeLimits', {
        'maxSpanSec': spanSec,
        'maxGapSec': gapSec,
        'maxImages': maxImagesClamped,
      });
      if (mounted) {
        _settingsSetState(() {
          _dynamicMergeMaxSpanMin = spanMinClamped;
          _dynamicMergeMaxGapMin = gapMinClamped;
          _dynamicMergeMaxImages = maxImagesClamped;
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
      return false;
    }
  }
}
