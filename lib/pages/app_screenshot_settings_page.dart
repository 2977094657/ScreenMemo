import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import '../models/app_info.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import '../services/per_app_screenshot_settings_service.dart';
import '../services/screenshot_service.dart';

/// 应用内独立的“截图设置”页面：严格复用全局设置的视觉与交互
class AppScreenshotSettingsPage extends StatefulWidget {
  const AppScreenshotSettingsPage({super.key});

  @override
  State<AppScreenshotSettingsPage> createState() =>
      _AppScreenshotSettingsPageState();
}

class _AppScreenshotSettingsPageState extends State<AppScreenshotSettingsPage> {
  late String _packageName;
  late AppInfo _appInfo;

  bool _initialized = false;
  bool _useCustom = false;

  bool _statsLoading = true;
  int? _statCount;
  int? _statSize;
  DateTime? _statLastCapture;
  bool _recomputingStats = false;

  // 质量设置
  String _imageFormat = 'webp_lossless';
  int _imageQuality = 90;
  bool _useTargetSize = false;
  int _targetSizeKb = 50;

  // 过期清理
  bool _expireEnabled = false;
  int _expireDays = 30;
  int _intervalSec = 5;

  // 历史压缩
  int _compressDays = 7;
  bool _compressingHistory = false;
  CompressionProgress? _compressionProgress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args == null) {
      Navigator.of(context).maybePop();
      return;
    }
    _packageName = args['packageName'] as String;
    _appInfo = args['appInfo'] as AppInfo;
    _restoreCompressionState();
    _loadAll();
  }

  @override
  void dispose() {
    ScreenshotService.instance.attachCompressionProgressListener(
      null,
      replayLatest: false,
    );
    super.dispose();
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
    await _loadStats();
    _restoreCompressionState();
  }

  Future<void> _loadStats({bool showSpinner = true}) async {
    if (!mounted) return;
    if (showSpinner) {
      setState(() {
        _statsLoading = true;
      });
    }
    int? count;
    int? size;
    DateTime? last;
    try {
      final stats = await ScreenshotService.instance
          .getScreenshotStatsCachedFirst();
      final appStats = stats['appStatistics'];
      if (appStats is Map) {
        final dynamic raw = appStats[_packageName];
        if (raw is Map) {
          final c = raw['totalCount'];
          final s = raw['totalSize'];
          final lc = raw['lastCaptureTime'];
          if (c is int) count = c;
          if (s is int) size = s;
          if (lc is DateTime) last = lc;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _statCount = count;
      _statSize = size;
      _statLastCapture = last;
      _statsLoading = false;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    String formatted;
    if (value >= 100) {
      formatted = value.toStringAsFixed(0);
    } else if (value >= 10) {
      formatted = value.toStringAsFixed(1);
    } else {
      formatted = value.toStringAsFixed(2);
    }
    return '$formatted ${units[index]}';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _formatLastCaptureValue(AppLocalizations l10n) {
    final dt = _statLastCapture;
    if (dt == null) {
      return '--';
    }
    final now = DateTime.now();
    if (dt.year == now.year) {
      return l10n.monthDayTime(
        _twoDigits(dt.month),
        _twoDigits(dt.day),
        _twoDigits(dt.hour),
        _twoDigits(dt.minute),
      );
    }
    return l10n.yearMonthDayTime(
      dt.year,
      _twoDigits(dt.month),
      _twoDigits(dt.day),
      _twoDigits(dt.hour),
      _twoDigits(dt.minute),
    );
  }

  void _showCompressDaysDialog() {
    final l10n = AppLocalizations.of(context);
    _showIntervalDialogStyle(
      title: l10n.setCompressDaysDialogTitle,
      label: l10n.compressDaysLabel,
      hint: l10n.compressDaysInputHint,
      value: _compressDays,
      onValid: (value) async {
        if (value < 1) {
          UINotifier.error(context, l10n.compressDaysInvalidError);
          return;
        }
        setState(() => _compressDays = value);
      },
    );
  }

  void _showTargetSizeDialog() {
    final l10n = AppLocalizations.of(context);
    _showIntervalDialogStyle(
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
          _useTargetSize = true;
        });
        await _saveQuality();
      },
    );
  }

  void _handleCompressionProgress(CompressionProgress progress) {
    if (!mounted) return;
    setState(() {
      _compressionProgress = progress;
      _compressingHistory = ScreenshotService.instance.compressionInFlightFor(
        _packageName,
      );
    });
  }

  void _restoreCompressionState() {
    final service = ScreenshotService.instance;
    final bool ongoing = service.compressionInFlightFor(_packageName);
    final CompressionProgress? latest = service.latestCompressionProgressFor(
      _packageName,
    );
    if (!mounted) return;
    setState(() {
      _compressingHistory = ongoing;
      if (latest != null) {
        _compressionProgress = latest;
      }
    });
    service.attachCompressionProgressListener(
      _handleCompressionProgress,
      packageName: _packageName,
    );
  }

  Future<void> _startHistoryCompression() async {
    if (_compressingHistory) return;
    if (_targetSizeKb < 50) {
      UINotifier.error(
        context,
        AppLocalizations.of(context).targetSizeInvalidError,
      );
      return;
    }
    setState(() {
      _compressingHistory = true;
      _compressionProgress = const CompressionProgress(
        total: 0,
        handled: 0,
        success: 0,
        skipped: 0,
        failed: 0,
        savedBytes: 0,
      );
    });
    CompressionResult? finalResult;
    try {
      finalResult = await ScreenshotService.instance.compressAppScreenshots(
        packageName: _packageName,
        days: _compressDays,
        targetSizeKb: _targetSizeKb,
        imageFormat: _imageFormat,
        imageQuality: _imageQuality,
        useTargetSize: true,
        onProgress: _handleCompressionProgress,
      );
      if (!mounted) return;
      final int savedBytes = finalResult.savedBytes > 0
          ? finalResult.savedBytes
          : 0;
      if (finalResult.success > 0) {
        await _loadStats(showSpinner: false);
        UINotifier.success(
          context,
          AppLocalizations.of(context).compressHistorySuccess(
            finalResult.success,
            _formatBytes(savedBytes),
          ),
        );
      } else if (finalResult.handled == 0 || finalResult.success == 0) {
        if (finalResult.skipped > 0 && finalResult.failed == 0) {
          UINotifier.info(
            context,
            AppLocalizations.of(context).compressHistoryNothing,
          );
        } else {
          UINotifier.error(
            context,
            AppLocalizations.of(context).compressHistoryFailure,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).compressHistoryFailure,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _compressingHistory = false;
        });
      }
    }
  }

  Future<void> _showRecomputeConfirm() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    await showUIDialog<void>(
      context: context,
      title: l10n.recomputeAppStatsConfirmTitle,
      message: l10n.recomputeAppStatsConfirmMessage,
      actions: [
        UIDialogAction(text: l10n.dialogCancel),
        UIDialogAction(
          text: l10n.dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (dialogCtx) async {
            await _performRecompute(dialogCtx);
          },
        ),
      ],
    );
  }

  Future<void> _performRecompute(BuildContext dialogContext) async {
    if (_recomputingStats) return;
    if (mounted) {
      setState(() {
        _recomputingStats = true;
      });
    }
    try {
      await ScreenshotService.instance.recomputeAppStats(_packageName);
      await _loadStats();
      if (mounted) {
        UINotifier.success(
          context,
          AppLocalizations.of(context).recomputeAppStatsSuccess,
        );
      }
    } catch (_) {
      if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      }
    } finally {
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      if (mounted) {
        setState(() {
          _recomputingStats = false;
        });
      }
    }
  }

  Future<void> _saveUseCustom(bool v) async {
    await PerAppScreenshotSettingsService.instance.setUseCustom(
      _packageName,
      v,
    );
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
    if (mounted)
      UINotifier.success(
        context,
        AppLocalizations.of(context).screenshotQualitySettingsSaved,
      );
  }

  Future<void> _saveExpire() async {
    await PerAppScreenshotSettingsService.instance.saveExpireSettings(
      packageName: _packageName,
      enabled: _expireEnabled,
      days: _expireDays < 1 ? 1 : _expireDays,
    );
    if (mounted)
      UINotifier.success(
        context,
        AppLocalizations.of(context).expireCleanupSaved,
      );
  }

  Future<void> _saveInterval() async {
    await PerAppScreenshotSettingsService.instance
        .saveScreenshotIntervalSeconds(_packageName, _intervalSec);
    if (mounted)
      UINotifier.success(
        context,
        AppLocalizations.of(context).intervalSavedSuccess(_intervalSec),
      );
  }

  void _showIntervalDialogStyle({
    required String title,
    required String label,
    required String hint,
    required int value,
    required void Function(int) onValid,
  }) {
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
              UINotifier.error(
                ctx,
                AppLocalizations.of(ctx).intervalInvalidError,
              );
              return;
            }
            onValid(v);
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
      ],
    );
  }

  Widget _buildStatsCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color cardColor = theme.colorScheme.surfaceVariant.withOpacity(
      isDark ? 0.28 : 0.6,
    );
    final Color borderColor = theme.colorScheme.outline.withOpacity(
      isDark ? 0.2 : 0.35,
    );

    Widget buildStatItem(String label, String value) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      );
    }

    final Widget statsContent;
    if (_statsLoading) {
      statsContent = SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      );
    } else {
      final countValue = (_statCount ?? 0).toString();
      final sizeValue = _statSize != null ? _formatBytes(_statSize!) : '--';
      final lastValue = _formatLastCaptureValue(l10n);

      statsContent = Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing3,
          vertical: AppTheme.spacing2,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(isDark ? 0.25 : 0.9),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Row(
          children: [
            Expanded(child: buildStatItem(l10n.appStatsCountTitle, countValue)),
            const SizedBox(width: AppTheme.spacing4),
            Expanded(child: buildStatItem(l10n.appStatsSizeTitle, sizeValue)),
            const SizedBox(width: AppTheme.spacing4),
            Expanded(
              child: buildStatItem(l10n.appStatsLastCaptureTitle, lastValue),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  Icons.insights_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.appStatsSectionTitle,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing1),
                    Text(
                      l10n.recomputeAppStatsDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacing3),
              SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: _recomputingStats ? null : _showRecomputeConfirm,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing3,
                      vertical: AppTheme.spacing1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                  ),
                  child: _recomputingStats
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : Text(l10n.recomputeAppStatsAction),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing3),
          statsContent,
        ],
      ),
    );
  }

  Widget _buildHistoryCompressionCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
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
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.6),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  Icons.auto_fix_high_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.compressHistoryTitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.compressHistoryDescription(
                        _compressDays,
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
                onPressed: _compressingHistory ? null : _showCompressDaysDialog,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing3,
                    vertical: AppTheme.spacing1,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: Size.zero,
                ),
                child: buildUnderlinedValueText(
                  text: l10n.compressHistorySetDays(_compressDays),
                  value: _compressDays.toString(),
                  enabled: !_compressingHistory,
                ),
              ),
              TextButton(
                onPressed: _compressingHistory ? null : _showTargetSizeDialog,
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
                  enabled: !_compressingHistory,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing3),
          if (_compressionProgress != null &&
              (_compressionProgress!.handled > 0 || _compressingHistory))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UIProgress(
                  value: _compressionProgress!.ratio.clamp(0.0, 1.0),
                  height: 4,
                ),
                const SizedBox(height: AppTheme.spacing1),
                Text(
                  l10n.compressHistoryProgress(
                    _compressionProgress!.handled,
                    _compressionProgress!.total,
                    _formatBytes(
                      _compressionProgress!.savedBytes > 0
                          ? _compressionProgress!.savedBytes
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
              onPressed: _compressingHistory ? null : _startHistoryCompression,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing3,
                  vertical: AppTheme.spacing2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
              ),
              child: _compressingHistory
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          _appInfo.appName.isEmpty
              ? l10n.screenshotSectionTitle
              : '${l10n.screenshotSectionTitle} · ${_appInfo.appName}',
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacing4),
        children: [
          _buildStatsCard(l10n),
          const SizedBox(height: AppTheme.spacing4),
          _buildHistoryCompressionCard(l10n),
          const SizedBox(height: AppTheme.spacing4),
          // 自定义开关（置顶）
          Container(
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
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
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withOpacity(0.6),
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
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(
                              context,
                            ).screenshotIntervalTitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(
                              context,
                            ).screenshotIntervalDesc(_intervalSec),
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
                    const SizedBox(width: AppTheme.spacing2),
                    TextButton(
                      onPressed: () {
                        _showIntervalDialogStyle(
                          title: AppLocalizations.of(
                            context,
                          ).setIntervalDialogTitle,
                          label: AppLocalizations.of(
                            context,
                          ).intervalSecondsLabel,
                          hint: AppLocalizations.of(context).intervalInputHint,
                          value: _intervalSec,
                          onValid: (v) async {
                            if (v < 5 || v > 60) {
                              UINotifier.error(
                                context,
                                AppLocalizations.of(
                                  context,
                                ).intervalInvalidError,
                              );
                              return;
                            }
                            setState(() => _intervalSec = v);
                            await _saveInterval();
                          },
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing3,
                          vertical: AppTheme.spacing1,
                        ),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSm,
                            ),
                          ),
                          child: Icon(
                            Icons.image_outlined,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
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
                                    Text(
                                      l10n.screenshotQualityTitle,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    IgnorePointer(
                                      ignoring: !_useTargetSize,
                                      child: Opacity(
                                        opacity: _useTargetSize ? 1.0 : 0.5,
                                        child: Row(
                                          children: [
                                            Text(
                                              l10n.currentTimeLabel,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                            const SizedBox(
                                              width: AppTheme.spacing1,
                                            ),
                                            GestureDetector(
                                              onTap: _useTargetSize
                                                  ? () => _showIntervalDialogStyle(
                                                      title: l10n
                                                          .setTargetSizeDialogTitle,
                                                      label: l10n
                                                          .targetSizeKbLabel,
                                                      hint: l10n
                                                          .targetSizeInvalidError,
                                                      value: _targetSizeKb,
                                                      onValid: (kb) async {
                                                        if (kb < 50) {
                                                          UINotifier.error(
                                                            context,
                                                            l10n.targetSizeInvalidError,
                                                          );
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
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: _useTargetSize
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .primary
                                                          : Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      decoration: _useTargetSize
                                                          ? TextDecoration
                                                                .underline
                                                          : TextDecoration.none,
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(
                                              width: AppTheme.spacing1,
                                            ),
                                            Flexible(
                                              child: Text(
                                                l10n.clickToModifyHint,
                                                softWrap: false,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
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
                                    value: _useTargetSize,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
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
                    top: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withOpacity(0.6),
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
                        Icons.auto_delete_outlined,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
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
                                Text(
                                  l10n.screenshotExpireTitle,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 2),
                                IgnorePointer(
                                  ignoring: !_expireEnabled,
                                  child: Opacity(
                                    opacity: _expireEnabled ? 1.0 : 0.5,
                                    child: Row(
                                      children: [
                                        Text(
                                          l10n.currentTimeLabel,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                        const SizedBox(
                                          width: AppTheme.spacing1,
                                        ),
                                        GestureDetector(
                                          onTap: _expireEnabled
                                              ? () => _showIntervalDialogStyle(
                                                  title: l10n
                                                      .setExpireDaysDialogTitle,
                                                  label: l10n.expireDaysLabel,
                                                  hint:
                                                      l10n.expireDaysInputHint,
                                                  value: _expireDays,
                                                  onValid: (d) async {
                                                    if (d < 1) {
                                                      UINotifier.error(
                                                        context,
                                                        l10n.expireDaysInvalidError,
                                                      );
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
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: _expireEnabled
                                                      ? Theme.of(
                                                          context,
                                                        ).colorScheme.primary
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                  decoration: _expireEnabled
                                                      ? TextDecoration.underline
                                                      : TextDecoration.none,
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
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
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
