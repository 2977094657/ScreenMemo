part of 'settings_page.dart';

// ========== NSFW 偏好设置 ==========
extension _SettingsNsfwPart on _SettingsPageState {
  // ===== NSFW 域名清单管理 =====
  Future<void> _loadNsfwRules() async {
    try {
      if (mounted) _settingsSetState(() => _nsfwLoading = true);
      await NsfwPreferenceService.instance.ensureRulesLoaded();
      final rows = await NsfwPreferenceService.instance.listRules();
      if (mounted) {
        _settingsSetState(() {
          _nsfwRules = rows;
          _nsfwLoading = false;
        });
      }
    } catch (_) {
      if (mounted) _settingsSetState(() => _nsfwLoading = false);
    }
  }

  Future<void> _previewNsfwDomain() async {
    final input = _nsfwDomainController.text.trim();
    if (input.isEmpty) return;
    try {
      final cnt = await NsfwPreferenceService.instance.previewMatchCount(input);
      if (mounted) {
        _settingsSetState(() => _nsfwPreviewCount = cnt);
        UINotifier.info(
          context,
          AppLocalizations.of(context).previewAffectsCount(cnt),
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).invalidDomainInputError,
        );
      }
    }
  }

  Future<void> _addNsfwDomain() async {
    final l10n = AppLocalizations.of(context);
    final input = _nsfwDomainController.text.trim();
    if (input.isEmpty) return;
    // 先预览，避免误屏蔽
    int preview = 0;
    try {
      preview = await NsfwPreferenceService.instance.previewMatchCount(input);
    } catch (e) {
      UINotifier.error(context, l10n.invalidDomainInputError);
      return;
    }
    final ok =
        await showUIDialog<bool>(
          context: context,
          title: l10n.confirmAddRuleTitle,
          message: l10n.confirmAddRuleMessage(input),
          barrierDismissible: false,
          actions: [
            UIDialogAction<bool>(text: l10n.dialogCancel, result: false),
            UIDialogAction<bool>(
              text: l10n.dialogOk,
              style: UIDialogActionStyle.primary,
              result: true,
            ),
          ],
        ) ??
        false;
    if (!ok) return;
    final saved = await NsfwPreferenceService.instance.addRule(input);
    if (!mounted) return;
    if (saved) {
      _nsfwDomainController.clear();
      _nsfwPreviewCount = null;
      await _loadNsfwRules();
      UINotifier.success(context, l10n.ruleAddedToast);
    } else {
      UINotifier.error(context, l10n.operationFailed);
    }
  }

  Future<void> _removeNsfwDomain(String pattern) async {
    final l10n = AppLocalizations.of(context);
    final ok = await NsfwPreferenceService.instance.removeRule(pattern);
    if (!mounted) return;
    if (ok) {
      await _loadNsfwRules();
      UINotifier.success(context, l10n.ruleRemovedToast);
    } else {
      UINotifier.error(context, l10n.operationFailed);
    }
  }

  Future<void> _clearAllNsfwRules() async {
    final l10n = AppLocalizations.of(context);
    final ok =
        await showUIDialog<bool>(
          context: context,
          title: l10n.clearAllRulesConfirmTitle,
          message: l10n.clearAllRulesMessage,
          actions: const [
            UIDialogAction<bool>(text: '取消', result: false),
            UIDialogAction<bool>(
              text: '清空',
              style: UIDialogActionStyle.destructive,
              result: true,
            ),
          ],
          barrierDismissible: false,
        ) ??
        false;
    if (!ok) return;
    final n = await NsfwPreferenceService.instance.clearRules();
    if (!mounted) return;
    if (n >= 0) {
      await _loadNsfwRules();
      UINotifier.success(context, l10n.actionClear);
    } else {
      UINotifier.error(context, l10n.operationFailed);
    }
  }

  Widget _buildNsfwDomainManager(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(
                      color: _settingsDividerSide(context).color,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _nsfwDomainController,
                    decoration: InputDecoration(
                      hintText: l10n.addDomainPlaceholder,
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacing2),
              TextButton(
                onPressed: _previewNsfwDomain,
                child: Text(l10n.previewAction),
              ),
              const SizedBox(width: AppTheme.spacing1),
              ElevatedButton(
                onPressed: _addNsfwDomain,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                child: Text(l10n.addRuleAction),
              ),
            ],
          ),
          if (_nsfwPreviewCount != null) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              l10n.previewAffectsCount(_nsfwPreviewCount!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppTheme.spacing3),
          Row(
            children: [
              Text(
                l10n.blockedDomainListTitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: _nsfwRules.isEmpty ? null : _clearAllNsfwRules,
                child: Text(l10n.clearAllRules),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing1),
          if (_nsfwLoading)
            const SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_nsfwRules.isEmpty)
            Text(
              AppLocalizations.of(context).none,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _nsfwRules.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Theme.of(context).dividerColor),
              itemBuilder: (context, index) {
                final r = _nsfwRules[index];
                final pattern = (r['pattern'] as String?) ?? '';
                final isWildcard = ((r['is_wildcard'] as int?) ?? 0) == 1;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Expanded(child: Text(pattern)),
                      if (isWildcard)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSm,
                            ),
                          ),
                          child: Text(
                            '*.',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.removeAction,
                    onPressed: () => _removeNsfwDomain(pattern),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
