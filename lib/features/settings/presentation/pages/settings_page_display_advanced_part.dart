part of 'settings_page.dart';

// ========== 显示与高级设置 ==========
extension _SettingsDisplayAdvancedPart on _SettingsPageState {
  Future<void> _loadLoggingEnabled() async {
    try {
      _loggingEnabled = FlutterLogger.enabled;
      _aiLoggingEnabled = await FlutterLogger.getCategoryEnabled('ai');
      _screenshotLoggingEnabled = await FlutterLogger.getCategoryEnabled(
        'screenshot',
      );
      if (mounted) _settingsSetState(() {});
    } catch (_) {}
  }

  Future<void> _updateLoggingEnabled(bool enabled) async {
    try {
      await FlutterLogger.setEnabled(enabled);
      if (mounted) _settingsSetState(() => _loggingEnabled = enabled);
    } catch (_) {}
  }

  Future<void> _updateAiLoggingEnabled(bool enabled) async {
    try {
      await FlutterLogger.setCategoryEnabled('ai', enabled);
      if (mounted) _settingsSetState(() => _aiLoggingEnabled = enabled);
    } catch (_) {}
  }

  Future<void> _updateScreenshotLoggingEnabled(bool enabled) async {
    try {
      await FlutterLogger.setCategoryEnabled('screenshot', enabled);
      if (mounted) _settingsSetState(() => _screenshotLoggingEnabled = enabled);
    } catch (_) {}
  }

  Future<void> _loadRenderImagesDuringStreaming() async {
    try {
      final v = await AISettingsService.instance
          .getRenderImagesDuringStreaming();
      if (mounted) _settingsSetState(() => _renderImagesDuringStreaming = v);
    } catch (_) {}
  }

  Future<void> _updateRenderImagesDuringStreaming(bool enabled) async {
    try {
      await AISettingsService.instance.setRenderImagesDuringStreaming(enabled);
      if (mounted)
        _settingsSetState(() => _renderImagesDuringStreaming = enabled);
    } catch (_) {}
  }

  Future<void> _loadAiChatPerfOverlayEnabled() async {
    try {
      final v = await AISettingsService.instance.getAiChatPerfOverlayEnabled();
      if (mounted) _settingsSetState(() => _aiChatPerfOverlayEnabled = v);
    } catch (_) {}
  }

  Future<void> _updateAiChatPerfOverlayEnabled(bool enabled) async {
    try {
      await AISettingsService.instance.setAiChatPerfOverlayEnabled(enabled);
      if (mounted) _settingsSetState(() => _aiChatPerfOverlayEnabled = enabled);
    } catch (_) {}
  }

  Future<void> _loadDynamicEntryLogIconEnabled() async {
    try {
      final bool enabled = await UserSettingsService.instance.getBool(
        UserSettingKeys.dynamicEntryLogIconEnabled,
        defaultValue: false,
      );
      if (mounted) {
        _settingsSetState(() => _dynamicEntryLogIconEnabled = enabled);
      }
    } catch (_) {}
  }

  Future<void> _updateDynamicEntryLogIconEnabled(bool enabled) async {
    try {
      await UserSettingsService.instance.setBool(
        UserSettingKeys.dynamicEntryLogIconEnabled,
        enabled,
      );
      if (mounted) {
        _settingsSetState(() => _dynamicEntryLogIconEnabled = enabled);
      }
    } catch (_) {}
  }

  String _themeModeLabel(BuildContext context, ThemeMode mode) {
    final AppLocalizations t = AppLocalizations.of(context);
    switch (mode) {
      case ThemeMode.system:
        return t.themeModeAuto;
      case ThemeMode.light:
        return t.themeModeLight;
      case ThemeMode.dark:
        return t.themeModeDark;
    }
  }

