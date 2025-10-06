import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import '../models/app_info.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import '../services/per_app_screenshot_settings_service.dart';

/// 应用内独立的“截图设置”页面：严格复用全局设置的视觉与交互
class AppScreenshotSettingsPage extends StatefulWidget {
  const AppScreenshotSettingsPage({super.key});

  @override
  State<AppScreenshotSettingsPage> createState() => _AppScreenshotSettingsPageState();
}

class _AppScreenshotSettingsPageState extends State<AppScreenshotSettingsPage> {
  late String _packageName;
  late AppInfo _appInfo;

  bool _initialized = false;
  bool _useCustom = false;

  // 质量设置
  String _imageFormat = 'webp_lossless';
  int _imageQuality = 90;
  bool _useTargetSize = false;
  int _targetSizeKb = 50;

  // 过期清理
  bool _expireEnabled = false;
  int _expireDays = 30;
  int _intervalSec = 5;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args == null) {
      Navigator.of(context).maybePop();
      return;
    }
    _packageName = args['packageName'] as String;
    _appInfo = args['appInfo'] as AppInfo;
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final s = PerAppScreenshotSettingsService.instance;
      final useCustom = await s.getUseCustom(_packageName);
      final q = await s.getQualitySettings(_packageName);
      final e = await s.getExpireSettings(_packageName);
      final iv = await s.getScreenshotIntervalSeconds(_packageName);
      if (!mounted) return;
      setState(() {
        _useCustom = useCustom;
        _imageFormat = (q['image_format'] as String?) ?? _imageFormat;
        _imageQuality = (q['image_quality'] as int?) ?? _imageQuality;
        _useTargetSize = (q['use_target_size'] as bool?) ?? _useTargetSize;
        _targetSizeKb = (q['target_size_kb'] as int?) ?? _targetSizeKb;
        _expireEnabled = (e['enabled'] as bool?) ?? _expireEnabled;
        _expireDays = (e['days'] as int?) ?? _expireDays;
        _intervalSec = (iv ?? _intervalSec).clamp(5, 60);
      });
    } catch (_) {}
  }

  Future<void> _saveUseCustom(bool v) async {
    await PerAppScreenshotSettingsService.instance.setUseCustom(_packageName, v);
    if (mounted) setState(() => _useCustom = v);
  }

  Future<void> _saveQuality() async {
    // 与全局页一致：根据 useTargetSize 决定格式默认
    final effectiveFormat = _useTargetSize ? 'webp_lossy' : _imageFormat;
    await PerAppScreenshotSettingsService.instance.saveQualitySettings(
      packageName: _packageName,
      imageFormat: effectiveFormat,
      imageQuality: _imageQuality,
      useTargetSize: _useTargetSize,
      targetSizeKb: _targetSizeKb < 50 ? 50 : _targetSizeKb,
    );
    if (mounted) UINotifier.success(context, AppLocalizations.of(context).screenshotQualitySettingsSaved);
  }

  Future<void> _saveExpire() async {
    await PerAppScreenshotSettingsService.instance.saveExpireSettings(
      packageName: _packageName,
      enabled: _expireEnabled,
      days: _expireDays < 1 ? 1 : _expireDays,
    );
    if (mounted) UINotifier.success(context, AppLocalizations.of(context).expireCleanupSaved);
  }

  Future<void> _saveInterval() async {
    await PerAppScreenshotSettingsService.instance.saveScreenshotIntervalSeconds(_packageName, _intervalSec);
    if (mounted) UINotifier.success(context, AppLocalizations.of(context).intervalSavedSuccess(_intervalSec));
  }

  void _showIntervalDialogStyle({required String title, required String label, required String hint, required int value, required void Function(int) onValid}) {
    final controller = TextEditingController(text: value.toString());
    showUIDialog<void>(
      context: context,
      title: title,
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
                labelText: label,
                hintText: hint,
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
            final v = int.tryParse(input);
            if (v == null) {
              UINotifier.error(ctx, AppLocalizations.of(ctx).intervalInvalidError);
              return;
            }
            onValid(v);
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l10n.screenshotSectionTitle),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacing4),
        children: [
          // 自定义开关（置顶）
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.6), width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Icon(
                    Icons.tune,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppTheme.spacing3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.customLabel,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _useCustom ? l10n.customLabel : l10n.defaultLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 0.9,
                  child: Switch(
                    value: _useCustom,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) async {
                      await _saveUseCustom(v);
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.spacing4),

          // 截屏间隔（与全局样式一致；未开启自定义时灰显并禁用）
          IgnorePointer(
            ignoring: !_useCustom,
            child: Opacity(
              opacity: _useCustom ? 1.0 : 0.5,
              child: Container(
                padding: const EdgeInsets.all(AppTheme.spacing3),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.6),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      child: Icon(
                        Icons.timer_outlined,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context).screenshotIntervalTitle,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(context).screenshotIntervalDesc(_intervalSec),
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
                        _showIntervalDialogStyle(
                          title: AppLocalizations.of(context).setIntervalDialogTitle,
                          label: AppLocalizations.of(context).intervalSecondsLabel,
                          hint: AppLocalizations.of(context).intervalInputHint,
                          value: _intervalSec,
                          onValid: (v) async {
                            if (v < 5 || v > 60) {
                              UINotifier.error(context, AppLocalizations.of(context).intervalInvalidError);
                              return;
                            }
                            setState(() => _intervalSec = v);
                            await _saveInterval();
                          },
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing3, vertical: AppTheme.spacing1),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: Size.zero,
                      ),
                      child: Text(AppLocalizations.of(context).actionSet),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: AppTheme.spacing4),

          // 截图质量（复用全局样式与交互）
          IgnorePointer(
            ignoring: !_useCustom,
            child: Opacity(
              opacity: _useCustom ? 1.0 : 0.5,
              child: Container(
                padding: const EdgeInsets.all(AppTheme.spacing3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          ),
                          child: Icon(
                            Icons.image_outlined,
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacing3),
                        Expanded(
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 72),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l10n.screenshotQualityTitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 2),
                                    IgnorePointer(
                                      ignoring: !_useTargetSize,
                                      child: Opacity(
                                        opacity: _useTargetSize ? 1.0 : 0.5,
                                        child: Row(
                                          children: [
                                            Text(l10n.currentTimeLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                            const SizedBox(width: AppTheme.spacing1),
                                            GestureDetector(
                                              onTap: _useTargetSize
                                                  ? () => _showIntervalDialogStyle(
                                                        title: l10n.setTargetSizeDialogTitle,
                                                        label: l10n.targetSizeKbLabel,
                                                        hint: l10n.targetSizeInvalidError,
                                                        value: _targetSizeKb,
                                                        onValid: (kb) async {
                                                          if (kb < 50) {
                                                            UINotifier.error(context, l10n.targetSizeInvalidError);
                                                            return;
                                                          }
                                                          setState(() {
                                                            _targetSizeKb = kb;
                                                          });
                                                          await _saveQuality();
                                                        },
                                                      )
                                                  : null,
                                              child: Text(
                                                '${_targetSizeKb}KB',
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      color: _useTargetSize ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                                                      decoration: _useTargetSize ? TextDecoration.underline : TextDecoration.none,
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: AppTheme.spacing1),
                                            Flexible(
                                              child: Text(l10n.clickToModifyHint, softWrap: false, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                            ),
                                          ],
                                        ),
                                      ),
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
                                    value: _useTargetSize,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (v) async {
                                      setState(() => _useTargetSize = v);
                                      await _saveQuality();
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: AppTheme.spacing4),

          // 截图过期清理（复用样式与交互）
          IgnorePointer(
            ignoring: !_useCustom,
            child: Opacity(
              opacity: _useCustom ? 1.0 : 0.5,
              child: Container(
                padding: const EdgeInsets.all(AppTheme.spacing3),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.6), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      child: Icon(
                        Icons.auto_delete_outlined,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing3),
                    Expanded(
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 72),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.screenshotExpireTitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                IgnorePointer(
                                  ignoring: !_expireEnabled,
                                  child: Opacity(
                                    opacity: _expireEnabled ? 1.0 : 0.5,
                                    child: Row(
                                      children: [
                                        Text(l10n.currentTimeLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                        const SizedBox(width: AppTheme.spacing1),
                                        GestureDetector(
                                          onTap: _expireEnabled
                                              ? () => _showIntervalDialogStyle(
                                                    title: l10n.setExpireDaysDialogTitle,
                                                    label: l10n.expireDaysLabel,
                                                    hint: l10n.expireDaysInputHint,
                                                    value: _expireDays,
                                                    onValid: (d) async {
                                                      if (d < 1) {
                                                        UINotifier.error(context, l10n.expireDaysInvalidError);
                                                        return;
                                                      }
                                                      setState(() {
                                                        _expireDays = d;
                                                      });
                                                      await _saveExpire();
                                                    },
                                                  )
                                              : null,
                                          child: Text(
                                            l10n.expireDaysUnit(_expireDays),
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: _expireEnabled ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                                                  decoration: _expireEnabled ? TextDecoration.underline : TextDecoration.none,
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
                          Positioned(
                            top: -1,
                            right: 0,
                            child: Transform.scale(
                              scale: 0.9,
                              child: Switch(
                                value: _expireEnabled,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onChanged: (v) async {
                                  setState(() => _expireEnabled = v);
                                  await _saveExpire();
                                },
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
          ),
        ],
      ),
    );
  }
}


