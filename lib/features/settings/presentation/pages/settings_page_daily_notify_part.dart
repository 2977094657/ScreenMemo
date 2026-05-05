part of 'settings_page.dart';

// ========== 扩展：每日总结提醒设置（提示时间 + 测试按钮） ==========
extension _DailySummaryNotifyExt on _SettingsPageState {
  Future<void> _loadDailyNotifySettings() async {
    try {
      final bool enabled = await UserSettingsService.instance.getBool(
        UserSettingKeys.dailyNotifyEnabled,
        defaultValue: true,
        legacyPrefKeys: const <String>['daily_notify_enabled'],
      );
      final int hour = await UserSettingsService.instance.getInt(
        UserSettingKeys.dailyNotifyHour,
        defaultValue: 22,
        legacyPrefKeys: const <String>['daily_notify_hour'],
      );
      final int minute = await UserSettingsService.instance.getInt(
        UserSettingKeys.dailyNotifyMinute,
        defaultValue: 0,
        legacyPrefKeys: const <String>['daily_notify_minute'],
      );
      if (mounted) {
        _settingsSetState(() {
          _dailyNotifyEnabled = enabled;
          _dailyNotifyHour = hour.clamp(0, 23);
          _dailyNotifyMinute = minute.clamp(0, 59);
        });
      }
      await FlutterLogger.nativeInfo(
        'DailySummaryUI',
        '加载设置：启用=${_dailyNotifyEnabled} 时间=${_two(_dailyNotifyHour)}:${_two(_dailyNotifyMinute)}',
      );
      final ok = await DailySummaryService.instance.scheduleDailyNotification(
        hour: _dailyNotifyHour,
        minute: _dailyNotifyMinute,
        enabled: _dailyNotifyEnabled,
      );
      // 启动一次"自动预生成"调度
      await DailySummaryService.instance.refreshAutoRefreshSchedule();
      await FlutterLogger.nativeInfo('DailySummaryUI', '加载后恢复调度 结果=$ok');
    } catch (e) {
      await FlutterLogger.nativeWarn('DailySummaryUI', '加载设置失败：$e');
    }
  }