  Widget _buildThemeModeItem(BuildContext context) {
    final String currentMode = _themeModeLabel(
      context,
      widget.themeService.themeMode,
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
          _buildSettingsLeadingIcon(context, Icons.brightness_6_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).themeModeTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  currentMode,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _showThemeModeSheet,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(currentMode),
          ),
        ],
      ),
    );
  }

  void _showThemeModeSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final ThemeData theme = Theme.of(sheetContext);
        final ThemeMode currentMode = widget.themeService.themeMode;
        final BorderSide dividerSide = BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.45),
          width: 0.8,
        );

        Widget buildOption({
          required ThemeMode mode,
          required IconData icon,
          required String label,
          required bool showDivider,
        }) {
          final bool selected = currentMode == mode;
          return InkWell(
            onTap: () async {
              await widget.themeService.setThemeMode(mode);
              if (mounted) {
                Navigator.of(sheetContext).pop();
                _settingsSetState(() {});
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
                vertical: AppTheme.spacing3,
              ),
              decoration: BoxDecoration(
                border: showDivider ? Border(bottom: dividerSide) : null,
                color: selected
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
            ),
          );
        }

        return UISheetSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppTheme.spacing3),
              const UISheetHandle(),
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacing4),
                child: Text(
                  AppLocalizations.of(context).themeModeTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              buildOption(
                mode: ThemeMode.system,
                icon: Icons.brightness_auto_outlined,
                label: _themeModeLabel(context, ThemeMode.system),
                showDivider: true,
              ),
              buildOption(
                mode: ThemeMode.light,
                icon: Icons.brightness_high_outlined,
                label: _themeModeLabel(context, ThemeMode.light),
                showDivider: true,
              ),
              buildOption(
                mode: ThemeMode.dark,
                icon: Icons.brightness_4_outlined,
                label: _themeModeLabel(context, ThemeMode.dark),
                showDivider: false,
              ),
              const SizedBox(height: AppTheme.spacing2),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNsfwEntryItem(BuildContext context) {
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
          _buildSettingsLeadingIcon(context, Icons.shield_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).nsfwSettingsSectionTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).blockedDomainListTitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NsfwSettingsPage()),
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionEnter),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyModeItem(BuildContext context) {
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
          _buildSettingsLeadingIcon(context, Icons.privacy_tip_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).privacyModeTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).privacyModeDesc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: _privacyMode,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => _updatePrivacyMode(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoggingToggleItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Row(
                children: [
                  _buildSettingsLeadingIcon(context, Icons.event_note_outlined),
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 72),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).loggingTitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(context).loggingDesc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: -1,
                right: 0,
                child: Transform.scale(
                  scale: 0.9,
                  child: Switch(
                    value: _loggingEnabled,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => _updateLoggingEnabled(v),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing3),
          // 子列表整体：随主开关禁用并灰化
          IgnorePointer(
            ignoring: !_loggingEnabled,
            child: Opacity(
              opacity: _loggingEnabled ? 1.0 : 0.5,
              child: Column(
                children: [
                  // 子项：AI 日志
                  Container(
                    padding: const EdgeInsets.only(
                      left: AppTheme.spacing3,
                      top: AppTheme.spacing3,
                      bottom: AppTheme.spacing3,
                    ),
                    decoration: BoxDecoration(
                      border: Border(bottom: _settingsDividerSide(context)),
                    ),
                    child: Stack(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSettingsLeadingIcon(
                              context,
                              Icons.smart_toy_outlined,
                            ),
                            const SizedBox(width: AppTheme.spacing3),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 72),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      ).loggingAiTitle,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      ).loggingAiDesc,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          top: -1,
                          right: 0,
                          child: Transform.scale(
                            scale: 0.9,
                            child: Switch(
                              value: _aiLoggingEnabled,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) => _updateAiLoggingEnabled(v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 子项：截图日志
                  Container(
                    padding: const EdgeInsets.only(
                      left: AppTheme.spacing3,
                      top: AppTheme.spacing3,
                      bottom: AppTheme.spacing3,
                    ),
                    decoration: BoxDecoration(
                      border: Border(bottom: _settingsDividerSide(context)),
                    ),
                    child: Stack(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSettingsLeadingIcon(
                              context,
                              Icons.image_search_outlined,
                            ),
                            const SizedBox(width: AppTheme.spacing3),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 72),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      ).loggingScreenshotTitle,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      ).loggingScreenshotDesc,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          top: -1,
                          right: 0,
                          child: Transform.scale(
                            scale: 0.9,
                            child: Switch(
                              value: _screenshotLoggingEnabled,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) =>
                                  _updateScreenshotLoggingEnabled(v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamRenderImagesItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildSettingsLeadingIcon(context, Icons.image_outlined),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).streamRenderImagesTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppLocalizations.of(context).streamRenderImagesDesc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: -1,
            right: 0,
            child: Transform.scale(
              scale: 0.9,
              child: Switch(
                value: _renderImagesDuringStreaming,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => _updateRenderImagesDuringStreaming(v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiChatPerfOverlayItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildSettingsLeadingIcon(context, Icons.speed_outlined),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).aiChatPerfOverlayTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppLocalizations.of(context).aiChatPerfOverlayDesc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: -1,
            right: 0,
            child: Transform.scale(
              scale: 0.9,
              child: Switch(
                value: _aiChatPerfOverlayEnabled,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => _updateAiChatPerfOverlayEnabled(v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicEntryLogIconItem(BuildContext context) {
    final bool isZh = AppLocalizations.of(
      context,
    ).localeName.toLowerCase().startsWith('zh');
    final String title = isZh
        ? '动态页每日总结右侧日志图标'
        : 'Dynamic page summary-side log icon';
    final String desc = isZh
        ? '控制动态页中“每日总结”图标右侧日志入口是否显示，默认关闭。'
        : 'Show the log entry next to the daily summary icon on the dynamic page. Off by default.';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: _settingsDividerSide(context)),
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildSettingsLeadingIcon(context, Icons.receipt_long_outlined),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: -1,
            right: 0,
            child: Transform.scale(
              scale: 0.9,
              child: Switch(
                value: _dynamicEntryLogIconEnabled,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => _updateDynamicEntryLogIconEnabled(v),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
