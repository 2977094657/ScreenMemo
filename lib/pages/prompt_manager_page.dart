import 'package:flutter/material.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../services/ai_settings_service.dart';
import '../widgets/screenshot_style_tab_bar.dart';
import '../widgets/ui_components.dart';
import '../theme/app_theme.dart';

class PromptManagerPage extends StatefulWidget {
  const PromptManagerPage({super.key});

  @override
  State<PromptManagerPage> createState() => _PromptManagerPageState();
}

class _PromptManagerPageState extends State<PromptManagerPage> with SingleTickerProviderStateMixin {
  final AISettingsService _settings = AISettingsService.instance;
  // 当前存储的自定义提示词（null/空 = 使用默认）
  String? _promptSegment;
  String? _promptMerge;
  String? _promptDaily;
  String? _promptWeekly;
  String? _promptMorning;

  // 编辑状态与控制器
  final TextEditingController _segCtrl = TextEditingController();
  final TextEditingController _mergeCtrl = TextEditingController();
  final TextEditingController _dailyCtrl = TextEditingController();
  final TextEditingController _weeklyCtrl = TextEditingController();
  final TextEditingController _morningCtrl = TextEditingController();
  bool _editingSeg = false;
  bool _editingMerge = false;
  bool _editingDaily = false;
  bool _editingWeekly = false;
  bool _editingMorning = false;
  bool _savingSeg = false;
  bool _savingMerge = false;
  bool _savingDaily = false;
  bool _savingWeekly = false;
  bool _savingMorning = false;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _segCtrl.dispose();
    _mergeCtrl.dispose();
    _dailyCtrl.dispose();
    _weeklyCtrl.dispose();
    _morningCtrl.dispose();
   super.dispose();
  }

  Future<void> _load() async {
    try {
      final seg = await _settings.getPromptSegment();
      final mer = await _settings.getPromptMerge();
      final day = await _settings.getPromptDaily();
      final weekly = await _settings.getPromptWeekly();
      final morning = await _settings.getPromptMorning();
      if (!mounted) return;
      setState(() {
        _promptSegment = seg;
        _promptMerge = mer;
        _promptDaily = day;
        _promptWeekly = weekly;
        _promptMorning = morning;

        _segCtrl.text = seg?.trim() ?? '';
        _mergeCtrl.text = mer?.trim() ?? '';
        _dailyCtrl.text = day?.trim() ?? '';
        _weeklyCtrl.text = weekly?.trim() ?? '';
        _morningCtrl.text = morning?.trim() ?? '';

        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final t = AppLocalizations.of(context);
    final tabs = <Tab>[
      Tab(text: t.normalEventPromptLabel),
      Tab(text: t.mergeEventPromptLabel),
      Tab(text: t.dailySummaryPromptLabel),
      Tab(text: t.weeklySummaryPromptLabel),
      Tab(text: t.morningInsightsPromptLabel),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.promptManagerTitle),
          bottom: ScreenshotStyleTabBar(tabs: tabs),
        ),
        body: TabBarView(
          children: [
            _buildPromptTab(
              label: t.normalEventPromptLabel,
              infoText: t.promptAddonGeneralInfo,
              suggestion: t.promptAddonSuggestionSegment,
              currentAddon: _promptSegment ?? '',
              editing: _editingSeg,
              controller: _segCtrl,
              onEditToggle: () => setState(() => _editingSeg = !_editingSeg),
              onSave: _saveSeg,
              onReset: _resetSeg,
              saving: _savingSeg,
            ),
            _buildPromptTab(
              label: t.mergeEventPromptLabel,
              infoText: t.promptAddonGeneralInfo,
              suggestion: t.promptAddonSuggestionMerge,
              currentAddon: _promptMerge ?? '',
              editing: _editingMerge,
              controller: _mergeCtrl,
              onEditToggle: () => setState(() => _editingMerge = !_editingMerge),
              onSave: _saveMerge,
              onReset: _resetMerge,
              saving: _savingMerge,
            ),
            _buildPromptTab(
              label: t.dailySummaryPromptLabel,
              infoText: t.promptAddonGeneralInfo,
              suggestion: t.promptAddonSuggestionDaily,
              currentAddon: _promptDaily ?? '',
              editing: _editingDaily,
              controller: _dailyCtrl,
              onEditToggle: () => setState(() => _editingDaily = !_editingDaily),
              onSave: _saveDaily,
              onReset: _resetDaily,
              saving: _savingDaily,
            ),
            _buildPromptTab(
              label: t.weeklySummaryPromptLabel,
              infoText: t.promptAddonGeneralInfo,
              suggestion: t.promptAddonSuggestionWeekly,
              currentAddon: _promptWeekly ?? '',
              editing: _editingWeekly,
              controller: _weeklyCtrl,
              onEditToggle: () => setState(() => _editingWeekly = !_editingWeekly),
              onSave: _saveWeekly,
              onReset: _resetWeekly,
              saving: _savingWeekly,
            ),
            _buildPromptTab(
              label: t.morningInsightsPromptLabel,
              infoText: t.promptAddonGeneralInfo,
              suggestion: t.promptAddonSuggestionMorning,
              currentAddon: _promptMorning ?? '',
              editing: _editingMorning,
              controller: _morningCtrl,
              onEditToggle: () => setState(() => _editingMorning = !_editingMorning),
              onSave: _saveMorning,
              onReset: _resetMorning,
              saving: _savingMorning,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptTab({
    required String label,
    required String infoText,
    required String suggestion,
    required String currentAddon,
    required bool editing,
    required TextEditingController controller,
    required VoidCallback onEditToggle,
    required Future<void> Function() onSave,
    required Future<void> Function() onReset,
    required bool saving,
  }) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final display = currentAddon.trim();
    final hasAddon = display.isNotEmpty;
    final placeholderStyle = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);
    final displayText = hasAddon ? display : suggestion;

    if (editing) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: saving ? null : onSave,
                  child: Text(saving ? t.savingLabel : t.actionSave),
                ),
                const SizedBox(width: AppTheme.spacing1),
                TextButton(
                  onPressed: saving ? null : onReset,
                  child: Text(t.resetToDefault),
                ),
                const SizedBox(width: AppTheme.spacing1),
                TextButton(
                  onPressed: saving ? null : onEditToggle,
                  child: Text(t.dialogCancel),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacing4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(infoText, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                  const SizedBox(height: AppTheme.spacing2),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    minLines: 10,
                    maxLines: null,
                    style: theme.textTheme.bodySmall,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: suggestion,
                      hintMaxLines: 16,
                      contentPadding: const EdgeInsets.all(AppTheme.spacing3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onEditToggle,
              child: Text(t.actionEdit),
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(infoText, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          const SizedBox(height: AppTheme.spacing2),
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            child: SelectableText(
              displayText,
              style: hasAddon ? theme.textTheme.bodySmall : placeholderStyle,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSeg() async {
     if (_savingSeg) return;
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
        UINotifier.success(context, AppLocalizations.of(context).savedNormalPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
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
        UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingSeg = false);
    }
  }

  Future<void> _saveMerge() async {
    if (_savingMerge) return;
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
        UINotifier.success(context, AppLocalizations.of(context).savedMergePromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
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
        UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingMerge = false);
    }
  }

  Future<void> _saveDaily() async {
    if (_savingDaily) return;
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
        UINotifier.success(context, AppLocalizations.of(context).savedDailyPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingDaily = false);
    }
  }

  Future<void> _saveWeekly() async {
    if (_savingWeekly) return;
    setState(() => _savingWeekly = true);
    try {
      final text = _weeklyCtrl.text.trim();
      final normalized = text.isEmpty ? null : text;
      await _settings.setPromptWeekly(normalized);
      if (mounted) {
        setState(() {
          _promptWeekly = normalized;
          _weeklyCtrl.text = normalized ?? '';
          _editingWeekly = false;
        });
        UINotifier.success(context, AppLocalizations.of(context).savedWeeklyPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingWeekly = false);
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
        UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingDaily = false);
    }
  }

  Future<void> _resetWeekly() async {
    if (_savingWeekly) return;
    setState(() => _savingWeekly = true);
    try {
      await _settings.setPromptWeekly(null);
      if (mounted) {
        setState(() {
          _promptWeekly = null;
          _weeklyCtrl.text = '';
          _editingWeekly = false;
        });
        UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingWeekly = false);
    }
  }

  Future<void> _saveMorning() async {
    if (_savingMorning) return;
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
        UINotifier.success(context, AppLocalizations.of(context).savedDailyPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).saveFailedError(e.toString()));
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
        UINotifier.success(context, AppLocalizations.of(context).resetToDefaultPromptToast);
      }
    } catch (e) {
      if (mounted) UINotifier.error(context, AppLocalizations.of(context).resetFailedWithError(e.toString()));
    } finally {
      if (mounted) setState(() => _savingMorning = false);
    }
  }
}
