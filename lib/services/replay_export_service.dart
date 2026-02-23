import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../models/screenshot_record.dart';
import '../widgets/ui_components.dart';
import 'flutter_logger.dart';
import 'navigation_service.dart';
import 'nsfw_preference_service.dart';
import 'path_service.dart';
import 'screenshot_service.dart';

enum ReplayQuality { low, medium, high }

enum ReplayAppProgressBarPosition { top, right, bottom, left }

enum ReplayNsfwMode { mask, show, hide }

class ReplayOptions {
  final int fps;
  final int targetDurationSeconds;
  final int shortSide; // 0 = original
  final ReplayQuality quality;
  final bool overlayEnabled;
  final bool appProgressBarEnabled;
  final ReplayAppProgressBarPosition appProgressBarPosition;
  final ReplayNsfwMode nsfwMode;
  final bool saveToGallery;
  final bool openGalleryAfterSave;

  const ReplayOptions({
    this.fps = 24,
    this.targetDurationSeconds = 0,
    this.shortSide = 0,
    this.quality = ReplayQuality.high,
    this.overlayEnabled = true,
    this.appProgressBarEnabled = true,
    this.appProgressBarPosition = ReplayAppProgressBarPosition.right,
    this.nsfwMode = ReplayNsfwMode.mask,
    this.saveToGallery = false,
    this.openGalleryAfterSave = false,
  });

  ReplayOptions copyWith({
    int? fps,
    int? targetDurationSeconds,
    int? shortSide,
    ReplayQuality? quality,
    bool? overlayEnabled,
    bool? appProgressBarEnabled,
    ReplayAppProgressBarPosition? appProgressBarPosition,
    ReplayNsfwMode? nsfwMode,
    bool? saveToGallery,
    bool? openGalleryAfterSave,
  }) {
    return ReplayOptions(
      fps: fps ?? this.fps,
      targetDurationSeconds:
          targetDurationSeconds ?? this.targetDurationSeconds,
      shortSide: shortSide ?? this.shortSide,
      quality: quality ?? this.quality,
      overlayEnabled: overlayEnabled ?? this.overlayEnabled,
      appProgressBarEnabled:
          appProgressBarEnabled ?? this.appProgressBarEnabled,
      appProgressBarPosition:
          appProgressBarPosition ?? this.appProgressBarPosition,
      nsfwMode: nsfwMode ?? this.nsfwMode,
      saveToGallery: saveToGallery ?? this.saveToGallery,
      openGalleryAfterSave: openGalleryAfterSave ?? this.openGalleryAfterSave,
    );
  }
}

class ReplayResult {
  final String outputPath;
  final int width;
  final int height;
  final int frames;
  final int durationMs;
  final int fileSize;

  const ReplayResult({
    required this.outputPath,
    required this.width,
    required this.height,
    required this.frames,
    required this.durationMs,
    required this.fileSize,
  });
}

class ReplayExportTask {
  final DateTime start;
  final DateTime end;

  const ReplayExportTask({required this.start, required this.end});
}

class ReplayExportException implements Exception {
  final String message;
  const ReplayExportException(this.message);
  @override
  String toString() => message;
}

int replayTargetFrames({required int fps, required int durationSeconds}) {
  final int f = fps <= 0 ? 1 : fps;
  final int d = durationSeconds <= 0 ? 1 : durationSeconds;
  return f * d;
}

int replayBucketMillis({
  required int startMillis,
  required int endMillis,
  required int targetFrames,
}) {
  final int tf = targetFrames <= 0 ? 1 : targetFrames;
  final int range = endMillis - startMillis;
  if (range <= 0) return 1;
  final int b = range ~/ tf;
  return b <= 0 ? 1 : b;
}

List<ScreenshotRecord> replayDedupeByBucket({
  required List<ScreenshotRecord> candidates,
  required int startMillis,
  required int bucketMillis,
}) {
  if (candidates.isEmpty) return <ScreenshotRecord>[];
  final int bucket = bucketMillis <= 0 ? 1 : bucketMillis;
  final seen = <int>{};
  final out = <ScreenshotRecord>[];
  for (final s in candidates) {
    final int ts = s.captureTime.millisecondsSinceEpoch;
    final int idx = ((ts - startMillis) ~/ bucket);
    if (seen.add(idx)) out.add(s);
  }
  return out;
}

