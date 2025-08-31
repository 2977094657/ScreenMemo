import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

class GenParams {
  final String baseDirPath;
  final String packageName;
  final String appName;
  final int seq;
  final int timestampMs;
  const GenParams({
    required this.baseDirPath,
    required this.packageName,
    required this.appName,
    required this.seq,
    required this.timestampMs,
  });
}

Future<Map<String, dynamic>> generateOneIsolate(GenParams params) async {
  final rnd = math.Random(params.seq * 9973);
  final ts = DateTime.fromMillisecondsSinceEpoch(params.timestampMs);

  final folderYm = '${ts.year.toString().padLeft(4,'0')}-${ts.month.toString().padLeft(2,'0')}';
  final folderD = ts.day.toString().padLeft(2,'0');
  final targetDir = Directory(p.join(
    params.baseDirPath,
    'output',
    'screen',
    params.packageName,
    folderYm,
    folderD,
  ));
  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);
  }

  final fileName = 'test_${ts.millisecondsSinceEpoch}_${params.seq.toString().padLeft(4,'0')}.png';
  final file = File(p.join(targetDir.path, fileName));

  // 随机目标大小（100KB - 2MB）
  const int minBytes = 100 * 1024;
  const int maxBytes = 2 * 1024 * 1024;
  final int targetBytes = minBytes + rnd.nextInt(maxBytes - minBytes + 1);

  int w, h;
  if (targetBytes < 300 * 1024) {
    w = 480; h = 960;
  } else if (targetBytes < 1024 * 1024) {
    w = 720; h = 1440;
  } else {
    w = 1080; h = 2160;
  }

  // 使用 image 包生成 png，避免在子 isolate 依赖 dart:ui
  final im = img.Image(width: w, height: h);
  // 背景渐变
  final c1 = 0xFF0000FF; // blue
  final c2 = 0xFF800080; // purple
  for (int y = 0; y < h; y++) {
    final t = y / (h - 1);
    final r = ((1 - t) * ((c1 >> 16) & 0xFF) + t * ((c2 >> 16) & 0xFF)).toInt();
    final g = ((1 - t) * ((c1 >> 8) & 0xFF) + t * ((c2 >> 8) & 0xFF)).toInt();
    final b = ((1 - t) * (c1 & 0xFF) + t * (c2 & 0xFF)).toInt();
    final color = img.ColorRgba8(r, g, b, 0xFF);
    for (int x = 0; x < w; x++) {
      im.setPixel(x, y, color);
    }
  }
  final timeStr = '${ts.year}-${ts.month.toString().padLeft(2,'0')}-${ts.day.toString().padLeft(2,'0')} '
      '${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}:${ts.second.toString().padLeft(2,'0')}';
  img.drawString(
    im,
    '${params.appName}\nTEST #${params.seq}\n$timeStr',
    x: 60,
    y: 200,
    font: img.arial48,
    color: img.ColorRgba8(255, 255, 255, 255),
  );
  final basePng = Uint8List.fromList(img.encodePng(im));

  // 追加随机填充到目标大小
  Uint8List finalBytes;
  if (basePng.length >= targetBytes) {
    finalBytes = basePng;
  } else {
    final pad = Uint8List(targetBytes - basePng.length);
    for (int k = 0; k < pad.length; k++) {
      pad[k] = rnd.nextInt(256);
    }
    final bb = BytesBuilder();
    bb.add(basePng);
    bb.add(pad);
    finalBytes = bb.toBytes();
  }

  await file.writeAsBytes(finalBytes, flush: true);
  final size = await file.length();
  return <String, dynamic>{
    'filePath': file.path,
    'timestampMs': params.timestampMs,
    'fileSize': size,
    'packageName': params.packageName,
    'appName': params.appName,
  };
}
