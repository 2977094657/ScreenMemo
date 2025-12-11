import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../constants/user_settings_keys.dart';
import 'screenshot_database.dart';
import 'user_settings_service.dart';

class EmbeddingService {
  EmbeddingService._();

  static final EmbeddingService instance = EmbeddingService._();

  static const int _defaultMaxRequestMb = 8;
  static const int _defaultMaxSamplesPerRequest = 32;
  static const String _defaultBaseUrl = 'https://ark.cn-beijing.volces.com/api/v3';
  static const String _defaultVisionModel = 'doubao-embedding-vision-250615';
  static const int _defaultDimensions = 2048;

  Future<int> getMaxRequestMb() async {
    final int value = await UserSettingsService.instance.getInt(
      UserSettingKeys.embeddingMaxRequestMb,
      defaultValue: _defaultMaxRequestMb,
    );
    if (value <= 0) {
      return _defaultMaxRequestMb;
    }
    return value;
  }

  Future<void> setMaxRequestMb(int mb) async {
    int clamped = mb;
    if (clamped < 1) {
      clamped = 1;
    } else if (clamped > 64) {
      clamped = 64;
    }
    await UserSettingsService.instance.setInt(
      UserSettingKeys.embeddingMaxRequestMb,
      clamped,
    );
  }

  Future<int> maxRequestBytes() async {
    final int mb = await getMaxRequestMb();
    return mb * 1024 * 1024;
  }

  int get defaultMaxSamplesPerRequest => _defaultMaxSamplesPerRequest;

  Future<void> embedAndSaveSample({
    required int sampleId,
    required int segmentId,
    required String filePath,
    required String apiKey,
    String? model,
    String? baseUrl,
    int? dimensions,
    String? modelVersionOverride,
  }) async {
    final List<double> embedding = await embedImageFile(
      filePath: filePath,
      apiKey: apiKey,
      model: model,
      baseUrl: baseUrl,
      dimensions: dimensions,
    );
    final String modelVersion = modelVersionOverride ?? (model ?? _defaultVisionModel);
    await ScreenshotDatabase.instance.saveEmbeddingForSample(
      sampleId: sampleId,
      segmentId: segmentId,
      embedding: embedding,
      modelVersion: modelVersion,
    );
  }

  Future<List<double>> embedImageFile({
    required String filePath,
    required String apiKey,
    String? model,
    String? baseUrl,
    int? dimensions,
  }) async {
    final File file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    final int fileSize = await file.length();
    final int limit = await maxRequestBytes();
    if (fileSize > limit) {
      throw Exception('Embedding request file too large: $fileSize bytes > limit $limit');
    }

    final Uint8List bytes = await file.readAsBytes();
    final String ext = p.extension(filePath).toLowerCase();
    final String mime = _detectImageMime(ext);
    final String b64 = base64Encode(bytes);
    final String dataUrl = 'data:$mime;base64,$b64';

    final String effectiveBase = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl);
    final Uri uri = Uri.parse('$effectiveBase/embeddings/multimodal');

    final Map<String, Object?> body = <String, Object?>{
      'model': model ?? _defaultVisionModel,
      'encoding_format': 'float',
      'input': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{
            'url': dataUrl,
          },
        },
      ],
      'dimensions': dimensions ?? _defaultDimensions,
    };

    final http.Response resp = await http.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Embedding request failed: ${resp.statusCode} ${resp.body}');
    }

    final Object decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, Object?>) {
      throw Exception('Invalid embedding response shape');
    }
    final Object? dataObj = decoded['data'];
    if (dataObj is! Map<String, Object?>) {
      throw Exception('Invalid embedding data field');
    }
    final Object? embObj = dataObj['embedding'];
    if (embObj is! List) {
      throw Exception('Invalid embedding vector field');
    }
    final List<double> out = <double>[];
    for (final Object? v in embObj) {
      if (v is num) {
        out.add(v.toDouble());
      }
    }
    if (out.isEmpty) {
      throw Exception('Empty embedding vector');
    }
    return out;
  }

  String _normalizeBaseUrl(String value) {
    String s = value.trim();
    if (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  String _detectImageMime(String ext) {
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      default:
        return 'image/png';
    }
  }
}
