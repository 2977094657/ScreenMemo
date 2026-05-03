import 'package:flutter_test/flutter_test.dart';

import 'package:screen_memo/models/screenshot_record.dart';
import 'package:screen_memo/features/timeline/application/replay_export_service.dart';

ScreenshotRecord _shot(int millis) {
  return ScreenshotRecord(
    id: 1,
    appPackageName: 'pkg',
    appName: 'App',
    filePath: '/tmp/a.jpg',
    captureTime: DateTime.fromMillisecondsSinceEpoch(millis),
    fileSize: 1,
  );
}

void main() {
  group('Replay sampling helpers', () {
    test('targetFrames = fps * duration (with clamping)', () {
      expect(replayTargetFrames(fps: 24, durationSeconds: 60), 1440);
      expect(replayTargetFrames(fps: 0, durationSeconds: 60), 60);
      expect(replayTargetFrames(fps: 24, durationSeconds: 0), 24);
    });

    test('bucketMillis computed from range/targetFrames (min 1)', () {
      expect(
        replayBucketMillis(startMillis: 0, endMillis: 1000, targetFrames: 100),
        10,
      );
      expect(
        replayBucketMillis(startMillis: 0, endMillis: 10, targetFrames: 100),
        1,
      );
      expect(
        replayBucketMillis(startMillis: 1000, endMillis: 1000, targetFrames: 1),
        1,
      );
    });

    test('dedupeByBucket keeps earliest in each bucket', () {
      const start = 0;
      const bucket = 10;
      final candidates = <ScreenshotRecord>[
        _shot(0),
        _shot(5),
        _shot(15),
        _shot(19),
      ];

      final out = replayDedupeByBucket(
        candidates: candidates,
        startMillis: start,
        bucketMillis: bucket,
      );

      expect(out.map((e) => e.captureTime.millisecondsSinceEpoch).toList(), [
        0,
        15,
      ]);
    });

    test('downsampleEvenly picks approximately uniform indices', () {
      final frames = List<ScreenshotRecord>.generate(10, (i) => _shot(i));
      final out = replayDownsampleEvenly(frames: frames, targetFrames: 4);
      expect(out.map((e) => e.captureTime.millisecondsSinceEpoch).toList(), [
        0,
        2,
        5,
        7,
      ]);
    });
  });
}