List<ScreenshotRecord> replayDownsampleEvenly({
  required List<ScreenshotRecord> frames,
  required int targetFrames,
}) {
  if (frames.isEmpty) return <ScreenshotRecord>[];
  final int target = targetFrames <= 0 ? 1 : targetFrames;
  if (frames.length <= target) return List<ScreenshotRecord>.from(frames);
  final int n = frames.length;
  final double step = n / target;
  final out = <ScreenshotRecord>[];
  for (int i = 0; i < target; i++) {
    final int idx = math.min(n - 1, (i * step).floor());
    out.add(frames[idx]);
  }
  return out;
}

class ReplayExportService {
  ReplayExportService._();
  static final ReplayExportService instance = ReplayExportService._();

  static const int maxFrames = 12000;

  static const MethodChannel _channel = MethodChannel(
    'com.fqyw.screen_memo/accessibility',
  );

  final ValueNotifier<ReplayExportTask?> exportTaskNotifier =
      ValueNotifier<ReplayExportTask?>(null);

  bool _inFlight = false;

  Future<ReplayResult> composeReplay({
    required DateTime start,
    required DateTime end,
    required ReplayOptions options,
  }) async {
    final NavigatorState? nav =
        NavigationService.instance.navigatorKey.currentState;
    final BuildContext? startCtx = nav?.context;
    final OverlayState? overlay = nav?.overlay;
    final AppLocalizations? l10n = startCtx == null
        ? null
        : AppLocalizations.of(startCtx);

    if (_inFlight) {
      const msg = 'Replay export already running';
      if (overlay != null && overlay.mounted) {
        UINotifier.errorOnOverlay(
          overlay,
          msg,
          duration: const Duration(seconds: 2),
        );
      }
      throw const ReplayExportException(msg);
    }
    _inFlight = true;

    final String msgNoScreenshots =
        l10n?.timelineReplayNoScreenshots ?? 'No screenshots in this range';
    final String msgFailed = l10n?.timelineReplayFailed ?? 'Replay failed';

    try {
      exportTaskNotifier.value = ReplayExportTask(start: start, end: end);
      final int startMillis = start.millisecondsSinceEpoch;
      final int endMillis = end.millisecondsSinceEpoch;
      if (endMillis < startMillis) {
        throw const ReplayExportException('End time must be after start time');
      }

      final int fps = options.fps <= 0 ? 24 : options.fps;
      final int totalCount = await ScreenshotService.instance
          .getGlobalScreenshotCountBetween(
            startMillis: startMillis,
            endMillis: endMillis,
          );
      if (totalCount <= 0) {
        throw ReplayExportException(msgNoScreenshots);
      }

      final bool needSampling = totalCount > maxFrames;
      final int bucketMillis = needSampling
          ? replayBucketMillis(
              startMillis: startMillis,
              endMillis: endMillis,
              targetFrames: maxFrames,
            )
          : 1;

      final List<ScreenshotRecord> candidates = await ScreenshotService.instance
          .getGlobalScreenshotsBucketedBetween(
            startMillis: startMillis,
            endMillis: endMillis,
            bucketMillis: bucketMillis,
          );
      if (candidates.isEmpty) {
        throw ReplayExportException(msgNoScreenshots);
      }

      // Ensure time-ascending; DB should already return ASC, but keep it safe.
      candidates.sort((a, b) => a.captureTime.compareTo(b.captureTime));
      List<ScreenshotRecord> frames = replayDedupeByBucket(
        candidates: candidates,
        startMillis: startMillis,
        bucketMillis: bucketMillis,
      );
      if (frames.isEmpty) {
        throw ReplayExportException(msgNoScreenshots);
      }

      if (needSampling && frames.length > maxFrames) {
        frames = replayDownsampleEvenly(
          frames: frames,
          targetFrames: maxFrames,
        );
      }
      if (frames.isEmpty) {
        throw ReplayExportException(msgNoScreenshots);
      }

      final Directory? base = await PathService.getInternalAppDir(
        'output/replay',
      );
      if (base == null) {
        throw const ReplayExportException(
          'Failed to resolve replay output dir',
        );
      }

      final String ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final File framesJsonl = File(p.join(base.path, 'frames_$ts.jsonl'));
      final File output = File(p.join(base.path, 'replay_$ts.mp4'));

      final Map<String, bool> nsfwMaskByFilePath =
          options.nsfwMode == ReplayNsfwMode.show
          ? const <String, bool>{}
          : await _buildNsfwMaskByFilePath(frames);
      await _writeFramesJsonl(
        framesJsonl,
        frames,
        nsfwMaskByFilePath: nsfwMaskByFilePath,
      );

      final Map<dynamic, dynamic>? res = await _channel
          .invokeMethod('composeReplayVideo', <String, Object?>{
            'framesJsonlPath': framesJsonl.path,
            'outputPath': output.path,
            'fps': fps,
            'shortSide': options.shortSide,
            'quality': options.quality.name,
            'overlayEnabled': options.overlayEnabled,
            'appProgressBarEnabled': options.appProgressBarEnabled,
            'appProgressBarPosition': options.appProgressBarPosition.name,
            'nsfwMode': options.nsfwMode.name,
            // i18n text for NSFW mask overlay (optional on Android side).
            'nsfwTitle': l10n?.nsfwWarningTitle ?? 'Content Warning: Adult Content',
            'nsfwSubtitle':
                l10n?.nsfwWarningSubtitle ??
                'This content has been marked as adult content',
          });

      final String outPath = (res?['outputPath'] as String?) ?? output.path;
      final int width = (res?['width'] as int?) ?? 0;
      final int height = (res?['height'] as int?) ?? 0;
      final int framesOut = (res?['frames'] as int?) ?? frames.length;
      final int durationMs =
          (res?['durationMs'] as int?) ??
          ((framesOut * 1000) ~/ math.max(1, fps));
      final int fileSize =
          (res?['fileSize'] as int?) ??
          (() {
            try {
              return File(outPath).lengthSync();
            } catch (_) {
              return 0;
            }
          })();

      try {
        if (await framesJsonl.exists()) {
          await framesJsonl.delete();
        }
      } catch (_) {}

      if (options.saveToGallery) {
        await _saveVideoToGallery(outPath, l10n: l10n);
        if (options.openGalleryAfterSave) {
          try {
            await Gal.open();
          } catch (_) {}
        }
      }

      if (!options.saveToGallery) {
        if (overlay == null || !overlay.mounted) {
          // No UI context available; just return the result.
          return ReplayResult(
            outputPath: outPath,
            width: width,
            height: height,
            frames: framesOut,
            durationMs: durationMs,
            fileSize: fileSize,
          );
        }
        final readyMsg = l10n?.timelineReplayReady ?? 'Replay generated';
        final saveLabel = l10n?.saveImageTooltip ?? 'Save to gallery';
        UINotifier.successOnOverlay(
          overlay,
          readyMsg,
          duration: const Duration(seconds: 6),
          actionLabel: saveLabel,
          onAction: () {
            unawaited(_saveVideoToGallery(outPath, l10n: l10n));
          },
        );
      }

      return ReplayResult(
        outputPath: outPath,
        width: width,
        height: height,
        frames: framesOut,
        durationMs: durationMs,
        fileSize: fileSize,
      );
    } on ReplayExportException catch (e) {
      if (overlay != null && overlay.mounted) {
        UINotifier.errorOnOverlay(
          overlay,
          e.message,
          duration: const Duration(seconds: 3),
        );
      }
      rethrow;
    } catch (e) {
      try {
        await FlutterLogger.nativeError('Replay', 'composeReplay 失败: $e');
      } catch (_) {}
      if (overlay != null && overlay.mounted) {
        UINotifier.errorOnOverlay(overlay, msgFailed);
      }
      throw ReplayExportException(msgFailed);
    } finally {
      exportTaskNotifier.value = null;
      _inFlight = false;
    }
  }

