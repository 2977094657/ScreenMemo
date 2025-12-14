import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../constants/user_settings_keys.dart';
import 'ai_providers_service.dart';
import 'screenshot_database.dart';
import 'user_settings_service.dart';

class EmbeddingResolvedConfig {
  final String requestedContext;
  final String usedContext;
  final int? providerId;
  final String? providerName;
  final String apiKey;
  final String baseUrl;
  final String model;

  const EmbeddingResolvedConfig({
    required this.requestedContext,
    required this.usedContext,
    required this.providerId,
    required this.providerName,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });
}

class EmbeddingBackfillResult {
  final EmbeddingResolvedConfig config;
  final int total;
  final int attempted;
  final int writeOk;
  final int writeFail;
  final int skippedMissingFile;
  final int skippedInvalidRow;
  final int verifyOk;
  final int verifyFail;
  final List<String> previews;
  final List<String> errors;

  const EmbeddingBackfillResult({
    required this.config,
    required this.total,
    required this.attempted,
    required this.writeOk,
    required this.writeFail,
    required this.skippedMissingFile,
    required this.skippedInvalidRow,
    required this.verifyOk,
    required this.verifyFail,
    required this.previews,
    required this.errors,
  });
}

class _EncodedImageInput {
  final String filePath;
  final String dataUrl;

  const _EncodedImageInput({
    required this.filePath,
    required this.dataUrl,
  });
}

class EmbeddingService {
  EmbeddingService._();

  static final EmbeddingService instance = EmbeddingService._();

  // 默认单次请求体积上限（MB）。用于估算 jsonEncode 后的请求体大小（含 base64），避免 413/超时。
  static const int _defaultMaxRequestMb = 3;
  static const int _defaultMaxSamplesPerRequest = 32;
  static const String _defaultBaseUrl = 'https://ark.cn-beijing.volces.com/api/v3';
  static const String _defaultVisionModel = 'doubao-embedding-vision-250615';
  static const int _defaultDimensions = 2048;
  static const String _defaultContext = 'embedding';
  static const List<String> _fallbackContexts = <String>[
    'embedding',
    'segments',
    'chat',
  ];

  // 单次运行内的“批量不支持”探测结果：一旦确认不支持，则直接回退逐图，避免反复失败。
  bool _multiImageBatchUnsupported = false;

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

  Future<EmbeddingResolvedConfig> resolveEmbeddingConfig({
    String context = _defaultContext,
    String? apiKeyOverride,
    String? baseUrlOverride,
    String? modelOverride,
  }) async {
    final String trimmedKey = (apiKeyOverride ?? '').trim();
    final String trimmedBase = (baseUrlOverride ?? '').trim();
    final String trimmedModel = (modelOverride ?? '').trim();

    Map<String, dynamic>? ctxRow;
    String usedContext = context;
    final List<String> scan = <String>[context, ..._fallbackContexts]
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    for (final String c in scan) {
      final Map<String, dynamic>? row = await ScreenshotDatabase.instance.getAIContext(c);
      if (row != null) {
        ctxRow = row;
        usedContext = c;
        break;
      }
    }

    int? providerId;
    if (ctxRow != null && ctxRow['provider_id'] is int) {
      providerId = ctxRow['provider_id'] as int;
    }

    AIProvider? provider;
    if (providerId != null) {
      provider = await AIProvidersService.instance.getProvider(providerId);
    }
    provider ??= await AIProvidersService.instance.getDefaultProvider();
    providerId ??= provider?.id;

    String? apiKey;
    if (providerId != null) {
      apiKey = await AIProvidersService.instance.getApiKey(providerId);
    }
    apiKey = (apiKey ?? '').trim();
    if (trimmedKey.isNotEmpty) {
      apiKey = trimmedKey;
    }
    if (apiKey.isEmpty) {
      throw Exception('Missing API key for embedding context');
    }

    String baseUrl = trimmedBase;
    if (baseUrl.isEmpty) {
      baseUrl = (provider?.baseUrl ?? '').trim();
    }
    if (baseUrl.isEmpty) {
      baseUrl = _defaultBaseUrl;
    }

    String model = trimmedModel;
    if (model.isEmpty && ctxRow != null) {
      model = (ctxRow['model'] as String?)?.trim() ?? '';
    }
    if (model.isEmpty) {
      model = ((provider?.extra['active_model'] as String?) ?? '').trim();
    }
    if (model.isEmpty) {
      model = (provider?.defaultModel ?? '').trim();
    }
    if (model.isEmpty && (provider?.models ?? const <String>[]).isNotEmpty) {
      model = provider!.models.first.trim();
    }
    if (model.isEmpty) {
      model = _defaultVisionModel;
    }

    return EmbeddingResolvedConfig(
      requestedContext: context,
      usedContext: usedContext,
      providerId: providerId,
      providerName: provider?.name,
      apiKey: apiKey,
      baseUrl: _normalizeBaseUrl(baseUrl),
      model: model,
    );
  }