  Future<void> _saveDailyNotifySettings({
    bool? enabled,
    int? hour,
    int? minute,
    bool toast = true,
  }) async {
    try {
      final newEnabled = enabled ?? _dailyNotifyEnabled;
      final newHour = (hour ?? _dailyNotifyHour).clamp(0, 23);
      final newMinute = (minute ?? _dailyNotifyMinute).clamp(0, 59);

      await UserSettingsService.instance.setBool(
        UserSettingKeys.dailyNotifyEnabled,
        newEnabled,
        legacyPrefKeys: const <String>['daily_notify_enabled'],
      );
      await UserSettingsService.instance.setInt(
        UserSettingKeys.dailyNotifyHour,
        newHour,
        legacyPrefKeys: const <String>['daily_notify_hour'],
      );
      await UserSettingsService.instance.setInt(
        UserSettingKeys.dailyNotifyMinute,
        newMinute,
        legacyPrefKeys: const <String>['daily_notify_minute'],
      );

      if (mounted) {
        _settingsSetState(() {
          _dailyNotifyEnabled = newEnabled;
          _dailyNotifyHour = newHour;
          _dailyNotifyMinute = newMinute;
        });
      }

      final ok = await DailySummaryService.instance.scheduleDailyNotification(
        hour: newHour,
        minute: newMinute,
        enabled: newEnabled,
      );
      // 刷新"预生成"定时器，使得在提醒前1分钟自动刷新当日总结
      await DailySummaryService.instance.refreshAutoRefreshSchedule();
      if (toast && mounted) {
        if (ok) {
          UINotifier.success(
            context,
            newEnabled
                ? AppLocalizations.of(
                    context,
                  ).reminderScheduleSuccess(_two(newHour), _two(newMinute))
                : AppLocalizations.of(context).reminderDisabledSuccess,
          );
        } else {
          UINotifier.warning(
            context,
            AppLocalizations.of(context).reminderScheduleFailed,
          );
        }
      }
    } catch (e) {
      if (mounted)
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveReminderSettingsFailed(e.toString()),
        );
    }
  }

  Future<void> _pickDailyNotifyTime() async {
    final int initialHour = _dailyNotifyHour.clamp(0, 23);
    final int initialMinute = _dailyNotifyMinute.clamp(0, 59);

    final FixedExtentScrollController hourController =
        FixedExtentScrollController(initialItem: initialHour);
    final FixedExtentScrollController minuteController =
        FixedExtentScrollController(initialItem: initialMinute);

    int tempHour = initialHour;
    int tempMinute = initialMinute;

    TimeOfDay? result;
    try {
      result = await showModalBottomSheet<TimeOfDay>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final theme = Theme.of(context);
          final l10n = AppLocalizations.of(context);

          return UISheetSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppTheme.spacing3),
                const UISheetHandle(),
                const SizedBox(height: AppTheme.spacing2),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                  child: Text(
                    l10n.setReminderTimeTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  height: 240,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              l10n.hourLabel,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Expanded(
                              child: CupertinoPicker(
                                scrollController: hourController,
                                itemExtent: 36,
                                magnification: 1.12,
                                squeeze: 1.05,
                                useMagnifier: true,
                                onSelectedItemChanged: (int index) {
                                  tempHour = index;
                                },
                                children: List<Widget>.generate(
                                  24,
                                  (int index) => Center(
                                    child: Text(
                                      _two(index),
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              l10n.minuteLabel,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Expanded(
                              child: CupertinoPicker(
                                scrollController: minuteController,
                                itemExtent: 36,
                                magnification: 1.12,
                                squeeze: 1.05,
                                useMagnifier: true,
                                onSelectedItemChanged: (int index) {
                                  tempMinute = index;
                                },
                                children: List<Widget>.generate(
                                  60,
                                  (int index) => Center(
                                    child: Text(
                                      _two(index),
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacing4,
                    AppTheme.spacing3,
                    AppTheme.spacing4,
                    AppTheme.spacing4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMd,
                              ),
                            ),
                          ),
                          child: Text(l10n.dialogCancel),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacing3),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(ctx).pop(
                              TimeOfDay(hour: tempHour, minute: tempMinute),
                            );
                          },
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMd,
                              ),
                            ),
                          ),
                          child: Text(l10n.dialogDone),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      hourController.dispose();
      minuteController.dispose();
    }

    if (result != null) {
      await _saveDailyNotifySettings(hour: result.hour, minute: result.minute);
    }
  }

  Widget _buildDailyNotifyItem(BuildContext context) {
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
          _buildSettingsLeadingIcon(context, Icons.schedule_outlined),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).dailyReminderTimeTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                IgnorePointer(
                  ignoring: !_dailyNotifyEnabled,
                  child: Opacity(
                    opacity: _dailyNotifyEnabled ? 1.0 : 0.5,
                    child: Row(
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
                        GestureDetector(
                          onTap: _dailyNotifyEnabled
                              ? _pickDailyNotifyTime
                              : null,
                          child: Text(
                            '${_two(_dailyNotifyHour)}:${_two(_dailyNotifyMinute)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  decoration: _dailyNotifyEnabled
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
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
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: _dailyNotifyEnabled,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) async {
                await _saveDailyNotifySettings(enabled: v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyNotifyTestItem(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3 - 2,
      ),
      child: Row(
        children: [
          _buildSettingsLeadingIcon(
            context,
            Icons.notifications_active_outlined,
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).testNotificationTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).testNotificationDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: () async {
              // 先强制重新生成当日总结，确保通知内容新鲜
              final key = _todayKey();
              try {
                await DailySummaryService.instance.getOrGenerate(
                  key,
                  force: true,
                );
              } catch (_) {}
              final ok = await DailySummaryService.instance
                  .triggerNotificationNow(key);
              if (!mounted) return;
              if (ok) {
                UINotifier.success(
                  context,
                  AppLocalizations.of(context).dailyNotifyTriggered,
                );
              } else {
                UINotifier.warning(
                  context,
                  AppLocalizations.of(context).dailyNotifyTriggerFailed,
                );
              }
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
            child: Text(AppLocalizations.of(context).actionTrigger),
          ),
        ],
      ),
    );
  }

  // 打开"每日总结提醒"渠道设置（开启横幅/悬浮通知等）
  Future<void> _openDailyChannelSettings() async {
    try {
      await FlutterLogger.nativeInfo('DailySummaryUI', '打开通知渠道设置');
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      await platform.invokeMethod('openDailySummaryNotificationSettings');
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).openChannelSettingsFailed(e.toString()),
        );
      }
    }
  }

  // 打开"应用通知"总设置（可选）
  Future<void> _openAppNotificationSettings() async {
    try {
      await FlutterLogger.nativeInfo('DailySummaryUI', '打开应用通知设置');
      const platform = MethodChannel('com.fqyw/screen_memo/accessibility');
      // 兼容：统一使用正确通道名
    } catch (_) {}
    try {
      const platform = MethodChannel('com.fqyw.screen_memo/accessibility');
      await platform.invokeMethod('openAppNotificationSettings');
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(
            context,
          ).openAppNotificationSettingsFailed(e.toString()),
        );
      }
    }
  }

  // 行项：开启横幅/悬浮通知
  Widget _buildDailyNotifyBannerItem(BuildContext context) {
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
          _buildSettingsLeadingIcon(
            context,
            Icons.notification_important_outlined,
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).enableBannerNotificationTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).enableBannerNotificationDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          TextButton(
            onPressed: _openDailyChannelSettings,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing1 - 1,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(AppLocalizations.of(context).actionOpen),
          ),
        ],
      ),
    );
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${_two(now.month)}-${_two(now.day)}';
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}
