part of 'settings_page.dart';

// ========== 截图采集与压缩设置 ==========
extension _SettingsScreenshotPart on _SettingsPageState {
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

  Future<void> _loadScreenshotInterval() async {
    final interval = await _appService.getScreenshotInterval();
    if (mounted) {
      _settingsSetState(() {
        _screenshotInterval = interval;
      });
    }
  }

  Future<void> _updateScreenshotInterval(int interval) async {
    await _appService.saveScreenshotInterval(interval);
    _settingsSetState(() {
      _screenshotInterval = interval;
    });
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
            if (interval == null || interval < 5 || interval > 60) {
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
        defaultValue: 'webp_lossless',
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
      if (mounted) {
        _settingsSetState(() {
          _imageFormat = format ?? 'webp_lossless';
          _imageQuality = quality.clamp(1, 100);
          _useTargetSize = useTarget;
          _targetSizeKb = targetKb < 50 ? 50 : targetKb;
          _grayscale = false; // 灰度已移除
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
      // 根据是否启用目标大小自动设置格式：启用->webp_lossy；关闭->webp_lossless（原画质）
      final String format = _useTargetSize ? 'webp_lossy' : 'webp_lossless';
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
}
