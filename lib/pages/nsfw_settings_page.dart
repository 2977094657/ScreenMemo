import 'package:flutter/material.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import '../services/nsfw_preference_service.dart';

/// NSFW 设置页面：在此管理域名清单（CRUD）
class NsfwSettingsPage extends StatefulWidget {
  const NsfwSettingsPage({super.key});

  @override
  State<NsfwSettingsPage> createState() => _NsfwSettingsPageState();
}

class _NsfwSettingsPageState extends State<NsfwSettingsPage> {
  // 状态
  final TextEditingController _domainController = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>> _rules = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  // ========== 数据加载与操作 ==========

  Future<void> _loadRules() async {
    try {
      if (mounted) setState(() => _loading = true);
      await NsfwPreferenceService.instance.ensureRulesLoaded();
      final rows = await NsfwPreferenceService.instance.listRules();
      if (mounted) {
        setState(() {
          _rules = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addDomain() async {
    final l10n = AppLocalizations.of(context);
    final input = _domainController.text.trim();
    if (input.isEmpty) return;

    // 直接添加
    final saved = await NsfwPreferenceService.instance.addRule(input);
    if (!mounted) return;
    if (saved) {
      _domainController.clear();
      await _loadRules();
      UINotifier.success(context, l10n.ruleAddedToast);
    } else {
      UINotifier.error(context, l10n.operationFailed);
    }
  }

  Future<void> _removeDomain(String pattern) async {
    final l10n = AppLocalizations.of(context);
    final ok = await NsfwPreferenceService.instance.removeRule(pattern);
    if (!mounted) return;
    if (ok) {
      await _loadRules();
      UINotifier.success(context, l10n.ruleRemovedToast);
    } else {
      UINotifier.error(context, l10n.operationFailed);
    }
  }

  Future<void> _clearAllRules() async {
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
      await _loadRules();
      UINotifier.success(context, l10n.actionClear);
    } else {
      UINotifier.error(context, l10n.operationFailed);
    }
  }

  // ========== UI ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).nsfwSettingsSectionTitle),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing4),
        child: _buildDomainManager(context),
      ),
    );
  }

  Widget _buildDomainManager(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 输入 + 添加
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _domainController,
                decoration: InputDecoration(
                  hintText: l10n.addDomainPlaceholder,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacing2),
            ElevatedButton(
              onPressed: _addDomain,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              child: Text(l10n.addRuleAction),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing3),
        Divider(
          height: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        const SizedBox(height: AppTheme.spacing3),
        // 标题 + 清空
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
              onPressed: _rules.isEmpty ? null : _clearAllRules,
              child: Text(l10n.clearAllRules),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing1),
        // 列表
        if (_loading)
          const SizedBox(
            height: 28,
            width: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (_rules.isEmpty)
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
            itemCount: _rules.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Theme.of(context).dividerColor),
            itemBuilder: (context, index) {
              final r = _rules[index];
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
                  onPressed: () => _removeDomain(pattern),
                ),
              );
            },
          ),
      ],
    );
  }
}
