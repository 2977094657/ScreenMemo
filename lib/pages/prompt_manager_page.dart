import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import '../services/ai_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/screenshot_style_tab_bar.dart';
import '../widgets/ui_components.dart';

class PromptManagerPage extends StatefulWidget {
  const PromptManagerPage({super.key});

  @override
  State<PromptManagerPage> createState() => _PromptManagerPageState();
}

class _PromptManagerPageState extends State<PromptManagerPage>
    with SingleTickerProviderStateMixin {
  static const int _promptAddonMaxChars = 500;

  final AISettingsService _settings = AISettingsService.instance;

  late final TabController _tabController;
  int _lastTabIndex = 0;

  // 当前存储的补充说明（null/空 = 使用默认模板，不追加说明）
  String? _promptSegment;
  String? _promptMerge;
  String? _promptDaily;
  String? _promptMorning;

  final TextEditingController _segCtrl = TextEditingController();
  final TextEditingController _mergeCtrl = TextEditingController();
  final TextEditingController _dailyCtrl = TextEditingController();
  final TextEditingController _morningCtrl = TextEditingController();

  bool _editingSeg = false;
  bool _editingMerge = false;
  bool _editingDaily = false;
  bool _editingMorning = false;

  bool _savingSeg = false;
  bool _savingMerge = false;
  bool _savingDaily = false;
  bool _savingMorning = false;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(_handleTabChanged);
    _load();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _segCtrl.dispose();
    _mergeCtrl.dispose();
    _dailyCtrl.dispose();
    _morningCtrl.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted) return;
    final int index = _tabController.index;
    if (index == _lastTabIndex) return;
    setState(() => _lastTabIndex = index);
  }

  Future<void> _load() async {
    try {
      final seg = await _settings.getPromptSegment();
      final mer = await _settings.getPromptMerge();
      final day = await _settings.getPromptDaily();
      final morning = await _settings.getPromptMorning();
      if (!mounted) return;
      setState(() {
        _promptSegment = seg;
        _promptMerge = mer;
        _promptDaily = day;
        _promptMorning = morning;

        _segCtrl.text = seg?.trim() ?? '';
        _mergeCtrl.text = mer?.trim() ?? '';
        _dailyCtrl.text = day?.trim() ?? '';
        _morningCtrl.text = morning?.trim() ?? '';

        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _currentTabEditing {
    switch (_tabController.index) {
      case 0:
        return _editingSeg;
      case 1:
        return _editingMerge;
      case 2:
        return _editingDaily;
      case 3:
        return _editingMorning;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final t = AppLocalizations.of(context);
    final tabs = <Tab>[
      Tab(text: t.normalEventPromptLabel),
      Tab(text: t.mergeEventPromptLabel),
      Tab(text: t.dailySummaryPromptLabel),
      Tab(text: t.morningInsightsPromptLabel),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(t.promptManagerTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.spacing4),
            child: Center(child: _buildModeBadge(t)),
          ),
        ],
        bottom: ScreenshotStyleTabBar(
          controller: _tabController,
          tabs: tabs,
          height: 36,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPromptTab(
            infoText: t.promptAddonGeneralInfo,
            suggestion: t.promptAddonSuggestionSegment,
            currentAddon: _promptSegment ?? '',
            editing: _editingSeg,
            controller: _segCtrl,
            saving: _savingSeg,
            onEdit: () => setState(() => _editingSeg = true),
            onCancel: _cancelSeg,
            onSave: _saveSeg,
            onReset: _resetSeg,
          ),
          _buildPromptTab(
            infoText: t.promptAddonGeneralInfo,
            suggestion: t.promptAddonSuggestionMerge,
            currentAddon: _promptMerge ?? '',
            editing: _editingMerge,
            controller: _mergeCtrl,
            saving: _savingMerge,
            onEdit: () => setState(() => _editingMerge = true),
            onCancel: _cancelMerge,
            onSave: _saveMerge,
            onReset: _resetMerge,
          ),
          _buildPromptTab(
            infoText: t.promptAddonGeneralInfo,
            suggestion: t.promptAddonSuggestionDaily,
            currentAddon: _promptDaily ?? '',
            editing: _editingDaily,
            controller: _dailyCtrl,
            saving: _savingDaily,
            onEdit: () => setState(() => _editingDaily = true),
            onCancel: _cancelDaily,
            onSave: _saveDaily,
            onReset: _resetDaily,
          ),
          _buildPromptTab(
            infoText: t.promptAddonGeneralInfo,
            suggestion: t.promptAddonSuggestionMorning,
            currentAddon: _promptMorning ?? '',
            editing: _editingMorning,
            controller: _morningCtrl,
            saving: _savingMorning,
            onEdit: () => setState(() => _editingMorning = true),
            onCancel: _cancelMorning,
            onSave: _saveMorning,
            onReset: _resetMorning,
          ),
        ],
      ),
    );
  }

  Widget _buildModeBadge(AppLocalizations t) {
    return UIBadge(
      text: _currentTabEditing
          ? t.promptManagerEditingBadge
          : t.promptManagerReadOnlyBadge,
      variant: _currentTabEditing
          ? UIBadgeVariant.primary
          : UIBadgeVariant.secondary,
    );
  }

  Widget _buildPromptTab({
    required String infoText,
    required String suggestion,
    required String currentAddon,
    required bool editing,
    required TextEditingController controller,
    required bool saving,
    required VoidCallback onEdit,
    required VoidCallback onCancel,
    required Future<void> Function() onSave,
    required Future<void> Function() onReset,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final currentLength = editing
            ? value.text.trim().length
            : currentAddon.trim().length;
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacing4,
                  AppTheme.spacing4,
                  AppTheme.spacing4,
                  AppTheme.spacing6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildInfoCard(infoText),
                    const SizedBox(height: AppTheme.spacing5),
                    _buildAddonHeader(editing: editing, count: currentLength),
                    const SizedBox(height: AppTheme.spacing2),
                    if (editing)
                      _buildEditorCard(
                        controller: controller,
                        suggestion: suggestion,
                        saving: saving,
                        isOverLimit: currentLength > _promptAddonMaxChars,
                        onReset: onReset,
                      )
                    else
                      _buildReadOnlyCard(currentAddon),
                  ],
                ),
              ),
            ),
            _buildBottomActions(
              editing: editing,
              saving: saving,
              onEdit: onEdit,
              onCancel: onCancel,
              onSave: onSave,
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoCard(String infoText) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.72), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppTheme.spacing3),
          Expanded(
            child: Text(
              infoText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddonHeader({required bool editing, required int count}) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bool overLimit = count > _promptAddonMaxChars;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          t.promptAddonSectionTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: AppTheme.spacing2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            t.promptAddonOptionalLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        Text(
          editing
              ? t.promptAddonCharCountLimit(count, _promptAddonMaxChars)
              : t.promptAddonCharCount(count),
          style: theme.textTheme.bodySmall?.copyWith(
            color: overLimit ? cs.error : cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyCard(String currentAddon) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final display = currentAddon.trim();
    final bool hasAddon = display.isNotEmpty;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 160),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.72), width: 1),
      ),
      child: SelectableText(
        hasAddon
            ? display
            : AppLocalizations.of(context).promptAddonEmptyPlaceholder,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: hasAddon ? cs.onSurface : cs.onSurfaceVariant,
          height: 1.55,
        ),
      ),
    );
  }

  Widget _buildEditorCard({
    required TextEditingController controller,
    required String suggestion,
    required bool saving,
    required bool isOverLimit,
    required Future<void> Function() onReset,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: isOverLimit ? cs.error : cs.outline.withValues(alpha: 0.72),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            enabled: !saving,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            minLines: 12,
            maxLines: null,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: suggestion,
              hintMaxLines: 10,
              contentPadding: const EdgeInsets.all(AppTheme.spacing4),
            ),
          ),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.56)),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing3,
              vertical: AppTheme.spacing2,
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: saving ? null : onReset,
                  icon: const Icon(Icons.restore_rounded, size: 16),
                  label: Text(t.resetToDefault),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing2,
                      vertical: AppTheme.spacing1,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: Size.zero,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.edit_note_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: AppTheme.spacing1),
                Text(
                  t.promptManagerSupportsPlainText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions({
    required bool editing,
    required bool saving,
    required VoidCallback onEdit,
    required VoidCallback onCancel,
    required Future<void> Function() onSave,
  }) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacing4,
          AppTheme.spacing3,
          AppTheme.spacing4,
          AppTheme.spacing4,
        ),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outline, width: 1)),
        ),
        child: editing
            ? Row(
                children: [
                  Expanded(
                    child: UIButton(
                      text: t.dialogCancel,
                      onPressed: saving ? null : onCancel,
                      variant: UIButtonVariant.outline,
                      fullWidth: true,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing3),
                  Expanded(
                    child: UIButton(
                      text: saving ? t.savingLabel : t.actionSave,
                      onPressed: saving ? null : () => unawaited(onSave()),
                      loading: saving,
                      fullWidth: true,
                    ),
                  ),
                ],
              )
            : UIButton(
                text: t.actionEdit,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                fullWidth: true,
              ),
      ),
    );
  }

  bool _validatePromptLength(TextEditingController controller) {
    final length = controller.text.trim().length;
    if (length <= _promptAddonMaxChars) return true;
    UINotifier.error(
      context,
      AppLocalizations.of(
        context,
      ).promptAddonTooLongError(_promptAddonMaxChars),
    );
    return false;
  }

  void _cancelSeg() {
    setState(() {
      _segCtrl.text = _promptSegment?.trim() ?? '';
      _editingSeg = false;
    });
  }

  void _cancelMerge() {
    setState(() {
      _mergeCtrl.text = _promptMerge?.trim() ?? '';
      _editingMerge = false;
    });
  }

  void _cancelDaily() {
    setState(() {
      _dailyCtrl.text = _promptDaily?.trim() ?? '';
      _editingDaily = false;
    });
  }

  void _cancelMorning() {
    setState(() {
      _morningCtrl.text = _promptMorning?.trim() ?? '';
      _editingMorning = false;
    });
  }

  Future<void> _saveSeg() async {
    if (_savingSeg || !_validatePromptLength(_segCtrl)) return;
    setState(() => _savingSeg = true);
    try {
      final text = _segCtrl.text.trim();
      final normalized = text.isEmpty ? null : text;
      await _settings.setPromptSegment(normalized);
      if (mounted) {
        setState(() {
          _promptSegment = normalized;
          _segCtrl.text = normalized ?? '';
          _editingSeg = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).savedNormalPromptToast,
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSeg = false);
    }
  }

  Future<void> _resetSeg() async {
    if (_savingSeg) return;
    setState(() => _savingSeg = true);
    try {
      await _settings.setPromptSegment(null);
      if (mounted) {
        setState(() {
          _promptSegment = null;
          _segCtrl.text = '';
          _editingSeg = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).resetToDefaultPromptToast,
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).resetFailedWithError(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSeg = false);
    }
  }

  Future<void> _saveMerge() async {
    if (_savingMerge || !_validatePromptLength(_mergeCtrl)) return;
    setState(() => _savingMerge = true);
    try {
      final text = _mergeCtrl.text.trim();
      final normalized = text.isEmpty ? null : text;
      await _settings.setPromptMerge(normalized);
      if (mounted) {
        setState(() {
          _promptMerge = normalized;
          _mergeCtrl.text = normalized ?? '';
          _editingMerge = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).savedMergePromptToast,
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _savingMerge = false);
    }
  }

  Future<void> _resetMerge() async {
    if (_savingMerge) return;
    setState(() => _savingMerge = true);
    try {
      await _settings.setPromptMerge(null);
      if (mounted) {
        setState(() {
          _promptMerge = null;
          _mergeCtrl.text = '';
          _editingMerge = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).resetToDefaultPromptToast,
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).resetFailedWithError(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _savingMerge = false);
    }
  }

  Future<void> _saveDaily() async {
    if (_savingDaily || !_validatePromptLength(_dailyCtrl)) return;
    setState(() => _savingDaily = true);
    try {
      final text = _dailyCtrl.text.trim();
      final normalized = text.isEmpty ? null : text;
      await _settings.setPromptDaily(normalized);
      if (mounted) {
        setState(() {
          _promptDaily = normalized;
          _dailyCtrl.text = normalized ?? '';
          _editingDaily = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).savedDailyPromptToast,
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _savingDaily = false);
    }
  }

  Future<void> _resetDaily() async {
    if (_savingDaily) return;
    setState(() => _savingDaily = true);
    try {
      await _settings.setPromptDaily(null);
      if (mounted) {
        setState(() {
          _promptDaily = null;
          _dailyCtrl.text = '';
          _editingDaily = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).resetToDefaultPromptToast,
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).resetFailedWithError(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _savingDaily = false);
    }
  }

  Future<void> _saveMorning() async {
    if (_savingMorning || !_validatePromptLength(_morningCtrl)) return;
    setState(() => _savingMorning = true);
    try {
      final text = _morningCtrl.text.trim();
      final normalized = text.isEmpty ? null : text;
      await _settings.setPromptMorning(normalized);
      if (mounted) {
        setState(() {
          _promptMorning = normalized;
          _morningCtrl.text = normalized ?? '';
          _editingMorning = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).savedMorningPromptToast,
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).saveFailedError(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _savingMorning = false);
    }
  }

  Future<void> _resetMorning() async {
    if (_savingMorning) return;
    setState(() => _savingMorning = true);
    try {
      await _settings.setPromptMorning(null);
      if (mounted) {
        setState(() {
          _promptMorning = null;
          _morningCtrl.text = '';
          _editingMorning = false;
        });
        UINotifier.success(
          context,
          AppLocalizations.of(context).resetToDefaultPromptToast,
        );
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).resetFailedWithError(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _savingMorning = false);
    }
  }
}