  Future<List<double>> embedImageFileWithContext({
    required String filePath,
    String context = _defaultContext,
    String? apiKeyOverride,
    String? baseUrlOverride,
    String? modelOverride,
    int? dimensions,
  }) async {
    final EmbeddingResolvedConfig cfg = await resolveEmbeddingConfig(
      context: context,
      apiKeyOverride: apiKeyOverride,
      baseUrlOverride: baseUrlOverride,
      modelOverride: modelOverride,
    );
    return await embedImageFile(
      filePath: filePath,
      apiKey: cfg.apiKey,
      baseUrl: cfg.baseUrl,
      model: cfg.model,
      dimensions: dimensions,
    );
  }

  Future<List<double>> embedTextWithContext({
    required String text,
    String context = _defaultContext,
    String? apiKeyOverride,
    String? baseUrlOverride,
    String? modelOverride,
    int? dimensions,
  }) async {
    final EmbeddingResolvedConfig cfg = await resolveEmbeddingConfig(
      context: context,
      apiKeyOverride: apiKeyOverride,
      baseUrlOverride: baseUrlOverride,
      modelOverride: modelOverride,
    );
    return await embedText(
      text: text,
      apiKey: cfg.apiKey,
      baseUrl: cfg.baseUrl,
      model: cfg.model,
      dimensions: dimensions,
    );
  }