  Future<void> _writeFramesJsonl(
    File file,
    List<ScreenshotRecord> frames, {
    Map<String, bool> nsfwMaskByFilePath = const <String, bool>{},
  }) async {
    if (frames.isEmpty) {
      throw const ReplayExportException('Empty frames');
    }

    final sink = file.openWrite();
    try {
      for (final s in frames) {
        final String path = await _resolvePathToAbsolute(s.filePath);
        final line = jsonEncode(<String, Object?>{
          'path': path,
          'ts': s.captureTime.millisecondsSinceEpoch,
          'app': s.appName,
          'pkg': s.appPackageName,
          'nsfw': nsfwMaskByFilePath[s.filePath] == true,
        });
        sink.writeln(line);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  Future<Map<String, bool>> _buildNsfwMaskByFilePath(
    List<ScreenshotRecord> frames,
  ) async {
    if (frames.isEmpty) return const <String, bool>{};

    final NsfwPreferenceService nsfw = NsfwPreferenceService.instance;
    try {
      try {
        await nsfw.ensureRulesLoaded();
      } catch (_) {}

      final List<String> filePaths = frames
          .map((e) => e.filePath.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);

      if (filePaths.isNotEmpty) {
        try {
          await nsfw.preloadAiNsfwFlags(filePaths: filePaths);
        } catch (_) {}
        try {
          await nsfw.preloadSegmentNsfwFlags(filePaths: filePaths);
        } catch (_) {}
      }

      final Map<String, Set<int>> manualIdsByPkg = <String, Set<int>>{};
      for (final s in frames) {
        final int? id = s.id;
        final String pkg = s.appPackageName.trim();
        if (id == null || pkg.isEmpty) continue;
        manualIdsByPkg.putIfAbsent(pkg, () => <int>{}).add(id);
      }
      for (final entry in manualIdsByPkg.entries) {
        try {
          await nsfw.preloadManualFlags(
            appPackageName: entry.key,
            screenshotIds: entry.value.toList(growable: false),
          );
        } catch (_) {}
      }

      final Map<String, bool> out = <String, bool>{};
      for (final s in frames) {
        out[s.filePath] = nsfw.shouldMaskCached(s);
      }
      return out;
    } catch (_) {
      return const <String, bool>{};
    }
  }

  Future<String> _resolvePathToAbsolute(String filePath) async {
    if (p.isAbsolute(filePath)) return filePath;
    try {
      final Directory? base = await PathService.getInternalAppDir();
      if (base != null) return p.join(base.path, filePath);
    } catch (_) {}
    return filePath;
  }

  Future<void> _saveVideoToGallery(
    String path, {
    required AppLocalizations? l10n,
  }) async {
    final OverlayState? overlay =
        NavigationService.instance.navigatorKey.currentState?.overlay;
    bool has = false;
    try {
      try {
        has = await Gal.hasAccess(toAlbum: true);
      } catch (_) {}
      if (!has) {
        try {
          await Gal.requestAccess(toAlbum: true);
        } catch (_) {
          if (overlay != null && overlay.mounted) {
            UINotifier.errorOnOverlay(
              overlay,
              l10n?.requestGalleryPermissionFailed ??
                  'Request gallery permission failed',
            );
          }
          return;
        }
      }
      await Gal.putVideo(path);
      if (overlay != null && overlay.mounted) {
        UINotifier.successOnOverlay(
          overlay,
          l10n?.saveImageSuccess ?? 'Saved to gallery',
        );
      }
    } on GalException catch (_) {
      if (overlay != null && overlay.mounted) {
        UINotifier.errorOnOverlay(
          overlay,
          l10n?.saveImageFailed ?? 'Save failed',
        );
      }
    } catch (_) {
      if (overlay != null && overlay.mounted) {
        UINotifier.errorOnOverlay(
          overlay,
          l10n?.saveImageFailed ?? 'Save failed',
        );
      }
    }
  }
}
