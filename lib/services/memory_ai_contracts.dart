import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'memory_entity_models.dart';

class MemoryAIImagePayload {
  const MemoryAIImagePayload({required this.label, required this.dataUrl});

  final String label;
  final String dataUrl;
}

class MemoryAIContracts {
  MemoryAIContracts._();

  static Future<String> readAsDataUrl(String path) async {
    final File file = File(path);
    if (!await file.exists()) {
      throw StateError('image not found: $path');
    }
    final Uint8List bytes = await file.readAsBytes();
    return dataUrlForBytes(bytes, mimeTypeForPath(path));
  }

  static String mimeTypeForPath(String path) {
    final String lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/png';
  }

  static String dataUrlForBytes(List<int> bytes, String mime) {
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  static Future<List<MemoryAIImagePayload>> buildVisualEvidencePayloads(
    String path, {
    required int batchSize,
  }) async {
    final File file = File(path);
    if (!await file.exists()) {
      throw StateError('image not found: $path');
    }
    final Uint8List bytes = await file.readAsBytes();
    final List<MemoryAIImagePayload> payloads = <MemoryAIImagePayload>[
      MemoryAIImagePayload(
        label: 'original',
        dataUrl: dataUrlForBytes(bytes, mimeTypeForPath(path)),
      ),
    ];
    try {
      payloads.addAll(
        await _buildDerivedCropPayloads(bytes, batchSize: batchSize),
      );
    } catch (_) {}
    return payloads;
  }

  static Future<List<Map<String, Object?>>> buildDossierApiParts({
    required String heading,
    required List<MemoryEntityDossier> dossiers,
    int maxImagesPerDossier = 2,
  }) async {
    final List<Map<String, Object?>> parts = <Map<String, Object?>>[
      <String, Object?>{'type': 'text', 'text': heading},
    ];
    for (int index = 0; index < dossiers.length; index += 1) {
      final MemoryEntityDossier dossier = dossiers[index];
      parts.add(<String, Object?>{
        'type': 'text',
        'text': jsonEncode(dossier.toJson(includeFilePaths: false)),
      });
      int attached = 0;
      for (final MemoryEntityExemplar exemplar in dossier.exemplars) {
        if (attached >= maxImagesPerDossier) break;
        final String path = exemplar.filePath.trim();
        if (path.isEmpty) continue;
        try {
          final String dataUrl = await readAsDataUrl(path);
          parts.add(<String, Object?>{
            'type': 'text',
            'text': 'dossier_index=$index exemplar_index=$attached',
          });
          parts.add(<String, Object?>{
            'type': 'image_url',
            'image_url': <String, Object?>{'url': dataUrl},
          });
          attached += 1;
        } catch (_) {}
      }
    }
    return parts;
  }

  static Future<List<Map<String, Object?>>> buildExemplarApiParts({
    required String heading,
    required List<MemoryEntityExemplar> exemplars,
    int maxImages = 3,
  }) async {
    final List<Map<String, Object?>> parts = <Map<String, Object?>>[
      <String, Object?>{'type': 'text', 'text': heading},
    ];
    int attached = 0;
    for (final MemoryEntityExemplar exemplar in exemplars) {
      if (attached >= maxImages) break;
      final String path = exemplar.filePath.trim();
      if (path.isEmpty) continue;
      try {
        final String dataUrl = await readAsDataUrl(path);
        parts.add(<String, Object?>{
          'type': 'text',
          'text': jsonEncode(exemplar.toJson(includeFilePath: false)),
        });
        parts.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{'url': dataUrl},
        });
        attached += 1;
      } catch (_) {}
    }
    return parts;
  }

  static Future<List<MemoryAIImagePayload>> _buildDerivedCropPayloads(
    Uint8List bytes, {
    required int batchSize,
  }) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image source = frame.image;
    final int width = source.width;
    final int height = source.height;
    if (width < 240 || height < 240) {
      return const <MemoryAIImagePayload>[];
    }

    final List<_CropVariant> variants = <_CropVariant>[
      const _CropVariant(
        label: 'focus_center',
        left: 0.12,
        top: 0.12,
        widthFactor: 0.76,
        heightFactor: 0.76,
      ),
      if (height >= width)
        const _CropVariant(
          label: 'focus_top',
          left: 0,
          top: 0,
          widthFactor: 1,
          heightFactor: 0.58,
        ),
      if (height >= width && batchSize <= 3)
        const _CropVariant(
          label: 'focus_bottom',
          left: 0,
          top: 0.42,
          widthFactor: 1,
          heightFactor: 0.58,
        ),
      if (width > height)
        const _CropVariant(
          label: 'focus_left',
          left: 0,
          top: 0,
          widthFactor: 0.6,
          heightFactor: 1,
        ),
    ];
    final int maxDerived = batchSize <= 2
        ? 3
        : batchSize <= 4
        ? 2
        : 1;

    final List<MemoryAIImagePayload> out = <MemoryAIImagePayload>[];
    for (final _CropVariant variant in variants.take(maxDerived)) {
      final ui.Image cropped = await _renderCrop(source, variant);
      final ByteData? bytesData = await cropped.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (bytesData == null) continue;
      out.add(
        MemoryAIImagePayload(
          label: variant.label,
          dataUrl: dataUrlForBytes(bytesData.buffer.asUint8List(), 'image/png'),
        ),
      );
    }
    return out;
  }

  static Future<ui.Image> _renderCrop(
    ui.Image source,
    _CropVariant variant,
  ) async {
    final int left = (source.width * variant.left)
        .round()
        .clamp(0, math.max(0, source.width - 1))
        .toInt();
    final int top = (source.height * variant.top)
        .round()
        .clamp(0, math.max(0, source.height - 1))
        .toInt();
    final int srcWidth = (source.width * variant.widthFactor)
        .round()
        .clamp(1, source.width - left)
        .toInt();
    final int srcHeight = (source.height * variant.heightFactor)
        .round()
        .clamp(1, source.height - top)
        .toInt();
    final double scale = math.min(
      1,
      1400 / math.max(srcWidth, srcHeight).toDouble(),
    );
    final int outWidth = math.max(1, (srcWidth * scale).round());
    final int outHeight = math.max(1, (srcHeight * scale).round());

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(
        left.toDouble(),
        top.toDouble(),
        srcWidth.toDouble(),
        srcHeight.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, outWidth.toDouble(), outHeight.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    final ui.Picture picture = recorder.endRecording();
    return picture.toImage(outWidth, outHeight);
  }
}

class _CropVariant {
  const _CropVariant({
    required this.label,
    required this.left,
    required this.top,
    required this.widthFactor,
    required this.heightFactor,
  });

  final String label;
  final double left;
  final double top;
  final double widthFactor;
  final double heightFactor;
}