  Future<List<double>> embedText({
    required String text,
    required String apiKey,
    String? model,
    String? baseUrl,
    int? dimensions,
  }) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw Exception('Embedding text is empty');
    }

    final Uri uri = _buildEmbeddingsUri(baseUrl ?? _defaultBaseUrl);
    final int limitBytes = await maxRequestBytes();
    final Map<String, Object?> body = <String, Object?>{
      'model': model ?? _defaultVisionModel,
      'encoding_format': 'float',
      'input': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'text',
          'text': trimmed,
        },
      ],
      'dimensions': dimensions ?? _defaultDimensions,
    };

    final http.Response resp = await _postEmbeddingsRaw(
      uri: uri,
      apiKey: apiKey,
      body: body,
      limitBytesOverride: limitBytes,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Embedding request failed: ${resp.statusCode} ${resp.body}');
    }

    final List<List<double>> vectors = _parseEmbeddingsFromResponse(resp.body);
    if (vectors.isEmpty || vectors.first.isEmpty) {
      throw Exception('Empty embedding vector');
    }
    return vectors.first;
  }

  /// 尝试“单次请求多图”；若不支持或失败，则自动回退为逐图请求。
  /// 注意：多模态向量化 API 文档未承诺“多图批量”必可用，因此此方法是 best-effort。
  Future<List<List<double>>> embedImageFilesBatchBestEffortWithContext({
    required List<String> filePaths,
    String context = _defaultContext,
    String? apiKeyOverride,
    String? baseUrlOverride,
    String? modelOverride,
    int? dimensions,
    int maxImagesPerRequest = 30,
    int? maxRequestBytesOverride,
    bool tryMultiImageRequest = true,
  }) async {
    final EmbeddingResolvedConfig cfg = await resolveEmbeddingConfig(
      context: context,
      apiKeyOverride: apiKeyOverride,
      baseUrlOverride: baseUrlOverride,
      modelOverride: modelOverride,
    );
    return await embedImageFilesBatchBestEffort(
      filePaths: filePaths,
      apiKey: cfg.apiKey,
      baseUrl: cfg.baseUrl,
      model: cfg.model,
      dimensions: dimensions,
      maxImagesPerRequest: maxImagesPerRequest,
      maxRequestBytesOverride: maxRequestBytesOverride,
      tryMultiImageRequest: tryMultiImageRequest,
    );
  }

  /// 尝试“单次请求多图”；若不支持或失败，则自动回退为逐图请求。
  /// - maxImagesPerRequest: 单次请求最多图片数（默认 30）。
  /// - maxRequestBytesOverride: 单次请求体积上限（字节）。如不传则使用用户设置。
  /// - tryMultiImageRequest: 允许尝试多图请求。
  Future<List<List<double>>> embedImageFilesBatchBestEffort({
    required List<String> filePaths,
    required String apiKey,
    String? model,
    String? baseUrl,
    int? dimensions,
    int maxImagesPerRequest = 30,
    int? maxRequestBytesOverride,
    bool tryMultiImageRequest = true,
  }) async {
    if (filePaths.isEmpty) return const <List<double>>[];

    final String effectiveBase = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl);
    final Uri uri = _buildEmbeddingsUri(effectiveBase);
    final String usedModel = model ?? _defaultVisionModel;
    final int usedDimensions = dimensions ?? _defaultDimensions;
    final int limitBytes = maxRequestBytesOverride ?? await maxRequestBytes();
    final int maxPerReq = maxImagesPerRequest <= 0 ? 1 : maxImagesPerRequest;

    // 不尝试多图：直接逐图
    if (!tryMultiImageRequest || _multiImageBatchUnsupported || filePaths.length < 2) {
      final List<List<double>> out = <List<double>>[];
      for (final String path in filePaths) {
        out.add(await embedImageFile(
          filePath: path,
          apiKey: apiKey,
          model: usedModel,
          baseUrl: effectiveBase,
          dimensions: usedDimensions,
        ));
      }
      return out;
    }

    final List<List<double>> results = <List<double>>[];
    int idx = 0;
    while (idx < filePaths.length) {
      int end = idx + maxPerReq;
      if (end > filePaths.length) end = filePaths.length;

      // 预编码（最多 maxPerReq 张）
      final List<_EncodedImageInput> encoded = <_EncodedImageInput>[];
      for (int i = idx; i < end; i++) {
        final String path = filePaths[i];
        final File file = File(path);
        if (!await file.exists()) {
          throw FileSystemException('File not found', path);
        }
        final Uint8List bytes = await file.readAsBytes();
        final String ext = p.extension(path).toLowerCase();
        final String mime = _detectImageMime(ext);
        final String b64 = base64Encode(bytes);
        final String dataUrl = 'data:$mime;base64,$b64';
        encoded.add(_EncodedImageInput(filePath: path, dataUrl: dataUrl));
      }

      // 根据 limitBytes 缩小本次多图请求的数量（至少保留 2 张才有“批量”意义）
      final List<_EncodedImageInput> batch = List<_EncodedImageInput>.from(encoded);
      while (batch.length > 1) {
        final Map<String, Object?> body = _buildMultiImageBody(
          model: usedModel,
          dimensions: usedDimensions,
          images: batch,
        );
        final String jsonBody = jsonEncode(body);
        final int bodyBytes = utf8.encode(jsonBody).length;
        if (bodyBytes <= limitBytes) break;
        batch.removeLast();
      }

      // 如果缩到只剩 1 张：直接逐图（只处理当前 idx，避免死循环）
      if (batch.length <= 1) {
        results.add(await embedImageFile(
          filePath: filePaths[idx],
          apiKey: apiKey,
          model: usedModel,
          baseUrl: effectiveBase,
          dimensions: usedDimensions,
        ));
        idx += 1;
        continue;
      }

      // 发送多图请求
      final Map<String, Object?> body = _buildMultiImageBody(
        model: usedModel,
        dimensions: usedDimensions,
        images: batch,
      );

      http.Response resp;
      try {
        resp = await _postEmbeddingsRaw(
          uri: uri,
          apiKey: apiKey,
          body: body,
          limitBytesOverride: limitBytes,
        );
      } catch (_) {
        // 本地 size 校验失败或其他编码问题：回退逐图
        for (final _EncodedImageInput item in batch) {
          results.add(await embedImageFile(
            filePath: item.filePath,
            apiKey: apiKey,
            model: usedModel,
            baseUrl: effectiveBase,
            dimensions: usedDimensions,
          ));
        }
        idx += batch.length;
        continue;
      }

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        // 400/422 常见于“input 不支持多段”，此时关闭本次运行内的多图尝试
        if (_isBatchUnsupportedResponse(resp.statusCode, resp.body)) {
          _multiImageBatchUnsupported = true;
        }
        for (final _EncodedImageInput item in batch) {
          results.add(await embedImageFile(
            filePath: item.filePath,
            apiKey: apiKey,
            model: usedModel,
            baseUrl: effectiveBase,
            dimensions: usedDimensions,
          ));
        }
        idx += batch.length;
        continue;
      }

      List<List<double>> vectors;
      try {
        vectors = _parseEmbeddingsFromResponse(resp.body);
      } catch (_) {
        _multiImageBatchUnsupported = true;
        for (final _EncodedImageInput item in batch) {
          results.add(await embedImageFile(
            filePath: item.filePath,
            apiKey: apiKey,
            model: usedModel,
            baseUrl: effectiveBase,
            dimensions: usedDimensions,
          ));
        }
        idx += batch.length;
        continue;
      }

      // 若返回向量数量不匹配，视为“不支持按输入条目返回多个向量”
      if (vectors.length != batch.length) {
        _multiImageBatchUnsupported = true;
        for (final _EncodedImageInput item in batch) {
          results.add(await embedImageFile(
            filePath: item.filePath,
            apiKey: apiKey,
            model: usedModel,
            baseUrl: effectiveBase,
            dimensions: usedDimensions,
          ));
        }
        idx += batch.length;
        continue;
      }

      results.addAll(vectors);
      idx += batch.length;
    }

    return results;
  }

  Future<void> embedAndSaveSampleWithContext({
    required int sampleId,
    required int segmentId,
    required String filePath,
    String context = _defaultContext,
    String? apiKeyOverride,
    String? baseUrlOverride,
    String? modelOverride,
    int? dimensions,
    String? modelVersionOverride,
  }) async {
    final EmbeddingResolvedConfig cfg = await resolveEmbeddingConfig(
      context: context,
      apiKeyOverride: apiKeyOverride,
      baseUrlOverride: baseUrlOverride,
      modelOverride: modelOverride,
    );
    await embedAndSaveSample(
      sampleId: sampleId,
      segmentId: segmentId,
      filePath: filePath,
      apiKey: cfg.apiKey,
      model: cfg.model,
      baseUrl: cfg.baseUrl,
      dimensions: dimensions,
      modelVersionOverride: modelVersionOverride,
    );
  }

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
    final int limitBytes = await maxRequestBytes();
    if (fileSize > limitBytes) {
      throw Exception('Embedding request file too large: $fileSize bytes > limit $limitBytes');
    }

    final Uint8List bytes = await file.readAsBytes();
    final String ext = p.extension(filePath).toLowerCase();
    final String mime = _detectImageMime(ext);
    final String b64 = base64Encode(bytes);
    final String dataUrl = 'data:$mime;base64,$b64';

    final Uri uri = _buildEmbeddingsUri(baseUrl ?? _defaultBaseUrl);

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

    final http.Response resp = await _postEmbeddingsRaw(
      uri: uri,
      apiKey: apiKey,
      body: body,
      limitBytesOverride: limitBytes,
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Embedding request failed: ${resp.statusCode} ${resp.body}');
    }

    final List<List<double>> vectors = _parseEmbeddingsFromResponse(resp.body);
    if (vectors.isEmpty || vectors.first.isEmpty) {
      throw Exception('Empty embedding vector');
    }
    return vectors.first;
  }

  Uri _buildEmbeddingsUri(String baseUrl) {
    final String effectiveBase = _normalizeBaseUrl(baseUrl);
    return Uri.parse('$effectiveBase/embeddings/multimodal');
  }

  Map<String, Object?> _buildMultiImageBody({
    required String model,
    required int dimensions,
    required List<_EncodedImageInput> images,
  }) {
    return <String, Object?>{
      'model': model,
      'encoding_format': 'float',
      'input': images
          .map(
            (e) => <String, Object?>{
              'type': 'image_url',
              'image_url': <String, Object?>{'url': e.dataUrl},
            },
          )
          .toList(),
      'dimensions': dimensions,
    };
  }

  Future<http.Response> _postEmbeddingsRaw({
    required Uri uri,
    required String apiKey,
    required Map<String, Object?> body,
    int? limitBytesOverride,
  }) async {
    final String jsonBody = jsonEncode(body);
    final int bodyBytes = utf8.encode(jsonBody).length;
    final int limit = limitBytesOverride ?? await maxRequestBytes();
    if (bodyBytes > limit) {
      throw Exception('Embedding request body too large: $bodyBytes bytes > limit $limit');
    }

    return await http.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonBody,
    );
  }

  List<List<double>> _parseEmbeddingsFromResponse(String body) {
    final Object decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw Exception('Invalid embedding response shape');
    }

    List<List<double>> vectors = _extractEmbeddings(decoded['data']);
    if (vectors.isNotEmpty) return vectors;

    vectors = _extractEmbeddings(decoded['embedding']);
    if (vectors.isNotEmpty) return vectors;

    vectors = _extractEmbeddings(decoded['embeddings']);
    if (vectors.isNotEmpty) return vectors;

    throw Exception('Invalid embedding vector field');
  }

  List<List<double>> _extractEmbeddings(Object? node) {
    if (node == null) return const <List<double>>[];

    if (node is Map) {
      final Object? direct = node['embedding'];
      final List<double> vec = _toVectorOrEmpty(direct);
      if (vec.isNotEmpty) return <List<double>>[vec];

      final Object? data = node['data'];
      final List<List<double>> nested = _extractEmbeddings(data);
      if (nested.isNotEmpty) return nested;

      final Object? embeddings = node['embeddings'];
      final List<List<double>> nested2 = _extractEmbeddings(embeddings);
      if (nested2.isNotEmpty) return nested2;

      return const <List<double>>[];
    }

    if (node is List) {
      // 形态1：直接是向量数组 [0.1, 0.2, ...]
      final List<double> direct = _toVectorOrEmpty(node);
      if (direct.isNotEmpty) return <List<double>>[direct];

      // 形态2：[{embedding:[...]}, {embedding:[...]}]
      final List<List<double>> out = <List<double>>[];
      for (final Object? item in node) {
        if (item is Map) {
          final List<double> vec = _toVectorOrEmpty(item['embedding']);
          if (vec.isNotEmpty) out.add(vec);
        } else if (item is List) {
          final List<double> vec = _toVectorOrEmpty(item);
          if (vec.isNotEmpty) out.add(vec);
        }
      }
      return out;
    }

    return const <List<double>>[];
  }

  List<double> _toVectorOrEmpty(Object? embObj) {
    if (embObj is! List) return const <double>[];
    final List<double> out = <double>[];
    for (final Object? v in embObj) {
      if (v is num) out.add(v.toDouble());
    }
    return out;
  }

  bool _isBatchUnsupportedResponse(int statusCode, String body) {
    if (statusCode != 400 && statusCode != 422) return false;
    final String low = body.toLowerCase();
    if (low.contains('not support') ||
        low.contains('unsupported') ||
        low.contains('only support') ||
        (low.contains('input') && low.contains('only'))) {
      return true;
    }
    return false;
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
