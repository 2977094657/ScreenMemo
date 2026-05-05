part of 'home_page.dart';

extension _HomePageLanguagePart on _HomePageState {
  void _toggleSelect(String packageName) {
    _homeSetState(() {
      if (_selectedPackages.contains(packageName)) {
        _selectedPackages.remove(packageName);
        if (_selectedPackages.isEmpty) _selectionMode = false;
      } else {
        _selectedPackages.add(packageName);
      }
    });
  }

  Future<void> _removeSelectedApps() async {
    final count = _selectedPackages.length;
    final confirmed = await showUIDialog<bool>(
      context: context,
      title: AppLocalizations.of(context).removeMonitoring,
      message: AppLocalizations.of(context).removeMonitoringMessage,
      actions: [
        UIDialogAction<bool>(
          text: AppLocalizations.of(context).dialogCancel,
          result: false,
        ),
        UIDialogAction<bool>(
          text: AppLocalizations.of(context).remove,
          style: UIDialogActionStyle.destructive,
          result: true,
        ),
      ],
      barrierDismissible: false,
    );
    if (confirmed != true) return;

    final remaining = _savedSelectedApps
        .where((a) => !_selectedPackages.contains(a.packageName))
        .toList();
    await _appService.saveSelectedApps(remaining);
    if (!mounted) return;
    _homeSetState(() {
      _savedSelectedApps = remaining;
      _sortApps();
      _selectionMode = false;
      _selectedPackages.clear();
    });
    UINotifier.info(
      context,
      AppLocalizations.of(context).removedMonitoringToast(count),
    );
  }

  /// 显示语言选择底部弹窗
  void _showLanguageBottomSheet() {
    final t = AppLocalizations.of(context);
    final currentOption = LocaleService.instance.option;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => UISheetSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppTheme.spacing3),
            const UISheetHandle(),
            // 标题
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacing4),
              child: Text(
                t.languageSettingTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            // 语言选项列表
            _buildLanguageOption(
              context: context,
              title: t.languageSystem,
              value: 'system',
              currentValue: currentOption,
              onTap: () async {
                await _handleLanguageSelection(
                  sheetContext: context,
                  option: 'system',
                  toastLanguageName: t.languageSystem,
                );
              },
            ),
            _buildLanguageOption(
              context: context,
              title: '中文',
              value: 'zh',
              currentValue: currentOption,
              onTap: () async {
                await _handleLanguageSelection(
                  sheetContext: context,
                  option: 'zh',
                  toastLocale: const Locale('zh'),
                  toastLanguageName: '中文',
                );
              },
            ),
            _buildLanguageOption(
              context: context,
              title: 'English',
              value: 'en',
              currentValue: currentOption,
              onTap: () async {
                await _handleLanguageSelection(
                  sheetContext: context,
                  option: 'en',
                  toastLocale: const Locale('en'),
                  toastLanguageName: 'English',
                );
              },
            ),
            _buildLanguageOption(
              context: context,
              title: '日本語',
              value: 'ja',
              currentValue: currentOption,
              onTap: () async {
                await _handleLanguageSelection(
                  sheetContext: context,
                  option: 'ja',
                  toastLocale: const Locale('ja'),
                  toastLanguageName: '日本語',
                );
              },
            ),
            _buildLanguageOption(
              context: context,
              title: '한국어',
              value: 'ko',
              currentValue: currentOption,
              onTap: () async {
                await _handleLanguageSelection(
                  sheetContext: context,
                  option: 'ko',
                  toastLocale: const Locale('ko'),
                  toastLanguageName: '한국어',
                );
              },
            ),
            const SizedBox(height: AppTheme.spacing4),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLanguageSelection({
    required BuildContext sheetContext,
    required String option,
    Locale? toastLocale,
    required String toastLanguageName,
  }) async {
    await LocaleService.instance.setOption(option);
    if (!mounted) return;
    if (!sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    final localization = await _loadToastLocalization(toastLocale);
    if (!mounted || localization == null) return;
    UINotifier.success(
      context,
      localization.languageChangedToast(toastLanguageName),
    );
  }

  Future<AppLocalizations?> _loadToastLocalization(Locale? locale) async {
    if (locale == null) {
      return AppLocalizations.of(context);
    }
    try {
      return await AppLocalizations.delegate.load(locale);
    } catch (_) {
      return AppLocalizations.of(context);
    }
  }

  /// 构建语言选项行
  Widget _buildLanguageOption({
    required BuildContext context,
    required String title,
    required String value,
    required String currentValue,
    required VoidCallback onTap,
  }) {
    final isSelected = value == currentValue;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing4,
          vertical: AppTheme.spacing3,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
