part of 'settings_page.dart';

// ========== 截图采集与压缩设置 ==========
extension _SettingsScreenshotPart on _SettingsPageState {
  String _globalCompressDaysText(BuildContext context) {
    return _globalCompressDays <= 0
        ? AppLocalizations.of(context).compressHistoryAllDays
        : _globalCompressDays.toString();
  }

  String _normalizeAiImageSendFormat(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'jpeg';
      case 'png':
        return 'png';
      default:
        return 'original';
    }
  }

  String _normalizeScreenshotDedupeMode(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'exact':
        return 'exact';
      case 'conservative':
        return 'conservative';
      case 'aggressive':
        return 'aggressive';
      case 'balanced':
      default:
        return 'balanced';
    }
  }

  String _screenshotDedupeModeLabel(BuildContext context, String value) {
    final l10n = AppLocalizations.of(context);
    switch (_normalizeScreenshotDedupeMode(value)) {
      case 'exact':
        return l10n.screenshotDedupeModeExact;
      case 'conservative':
        return l10n.screenshotDedupeModeConservative;
      case 'aggressive':
        return l10n.screenshotDedupeModeAggressive;
      default:
        return l10n.screenshotDedupeModeBalanced;
    }
  }

  String _screenshotDedupeModeDesc(BuildContext context, String value) {
    final l10n = AppLocalizations.of(context);
    switch (_normalizeScreenshotDedupeMode(value)) {
      case 'exact':
        return l10n.screenshotDedupeModeExactDesc;
      case 'conservative':
        return l10n.screenshotDedupeModeConservativeDesc;
      case 'aggressive':
        return l10n.screenshotDedupeModeAggressiveDesc;
      default:
        return l10n.screenshotDedupeModeBalancedDesc;
    }
  }

  String _aiImageSendFormatLabel(BuildContext context, String value) {
    final l10n = AppLocalizations.of(context);
    switch (_normalizeAiImageSendFormat(value)) {
      case 'jpeg':
        return l10n.aiImageSendFormatJpeg;
      case 'png':
        return l10n.aiImageSendFormatPng;
      default:
        return l10n.aiImageSendFormatOriginal;
    }
  }

  String _aiImageSendFormatDesc(BuildContext context, String value) {
    final l10n = AppLocalizations.of(context);
    switch (_normalizeAiImageSendFormat(value)) {
      case 'jpeg':
        return l10n.aiImageSendFormatJpegDesc;
      case 'png':
        return l10n.aiImageSendFormatPngDesc;
      default:
        return l10n.aiImageSendFormatOriginalDesc;
    }
  }

  Widget _buildScreenshotIntervalItem(BuildContext context) {
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
          _buildSettingsLeadingIcon(context, Icons.timer_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).screenshotIntervalTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).screenshotIntervalDesc(_screenshotInterval),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showIntervalDialog,
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

  Widget _buildScreenshotDedupeItem(BuildContext context) {
    final String label = _screenshotDedupeModeLabel(
      context,
      _screenshotDedupeMode,
    );
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
          _buildSettingsLeadingIcon(context, Icons.filter_none_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).screenshotDedupeModeTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(
                    context,
                  ).screenshotDedupeModeCurrent(label),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showScreenshotDedupeModeDialog,
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

  Widget _buildAutoAddNewAppsToCaptureItem(BuildContext context) {
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
          _buildSettingsLeadingIcon(context, Icons.playlist_add_check_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: AppTheme.spacing2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).autoAddNewAppsToCaptureTitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context).autoAddNewAppsToCaptureDesc,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: _autoAddNewAppsToCapture,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) async {
                await _updateAutoAddNewAppsToCapture(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowScreenshotApiItem(BuildContext context) {
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
          _buildSettingsLeadingIcon(context, Icons.select_all_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: AppTheme.spacing2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).windowScreenshotApiTitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context).windowScreenshotApiDesc,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: _windowScreenshotApiEnabled,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) async {
                await _updateWindowScreenshotApiEnabled(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshotQualityItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSettingsLeadingIcon(context, Icons.image_outlined),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Stack(
                  children: [
                    // 文本区域右侧预留空间，避免与右上角开关重叠
                    Padding(
                      padding: const EdgeInsets.only(right: 72),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).screenshotQualityTitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          // 说明行（根据开关禁用/启用与灰化）
                          IgnorePointer(
                            ignoring: !_useTargetSize,
                            child: Opacity(
                              opacity: _useTargetSize ? 1.0 : 0.5,
                              child: Row(
                                children: [
                                  Text(
                                    AppLocalizations.of(
                                      context,
                                    ).currentTimeLabel,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(width: AppTheme.spacing1),
                                  GestureDetector(
                                    onTap: _useTargetSize
                                        ? _showTargetSizeDialog
                                        : null,
                                    child: Text(
                                      '${_targetSizeKb}KB',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                            decoration: _useTargetSize
                                                ? TextDecoration.underline
                                                : TextDecoration.none,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: AppTheme.spacing1),
                                  Flexible(
                                    child: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).clickToModifyHint,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 右上角悬浮圆形开关（不占据垂直排布空间）
                    Positioned(
                      top: -1,
                      right: 0,
                      child: Transform.scale(
                        scale: 0.9,
                        child: Switch(
                          value: _useTargetSize,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) async {
                            _settingsSetState(() {
                              _useTargetSize = v;
                            });
                            await _saveScreenshotQualitySettings();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 与"截屏间隔"项保持一致的内边距与间距（去除多余的底部空白）
        ],
      ),
    );
  }

  Widget _buildGlobalHistoryCompressionItem(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    Widget buildUnderlinedValueText({
      required String text,
      required String value,
      required bool enabled,
    }) {
      final int index = text.indexOf(value);
      if (index < 0) {
        return Text(
          text,
          style: TextStyle(
            decoration: enabled
                ? TextDecoration.underline
                : TextDecoration.none,
          ),
        );
      }

      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text.substring(0, index)),
            TextSpan(
              text: value,
              style: TextStyle(
                decoration: enabled
                    ? TextDecoration.underline
                    : TextDecoration.none,
              ),
            ),
            TextSpan(text: text.substring(index + value.length)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: _settingsDividerSide(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingsLeadingIcon(context, Icons.auto_fix_high_outlined),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.globalCompressHistoryTitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _globalCompressDays <= 0
                          ? l10n.globalCompressHistoryDescriptionAll(
                              _targetSizeKb,
                            )
                          : l10n.globalCompressHistoryDescription(
                              _globalCompressDays,
                              _targetSizeKb,
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing3),
          Wrap(
            spacing: AppTheme.spacing2,
            runSpacing: AppTheme.spacing2,
            children: [
              TextButton(
                onPressed: _compressingGlobalHistory
                    ? null
                    : _showGlobalCompressDaysDialog,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing3,
                    vertical: AppTheme.spacing1,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: Size.zero,
                ),
                child: buildUnderlinedValueText(
                  text: l10n.compressHistorySetDays(
                    _globalCompressDaysText(context),
                  ),
                  value: _globalCompressDaysText(context),
                  enabled: !_compressingGlobalHistory,
                ),
              ),
              TextButton(
                onPressed: _compressingGlobalHistory
                    ? null
                    : _showTargetSizeDialog,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing3,
                    vertical: AppTheme.spacing1,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: Size.zero,
                ),
                child: buildUnderlinedValueText(
                  text: l10n.compressHistorySetTarget(_targetSizeKb),
                  value: _targetSizeKb.toString(),
                  enabled: !_compressingGlobalHistory,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing3),
          if (_globalCompressionProgress != null &&
              (_globalCompressionProgress!.handled > 0 ||
                  _compressingGlobalHistory))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UIProgress(
                  value: _globalCompressionProgress!.ratio.clamp(0.0, 1.0),
                  height: 4,
                ),
                const SizedBox(height: AppTheme.spacing1),
                Text(
                  l10n.compressHistoryProgress(
                    _globalCompressionProgress!.handled,
                    _globalCompressionProgress!.total,
                    formatBytes(
                      _globalCompressionProgress!.savedBytes > 0
                          ? _globalCompressionProgress!.savedBytes
                          : 0,
                    ),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing2),
              ],
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _compressingGlobalHistory
                  ? null
                  : _startGlobalHistoryCompression,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing3,
                  vertical: AppTheme.spacing2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
              ),
              child: _compressingGlobalHistory
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.onPrimary,
                        ),
                      ),
                    )
                  : Text(l10n.compressHistoryAction),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiImageSendFormatItem(BuildContext context) {
    final String label = _aiImageSendFormatLabel(context, _aiImageSendFormat);
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
          _buildSettingsLeadingIcon(context, Icons.send_to_mobile_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).aiImageSendFormatTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).aiImageSendFormatCurrent(label),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showAiImageSendFormatDialog,
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

  void _showAiImageSendFormatDialog() {
    String selected = _normalizeAiImageSendFormat(_aiImageSendFormat);
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).aiImageSendFormatDialogTitle,
      content: StatefulBuilder(
        builder: (ctx, setDialogState) {
          Widget option(String value) {
            return RadioListTile<String>(
              value: value,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(_aiImageSendFormatLabel(ctx, value)),
              subtitle: Text(_aiImageSendFormatDesc(ctx, value)),
            );
          }

          return RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) {
              if (v == null) return;
              setDialogState(() {
                selected = v;
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [option('original'), option('jpeg'), option('png')],
            ),
          );
        },
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final String normalized = _normalizeAiImageSendFormat(selected);
            _settingsSetState(() {
              _aiImageSendFormat = normalized;
            });
            await _saveAiImageSendFormat(showToast: false);
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).aiImageSendFormatSaved(
                  _aiImageSendFormatLabel(ctx, normalized),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  void _showScreenshotDedupeModeDialog() {
    String selected = _normalizeScreenshotDedupeMode(_screenshotDedupeMode);
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).screenshotDedupeModeDialogTitle,
      content: StatefulBuilder(
        builder: (ctx, setDialogState) {
          Widget option(String value) {
            return RadioListTile<String>(
              value: value,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(_screenshotDedupeModeLabel(ctx, value)),
              subtitle: Text(_screenshotDedupeModeDesc(ctx, value)),
            );
          }

          return RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) {
              if (v == null) return;
              setDialogState(() {
                selected = v;
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                option('exact'),
                option('conservative'),
                option('balanced'),
                option('aggressive'),
              ],
            ),
          );
        },
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final String normalized = _normalizeScreenshotDedupeMode(selected);
            _settingsSetState(() {
              _screenshotDedupeMode = normalized;
            });
            await _saveScreenshotDedupeMode(showToast: false);
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).screenshotDedupeModeSaved(
                  _screenshotDedupeModeLabel(ctx, normalized),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  Future<void> _loadScreenshotInterval() async {
    final interval = await _appService.getScreenshotInterval();
    if (mounted) {
      _settingsSetState(() {
        _screenshotInterval = interval;
      });
    }
  }

  Future<void> _loadAutoAddNewAppsToCapture() async {
    final enabled = await _appService.getAutoAddNewAppsToCapture();
    if (mounted) {
      _settingsSetState(() {
        _autoAddNewAppsToCapture = enabled;
      });
    }
  }

  Future<void> _updateAutoAddNewAppsToCapture(bool enabled) async {
    await _appService.saveAutoAddNewAppsToCapture(enabled);
    if (mounted) {
      _settingsSetState(() {
        _autoAddNewAppsToCapture = enabled;
      });
      UINotifier.success(
        context,
        enabled
            ? AppLocalizations.of(context).autoAddNewAppsToCaptureEnabledToast
            : AppLocalizations.of(context).autoAddNewAppsToCaptureDisabledToast,
      );
    }
  }

  Future<void> _loadWindowScreenshotApiEnabled() async {
    final enabled = await UserSettingsService.instance.getBool(
      UserSettingKeys.windowScreenshotApiEnabled,
      defaultValue: false,
      legacyPrefKeys: const <String>['window_screenshot_api_enabled'],
    );
    if (mounted) {
      _settingsSetState(() {
        _windowScreenshotApiEnabled = enabled;
      });
    }
  }

  Future<void> _updateWindowScreenshotApiEnabled(bool enabled) async {
    await UserSettingsService.instance.setBool(
      UserSettingKeys.windowScreenshotApiEnabled,
      enabled,
      legacyPrefKeys: const <String>['window_screenshot_api_enabled'],
    );
    if (mounted) {
      _settingsSetState(() {
        _windowScreenshotApiEnabled = enabled;
      });
      UINotifier.success(
        context,
        enabled
            ? AppLocalizations.of(context).windowScreenshotApiEnabledToast
            : AppLocalizations.of(context).windowScreenshotApiDisabledToast,
      );
    }
  }

  Future<void> _updateScreenshotInterval(int interval) async {
    await _appService.saveScreenshotInterval(interval);
    _settingsSetState(() {
      _screenshotInterval = interval;
    });
  }

  Future<void> _loadScreenshotDedupeMode() async {
    try {
      final String? mode = await UserSettingsService.instance.getString(
        UserSettingKeys.screenshotDedupeMode,
        defaultValue: 'balanced',
      );
      if (mounted) {
        _settingsSetState(() {
          _screenshotDedupeMode = _normalizeScreenshotDedupeMode(mode);
        });
      }
    } catch (_) {}
  }

  void _showIntervalDialog() {
    final TextEditingController controller = TextEditingController(
      text: _screenshotInterval.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).setIntervalDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).intervalSecondsLabel,
                hintText: AppLocalizations.of(context).intervalInputHint,
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(AppTheme.spacing3),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: AppTheme.fontSizeBase,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacing3),
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Text(
              AppLocalizations.of(context).intervalRangeNote,
              style: TextStyle(fontSize: 12, color: AppTheme.info),
            ),
          ),
        ],
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final input = controller.text.trim();
            final interval = int.tryParse(input);
            if (interval == null || interval < 1 || interval > 60) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).intervalInvalidError,
              );
              return;
            }
            await _updateScreenshotInterval(interval);
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).intervalSavedSuccess(interval),
              );
            }
          },
        ),
      ],
    );
  }

  void _showTargetSizeDialog() {
    final TextEditingController controller = TextEditingController(
      text: _targetSizeKb.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).setTargetSizeDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).targetSizeKbLabel,
                contentPadding: EdgeInsets.all(AppTheme.spacing3),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: AppTheme.fontSizeBase,
              ),
            ),
          ),
        ],
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final input = controller.text.trim();
            final kb = int.tryParse(input);
            if (kb == null || kb < 50) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).targetSizeInvalidError,
              );
              return;
            }
            _settingsSetState(() {
              _useTargetSize = true;
              _targetSizeKb = kb;
            });
            await _saveScreenshotQualitySettings();
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).targetSizeSavedSuccess(kb),
              );
            }
          },
        ),
      ],
    );
  }

  void _showGlobalCompressDaysDialog() {
    final TextEditingController controller = TextEditingController(
      text: _globalCompressDays <= 0 ? '0' : _globalCompressDays.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).setCompressDaysDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).compressDaysLabel,
                hintText: AppLocalizations.of(context).compressDaysInputHintAll,
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(AppTheme.spacing3),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: AppTheme.fontSizeBase,
              ),
            ),
          ),
        ],
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final int? days = int.tryParse(controller.text.trim());
            if (days == null || days < 0) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).compressDaysInvalidOrAllError,
              );
              return;
            }
            _settingsSetState(() {
              _globalCompressDays = days;
            });
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
            }
          },
        ),
      ],
    );
  }

  void _handleGlobalCompressionProgress(CompressionProgress progress) {
    if (!mounted) return;
    _settingsSetState(() {
      _globalCompressionProgress = progress;
      _compressingGlobalHistory =
          ScreenshotService.instance.globalCompressionInFlight;
    });
  }

  void _restoreGlobalCompressionState() {
    final service = ScreenshotService.instance;
    final bool ongoing = service.globalCompressionInFlight;
    final CompressionProgress? latest = service.latestGlobalCompressionProgress;
    if (!mounted) return;
    _settingsSetState(() {
      _compressingGlobalHistory = ongoing;
      if (latest != null) {
        _globalCompressionProgress = latest;
      }
    });
    if (ongoing) {
      service.attachCompressionProgressListener(
        _handleGlobalCompressionProgress,
        packageName: ScreenshotService.globalCompressionScopeKey,
      );
    }
  }

  Widget _buildGlobalCompressionDialogContent(
    AppLocalizations l10n,
    ValueListenable<CompressionProgress> progressListenable,
    ValueListenable<bool> cancellationListenable,
  ) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<CompressionProgress>(
      valueListenable: progressListenable,
      builder: (context, progress, _) {
        final double? value = progress.total <= 0
            ? null
            : progress.ratio.clamp(0.0, 1.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UIProgress(value: value, height: 8),
            const SizedBox(height: AppTheme.spacing3),
            Text(
              l10n.compressHistoryProgress(
                progress.handled,
                progress.total,
                formatBytes(progress.savedBytes > 0 ? progress.savedBytes : 0),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: cancellationListenable,
              builder: (context, isCancelling, _) {
                if (!isCancelling) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AppTheme.spacing2),
                  child: Text(
                    l10n.compressHistoryCancelling,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _startGlobalHistoryCompression() async {
    if (_compressingGlobalHistory) return;
    final l10n = AppLocalizations.of(context);
    if (_targetSizeKb < 50) {
      UINotifier.error(context, l10n.targetSizeInvalidError);
      return;
    }

    final CompressionProgress initialProgress = CompressionProgress(
      total: 0,
      handled: 0,
      success: 0,
      skipped: 0,
      failed: 0,
      savedBytes: 0,
    );
    final ValueNotifier<CompressionProgress> progressNotifier =
        ValueNotifier<CompressionProgress>(initialProgress);
    final ValueNotifier<bool> cancellationNotifier = ValueNotifier<bool>(false);
    final CompressionCancellationToken cancellationToken =
        CompressionCancellationToken();
    final Completer<BuildContext> dialogContextCompleter =
        Completer<BuildContext>();

    _settingsSetState(() {
      _compressingGlobalHistory = true;
      _globalCompressionProgress = initialProgress;
    });

    final Future<void> progressDialog = showUIDialog<void>(
      context: context,
      title: l10n.globalCompressHistoryTitle,
      barrierDismissible: false,
      canPop: false,
      constraints: const BoxConstraints(maxWidth: 420, minWidth: 280),
      content: Builder(
        builder: (dialogContext) {
          if (!dialogContextCompleter.isCompleted) {
            dialogContextCompleter.complete(dialogContext);
          }
          return _buildGlobalCompressionDialogContent(
            l10n,
            progressNotifier,
            cancellationNotifier,
          );
        },
      ),
      actions: <UIDialogAction<void>>[
        UIDialogAction<void>(
          text: l10n.dialogCancel,
          closeOnPress: false,
          onPressed: (ctx) async {
            if (cancellationToken.isCancelled) return;
            cancellationToken.cancel();
            cancellationNotifier.value = true;
          },
        ),
      ],
    );

    final BuildContext dialogContext = await dialogContextCompleter.future;
    CompressionResult? finalResult;
    try {
      finalResult = await ScreenshotService.instance.compressAllAppScreenshots(
        days: _globalCompressDays,
        targetSizeKb: _targetSizeKb,
        imageFormat: _imageFormat,
        imageQuality: _imageQuality,
        useTargetSize: true,
        cancellationToken: cancellationToken,
        onProgress: (progress) {
          progressNotifier.value = progress;
          _handleGlobalCompressionProgress(progress);
        },
      );
    } catch (_) {
      if (mounted) {
        UINotifier.error(context, l10n.compressHistoryFailure);
      }
    } finally {
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      await progressDialog.catchError((_) {});
      progressNotifier.dispose();
      cancellationNotifier.dispose();
      if (mounted) {
        _settingsSetState(() {
          _compressingGlobalHistory = false;
          if (finalResult != null) {
            _globalCompressionProgress = finalResult;
          }
        });
      }
    }

    if (!mounted || finalResult == null) return;
    if (cancellationToken.isCancelled) {
      UINotifier.info(context, l10n.compressHistoryCancelled);
      return;
    }
    if (finalResult.success > 0) {
      UINotifier.success(
        context,
        l10n.compressHistorySuccess(
          finalResult.success,
          formatBytes(finalResult.savedBytes > 0 ? finalResult.savedBytes : 0),
        ),
      );
    } else if (finalResult.failed == 0) {
      UINotifier.info(context, l10n.compressHistoryNothing);
    } else {
      UINotifier.error(context, l10n.compressHistoryFailure);
    }
  }

  Widget _buildScreenshotExpireItem(BuildContext context) {
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
          _buildSettingsLeadingIcon(context, Icons.auto_delete_outlined),
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
                        AppLocalizations.of(context).screenshotExpireTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            AppLocalizations.of(context).currentTimeLabel,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(width: AppTheme.spacing1),
                          GestureDetector(
                            onTap: _showExpireDaysDialog,
                            child: Text(
                              AppLocalizations.of(
                                context,
                              ).expireDaysUnit(_expireDays),
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
                              AppLocalizations.of(context).clickToModifyHint,
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
                      value: _expireEnabled,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) async {
                        if (v) {
                          // 开启时显示二次确认对话框
                          _showExpireEnableConfirmDialog();
                        } else {
                          // 关闭时直接保存
                          _settingsSetState(() {
                            _expireEnabled = false;
                          });
                          await _saveScreenshotExpireSettings();
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

  void _showExpireEnableConfirmDialog() {
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).expireCleanupConfirmTitle,
      content: Text(
        AppLocalizations.of(context).expireCleanupConfirmMessage(_expireDays),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).expireCleanupConfirmAction,
          style: UIDialogActionStyle.primary,
          onPressed: (ctx) async {
            _settingsSetState(() {
              _expireEnabled = true;
            });
            await _saveScreenshotExpireSettings();
            // 立即执行清理
            // ignore: unawaited_futures
            ScreenshotService.instance.cleanupExpiredScreenshotsIfNeeded(
              force: true,
            );
          },
        ),
      ],
    );
  }

  void _showExpireDaysDialog() {
    final TextEditingController controller = TextEditingController(
      text: _expireDays.toString(),
    );
    showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).setExpireDaysDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).expireDaysLabel,
                hintText: AppLocalizations.of(context).expireDaysInputHint,
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(AppTheme.spacing3),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: AppTheme.fontSizeBase,
              ),
            ),
          ),
        ],
      ),
      actions: [
        UIDialogAction(text: AppLocalizations.of(context).dialogCancel),
        UIDialogAction(
          text: AppLocalizations.of(context).dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final input = controller.text.trim();
            final d = int.tryParse(input);
            if (d == null || d < 1) {
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).expireDaysInvalidError,
              );
              return;
            }
            _settingsSetState(() {
              _expireDays = d;
            });
            await _saveScreenshotExpireSettings();
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              UINotifier.success(
                ctx,
                AppLocalizations.of(ctx).expireDaysSavedSuccess(d),
              );
            }
            // 如果开关已开启，则立即清理
            if (_expireEnabled) {
              // ignore: unawaited_futures
              ScreenshotService.instance.cleanupExpiredScreenshotsIfNeeded(
                force: true,
              );
            }
          },
        ),
      ],
    );
  }

  Future<void> _loadScreenshotQualitySettings() async {
    try {
      final String? format = await UserSettingsService.instance.getString(
        UserSettingKeys.imageFormat,
        defaultValue: 'webp_lossy',
        legacyPrefKeys: const <String>['image_format'],
      );
      final int quality = await UserSettingsService.instance.getInt(
        UserSettingKeys.imageQuality,
        defaultValue: 90,
        legacyPrefKeys: const <String>['image_quality'],
      );
      final bool useTarget = await UserSettingsService.instance.getBool(
        UserSettingKeys.useTargetSize,
        defaultValue: false,
        legacyPrefKeys: const <String>['use_target_size'],
      );
      final int targetKb = await UserSettingsService.instance.getInt(
        UserSettingKeys.targetSizeKb,
        defaultValue: 50,
        legacyPrefKeys: const <String>['target_size_kb'],
      );
      final String? aiSendFormat = await UserSettingsService.instance.getString(
        UserSettingKeys.aiImageSendFormat,
        defaultValue: 'original',
      );
      if (mounted) {
        _settingsSetState(() {
          _imageFormat = format ?? 'webp_lossy';
          _imageQuality = quality.clamp(1, 100);
          _useTargetSize = useTarget;
          _targetSizeKb = targetKb < 50 ? 50 : targetKb;
          _aiImageSendFormat = _normalizeAiImageSendFormat(aiSendFormat);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadScreenshotExpireSettings() async {
    try {
      final bool enabled = await UserSettingsService.instance.getBool(
        UserSettingKeys.screenshotExpireEnabled,
        defaultValue: false,
        legacyPrefKeys: const <String>['screenshot_expire_enabled'],
      );
      final int days = await UserSettingsService.instance.getInt(
        UserSettingKeys.screenshotExpireDays,
        defaultValue: 30,
        legacyPrefKeys: const <String>['screenshot_expire_days'],
      );
      if (mounted) {
        _settingsSetState(() {
          _expireEnabled = enabled;
          _expireDays = days < 1 ? 1 : days;
        });
      }
    } catch (_) {}
  }

  Future<void> _resyncScreenshotSettingsAfterImport() async {
    await UserSettingsService.instance.resyncScreenshotEncodingSettings();
    await Future.wait([
      _loadScreenshotDedupeMode(),
      _loadScreenshotQualitySettings(),
      _loadScreenshotExpireSettings(),
    ]);
  }

  Future<void> _saveScreenshotExpireSettings() async {
    try {
      final int days = _expireDays < 1 ? 1 : _expireDays;
      await UserSettingsService.instance.setBool(
        UserSettingKeys.screenshotExpireEnabled,
        _expireEnabled,
        legacyPrefKeys: const <String>['screenshot_expire_enabled'],
      );
      await UserSettingsService.instance.setInt(
        UserSettingKeys.screenshotExpireDays,
        days,
        legacyPrefKeys: const <String>['screenshot_expire_days'],
      );
      if (mounted) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).expireCleanupSaved,
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

  Future<void> _loadPrivacyMode() async {
    try {
      final enabled = await _appService.getPrivacyModeEnabled();
      if (mounted) {
        _settingsSetState(() {
          _privacyMode = enabled;
        });
      }
    } catch (_) {}
  }

  Future<void> _updatePrivacyMode(bool enabled) async {
    await _appService.savePrivacyModeEnabled(enabled);
    if (mounted) {
      _settingsSetState(() {
        _privacyMode = enabled;
      });
      UINotifier.success(
        context,
        enabled
            ? AppLocalizations.of(context).privacyModeEnabledToast
            : AppLocalizations.of(context).privacyModeDisabledToast,
      );
    }
  }

  Future<void> _saveScreenshotQualitySettings() async {
    try {
      // 根据是否启用目标大小自动设置格式：启用->webp_lossy；关闭->保留当前格式（默认 webp_lossy）
      final String format = _useTargetSize ? 'webp_lossy' : _imageFormat;
      await UserSettingsService.instance.setString(
        UserSettingKeys.imageFormat,
        format,
        legacyPrefKeys: const <String>['image_format'],
      );
      await UserSettingsService.instance.setInt(
        UserSettingKeys.imageQuality,
        _imageQuality,
        legacyPrefKeys: const <String>['image_quality'],
      );
      await UserSettingsService.instance.setBool(
        UserSettingKeys.useTargetSize,
        _useTargetSize,
        legacyPrefKeys: const <String>['use_target_size'],
      );
      await UserSettingsService.instance.setInt(
        UserSettingKeys.targetSizeKb,
        _targetSizeKb < 50 ? 50 : _targetSizeKb,
        legacyPrefKeys: const <String>['target_size_kb'],
      );
      // 不再保存灰度
      if (mounted) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).screenshotQualitySettingsSaved,
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

  Future<void> _saveScreenshotDedupeMode({bool showToast = true}) async {
    try {
      final String mode = _normalizeScreenshotDedupeMode(_screenshotDedupeMode);
      await UserSettingsService.instance.setString(
        UserSettingKeys.screenshotDedupeMode,
        mode,
      );
      if (mounted && showToast) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).screenshotDedupeModeSaved(
            _screenshotDedupeModeLabel(context, mode),
          ),
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

  Future<void> _saveAiImageSendFormat({bool showToast = true}) async {
    try {
      final String format = _normalizeAiImageSendFormat(_aiImageSendFormat);
      await UserSettingsService.instance.setString(
        UserSettingKeys.aiImageSendFormat,
        format,
      );
      if (mounted && showToast) {
        UINotifier.success(
          context,
          AppLocalizations.of(
            context,
          ).aiImageSendFormatSaved(_aiImageSendFormatLabel(context, format)),
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
}
