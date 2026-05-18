import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/data/database/screenshot_database.dart';
import 'package:screen_memo/data/platform/path_service.dart';
import 'package:screen_memo/features/ai/application/ai_providers_service.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';

const String kAiImageGenerationContext = 'image_generation';
const int kAiImageGenerationMaxCount = 10;
const int kAiImageEditMaxReferenceImages = 16;
const int kAiImageEditMaxReferenceEdge = 2048;

class AIImageGenerationParams {
  const AIImageGenerationParams({
    required this.prompt,
    this.count = 1,
    this.aspectRatio = 'square',
    this.quality = 'medium',
    this.outputFormat = 'png',
    this.referenceImagePaths = const <String>[],
  });

  final String prompt;
  final int count;
  final String aspectRatio;
  final String quality;
  final String outputFormat;
  final List<String> referenceImagePaths;

  AIImageGenerationParams normalized() => AIImageGenerationParams(
    prompt: prompt.trim(),
    count: normalizeCount(count),
    aspectRatio: normalizeAspectRatio(aspectRatio),
    quality: normalizeQuality(quality),
    outputFormat: normalizeOutputFormat(outputFormat),
    referenceImagePaths: normalizeReferenceImagePaths(referenceImagePaths),
  );

  String get size => sizeForAspectRatio(aspectRatio);

  bool get hasReferenceImages => referenceImagePaths.isNotEmpty;

  static AIImageGenerationParams fromJson(Map<String, dynamic> json) {
    return AIImageGenerationParams(
      prompt: (json['prompt'] ?? '').toString(),
      count: normalizeCount(json['count']),
      aspectRatio: normalizeAspectRatio(json['aspect_ratio']),
      quality: normalizeQuality(json['quality']),
      outputFormat: normalizeOutputFormat(json['output_format']),
      referenceImagePaths: normalizeReferenceImagePaths(
        json['reference_image_paths'] ?? json['referenceImagePaths'],
      ),
    ).normalized();
  }

  static int normalizeCount(Object? raw) {
    int value;
    if (raw is int) {
      value = raw;
    } else if (raw is num) {
      value = raw.toInt();
    } else {
      value = int.tryParse(raw?.toString().trim() ?? '') ?? 1;
    }
    return value.clamp(1, kAiImageGenerationMaxCount).toInt();
  }

  static String normalizeAspectRatio(Object? raw) {
    final String value = (raw ?? '').toString().trim().toLowerCase();
    switch (value) {
      case 'portrait':
      case 'vertical':
      case 'tall':
      case '1024x1536':
        return 'portrait';
      case 'landscape':
      case 'horizontal':
      case 'wide':
      case '1536x1024':
        return 'landscape';
      default:
        return 'square';
    }
  }

  static String sizeForAspectRatio(String aspectRatio) {
    switch (normalizeAspectRatio(aspectRatio)) {
      case 'portrait':
        return '1024x1536';
      case 'landscape':
        return '1536x1024';
      default:
        return '1024x1024';
    }
  }

  static String normalizeQuality(Object? raw) {
    final String value = (raw ?? '').toString().trim().toLowerCase();
    switch (value) {
      case 'low':
      case 'medium':
      case 'high':
      case 'auto':
        return value;
      default:
        return 'medium';
    }
  }

  static String normalizeOutputFormat(Object? raw) {
    final String value = (raw ?? '').toString().trim().toLowerCase();
    switch (value) {
      case 'jpg':
      case 'jpeg':
        return 'jpeg';
      case 'webp':
        return 'webp';
      default:
        return 'png';
    }
  }

  static List<String> normalizeReferenceImagePaths(Object? raw) {
    final List<String> values = <String>[];
    if (raw is Iterable) {
      for (final Object? item in raw) {
        final String path = (item ?? '').toString().trim();
        if (path.isNotEmpty) values.add(path);
      }
    } else {
      final String path = (raw ?? '').toString().trim();
      if (path.isNotEmpty) values.add(path);
    }
    return <String>{...values}.take(kAiImageEditMaxReferenceImages).toList();
  }
}

class AIImageGenerationResult {
  const AIImageGenerationResult({
    required this.ok,
    required this.images,
    this.error,
    this.normalized,
    this.model,
    this.providerId,
    this.partial = false,
  });

  final bool ok;
  final List<Map<String, dynamic>> images;
  final String? error;
  final AIImageGenerationParams? normalized;
  final String? model;
  final int? providerId;
  final bool partial;

  Map<String, dynamic> toToolJson() {
    return <String, dynamic>{
      'tool': 'generate_image',
      'ok': ok,
      if (partial) 'partial': true,
      if (error != null && error!.trim().isNotEmpty) 'error': error,
      if (normalized != null)
        'normalized': <String, dynamic>{
          'count': normalized!.count,
          'aspect_ratio': normalized!.aspectRatio,
          'size': normalized!.size,
          'quality': normalized!.quality,
          'output_format': normalized!.outputFormat,
        },
      if (model != null && model!.trim().isNotEmpty) 'model': model,
      if (providerId != null) 'provider_id': providerId,
      'count': images.length,
      'images': images,
      if (images.isNotEmpty)
        'markers': images
            .map((e) => (e['marker'] ?? '').toString())
            .where((e) => e.trim().isNotEmpty)
            .toList(growable: false),
      if (images.isNotEmpty)
        'note':
            'The assistant should include each marker in the final answer to display generated images.',
    };
  }
}

class AIImageGenerationService {
  AIImageGenerationService._();

  static final AIImageGenerationService instance = AIImageGenerationService._();

  final AISettingsService _settings = AISettingsService.instance;
  final http.Client _client = http.Client();

  static Uri buildImagesGenerationsUri(String baseUrl) {
    final String trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      return Uri.parse('https://api.openai.com/v1/images/generations');
    }
    final Uri base = Uri.parse(trimmed);
    final String path = base.path.trim();
    final String normalizedPath = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final String nextPath = normalizedPath.endsWith('/v1')
        ? '$normalizedPath/images/generations'
        : '$normalizedPath/v1/images/generations';
    return base.replace(path: nextPath);
  }

  static Uri buildImagesEditsUri(String baseUrl) {
    final String trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      return Uri.parse('https://api.openai.com/v1/images/edits');
    }
    final Uri base = Uri.parse(trimmed);
    final String path = base.path.trim();
    final String normalizedPath = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final String nextPath = normalizedPath.endsWith('/v1')
        ? '$normalizedPath/images/edits'
        : '$normalizedPath/v1/images/edits';
    return base.replace(path: nextPath);
  }

  Future<AIImageGenerationResult> generate({
    required AIImageGenerationParams params,
    required String conversationId,
    required int? assistantCreatedAtMs,
    required String toolCallId,
  }) async {
    final AIImageGenerationParams normalized = params.normalized();
    if (normalized.prompt.isEmpty) {
      return AIImageGenerationResult(
        ok: false,
        images: const <Map<String, dynamic>>[],
        error: 'Missing required prompt.',
        normalized: normalized,
      );
    }

    final List<AIEndpoint> endpoints = await _settings.getEndpointCandidates(
      context: kAiImageGenerationContext,
    );
    unawaited(
      FlutterLogger.nativeInfo(
        'AI_IMAGE',
        'generate.start call=$toolCallId promptLen=${normalized.prompt.length} count=${normalized.count} size=${normalized.size} quality=${normalized.quality} format=${normalized.outputFormat} refs=${normalized.referenceImagePaths.length} endpoints=${endpoints.length} cid=$conversationId assistantAt=$assistantCreatedAtMs',
      ),
    );
    if (endpoints.isEmpty) {
      unawaited(
        FlutterLogger.nativeWarn(
          'AI_IMAGE',
          'generate.no_context call=$toolCallId context=$kAiImageGenerationContext',
        ),
      );
      return AIImageGenerationResult(
        ok: false,
        images: const <Map<String, dynamic>>[],
        error:
            'Image generation model is not configured. Configure the image_generation AI context first.',
        normalized: normalized,
      );
    }

    final AIEndpoint endpoint = endpoints.first;
    try {
      unawaited(
        FlutterLogger.nativeInfo(
          'AI_IMAGE',
          'generate.endpoint.begin call=$toolCallId provider=${endpoint.providerId} model=${endpoint.model} baseUrl=${endpoint.baseUrl} endpointCount=${endpoints.length} retry=disabled',
        ),
      );
      final AIImageGenerationResult result = await _generateWithEndpoint(
        endpoint: endpoint,
        params: normalized,
        conversationId: conversationId,
        assistantCreatedAtMs: assistantCreatedAtMs,
        toolCallId: toolCallId,
      );
      unawaited(_markEndpointSuccess(endpoint).catchError((_) {}));
      unawaited(
        FlutterLogger.nativeInfo(
          'AI_IMAGE',
          'generate.endpoint.success call=$toolCallId images=${result.images.length} partial=${result.partial} model=${result.model} provider=${result.providerId}',
        ),
      );
      return result;
    } catch (e) {
      await _markEndpointFailure(endpoint: endpoint, error: e);
      try {
        await FlutterLogger.nativeWarn(
          'AI_IMAGE',
          'image generation endpoint failed without retry: ${endpoint.baseUrl} $e',
        );
      } catch (_) {}
      final Exception lastError = e is Exception ? e : Exception(e.toString());
      return AIImageGenerationResult(
        ok: false,
        images: const <Map<String, dynamic>>[],
        error: _cleanError(lastError.toString()),
        normalized: normalized,
        model: endpoint.model,
        providerId: endpoint.providerId,
      );
    }
  }

  Future<AIImageGenerationResult> _generateWithEndpoint({
    required AIEndpoint endpoint,
    required AIImageGenerationParams params,
    required String conversationId,
    required int? assistantCreatedAtMs,
    required String toolCallId,
  }) async {
    final String? apiKey = endpoint.apiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Image generation API key is missing.');
    }
    if (params.hasReferenceImages) {
      return _editWithEndpoint(
        endpoint: endpoint,
        params: params,
        conversationId: conversationId,
        assistantCreatedAtMs: assistantCreatedAtMs,
        toolCallId: toolCallId,
        apiKey: apiKey,
      );
    }
    final Uri uri = buildImagesGenerationsUri(endpoint.baseUrl);
    final Map<String, Object?> body = <String, Object?>{
      'model': endpoint.model,
      'prompt': params.prompt,
      'n': params.count,
      'size': params.size,
      'quality': params.quality,
      'output_format': params.outputFormat,
      'response_format': 'b64_json',
    };
    unawaited(
      FlutterLogger.nativeInfo(
        'AI_IMAGE',
        'http.request call=$toolCallId uri=$uri model=${endpoint.model} n=${params.count} size=${params.size} quality=${params.quality} format=${params.outputFormat}',
      ),
    );
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    unawaited(
      FlutterLogger.nativeInfo(
        'AI_IMAGE',
        'http.response call=$toolCallId status=${response.statusCode} bytes=${response.bodyBytes.length}',
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Image generation request failed: ${response.statusCode} ${_clip(response.body, 800)}',
      );
    }

    final Map<String, dynamic> obj = _decodeImageResponseObject(
      response.body,
      invalidJsonMessage: 'Image generation response is not valid JSON.',
      invalidObjectMessage: 'Image generation response is not an object.',
    );
    return _persistImageResponse(
      endpoint: endpoint,
      params: params,
      conversationId: conversationId,
      assistantCreatedAtMs: assistantCreatedAtMs,
      toolCallId: toolCallId,
      obj: obj,
    );
  }

  Future<AIImageGenerationResult> _editWithEndpoint({
    required AIEndpoint endpoint,
    required AIImageGenerationParams params,
    required String conversationId,
    required int? assistantCreatedAtMs,
    required String toolCallId,
    required String apiKey,
  }) async {
    final List<_PreparedEditImage> references = <_PreparedEditImage>[];
    for (final String path in params.referenceImagePaths) {
      references.add(await _prepareReferenceImage(path));
    }
    if (references.isEmpty) {
      throw Exception('At least one reference image is required.');
    }

    final Uri uri = buildImagesEditsUri(endpoint.baseUrl);
    final http.MultipartRequest request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = endpoint.model
      ..fields['prompt'] = params.prompt
      ..fields['n'] = params.count.toString()
      ..fields['size'] = params.size
      ..fields['quality'] = params.quality
      ..fields['output_format'] = params.outputFormat
      ..fields['response_format'] = 'b64_json';

    final String imageFieldName = references.length == 1 ? 'image' : 'image[]';
    for (int i = 0; i < references.length; i += 1) {
      final _PreparedEditImage ref = references[i];
      request.files.add(
        http.MultipartFile.fromBytes(
          imageFieldName,
          ref.bytes,
          filename: ref.fileName,
          contentType: MediaType.parse(ref.mimeType),
        ),
      );
    }

    unawaited(
      FlutterLogger.nativeInfo(
        'AI_IMAGE',
        'http.edit.request call=$toolCallId uri=$uri model=${endpoint.model} refs=${references.length} n=${params.count} size=${params.size} quality=${params.quality} format=${params.outputFormat}',
      ),
    );

    final http.StreamedResponse streamed = await _client.send(request);
    final http.Response response = await http.Response.fromStream(streamed);
    unawaited(
      FlutterLogger.nativeInfo(
        'AI_IMAGE',
        'http.edit.response call=$toolCallId status=${response.statusCode} bytes=${response.bodyBytes.length}',
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Image edit request failed: ${response.statusCode} ${_clip(response.body, 800)}',
      );
    }

    final Map<String, dynamic> obj = _decodeImageResponseObject(
      response.body,
      invalidJsonMessage: 'Image edit response is not valid JSON.',
      invalidObjectMessage: 'Image edit response is not an object.',
    );
    return _persistImageResponse(
      endpoint: endpoint,
      params: params,
      conversationId: conversationId,
      assistantCreatedAtMs: assistantCreatedAtMs,
      toolCallId: toolCallId,
      obj: obj,
    );
  }

  Map<String, dynamic> _decodeImageResponseObject(
    String body, {
    required String invalidJsonMessage,
    required String invalidObjectMessage,
  }) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw Exception(invalidJsonMessage);
    }
    if (decoded is! Map) {
      throw Exception(invalidObjectMessage);
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<AIImageGenerationResult> _persistImageResponse({
    required AIEndpoint endpoint,
    required AIImageGenerationParams params,
    required String conversationId,
    required int? assistantCreatedAtMs,
    required String toolCallId,
    required Map<String, dynamic> obj,
  }) async {
    final dynamic dataRaw = obj['data'];
    if (dataRaw is! List || dataRaw.isEmpty) {
      throw Exception('Image generation response is missing data.');
    }

    final Directory dir = await _resolveOutputDir();
    unawaited(
      FlutterLogger.nativeInfo(
        'AI_IMAGE',
        'decode.output_dir call=$toolCallId dir=${dir.path} dataCount=${dataRaw.length}',
      ),
    );
    final String usageJson = _extractUsageJson(obj);
    final List<Map<String, dynamic>> images = <Map<String, dynamic>>[];
    final int createdAt = DateTime.now().millisecondsSinceEpoch;
    try {
      for (int i = 0; i < dataRaw.length; i += 1) {
        final dynamic itemRaw = dataRaw[i];
        if (itemRaw is! Map) {
          throw Exception('Image generation data item is not an object.');
        }
        final Map<String, dynamic> item = Map<String, dynamic>.from(itemRaw);
        final Uint8List bytes = await _decodeImageItemBytes(item);
        unawaited(
          FlutterLogger.nativeInfo(
            'AI_IMAGE',
            'decode.item call=$toolCallId index=$i bytes=${bytes.length} keys=${item.keys.join(",")}',
          ),
        );
        if (bytes.isEmpty) {
          throw Exception('Image generation returned an empty image.');
        }
        final String fileName = _buildFileName(
          createdAt: createdAt,
          toolCallId: toolCallId,
          index: i,
          outputFormat: params.outputFormat,
        );
        final File file = File(p.join(dir.path, fileName));
        try {
          await file.writeAsBytes(bytes, flush: true);
          final bool existsAfterWrite = await file.exists();
          final int fileBytes = existsAfterWrite ? await file.length() : -1;
          unawaited(
            FlutterLogger.nativeInfo(
              'AI_IMAGE',
              'file.write call=$toolCallId index=$i file=$fileName path=${file.path} exists=$existsAfterWrite bytes=$fileBytes',
            ),
          );
        } catch (e) {
          unawaited(
            FlutterLogger.nativeError(
              'AI_IMAGE',
              'file.write.error call=$toolCallId index=$i path=${file.path} err=$e',
            ),
          );
          throw Exception('Failed to write generated image file: $e');
        }

        final String mime = _mimeForOutputFormat(params.outputFormat);
        final int id = await ScreenshotDatabase.instance.insertAiGeneratedImage(
          conversationId: conversationId,
          assistantCreatedAt: assistantCreatedAtMs,
          toolCallId: toolCallId,
          prompt: params.prompt,
          model: endpoint.model,
          providerId: endpoint.providerId,
          filePath: file.path,
          mimeType: mime,
          size: params.size,
          quality: params.quality,
          outputFormat: params.outputFormat,
          usageJson: usageJson.isEmpty ? null : usageJson,
          createdAt: createdAt + i,
        );
        final String marker = '[generated-image: $fileName]';
        unawaited(
          FlutterLogger.nativeInfo(
            'AI_IMAGE',
            'db.insert call=$toolCallId index=$i id=$id marker=$marker file=$fileName path=${file.path}',
          ),
        );
        images.add(<String, dynamic>{
          'id': id,
          'filename': fileName,
          'file_path': file.path,
          'mime_type': mime,
          'bytes': bytes.length,
          'size': params.size,
          'quality': params.quality,
          'output_format': params.outputFormat,
          'marker': marker,
          if (params.hasReferenceImages)
            'reference_image_count': params.referenceImagePaths.length,
        });
      }
    } catch (e) {
      unawaited(
        FlutterLogger.nativeWarn(
          'AI_IMAGE',
          'generate.partial_or_error call=$toolCallId saved=${images.length} err=$e',
        ),
      );
      if (images.isEmpty) rethrow;
      return AIImageGenerationResult(
        ok: true,
        partial: true,
        error: _cleanError(e.toString()),
        images: images,
        normalized: params,
        model: endpoint.model,
        providerId: endpoint.providerId,
      );
    }

    return AIImageGenerationResult(
      ok: true,
      images: images,
      normalized: params,
      model: endpoint.model,
      providerId: endpoint.providerId,
    );
  }

  Future<Uint8List> _decodeImageItemBytes(Map<String, dynamic> item) async {
    final String b64 = (item['b64_json'] ?? '').toString().trim();
    if (b64.isNotEmpty) {
      return _decodeBase64ImageBytes(
        b64,
        invalidMessage: 'Image generation response contains invalid base64.',
      );
    }

    final String url = (item['url'] ?? '').toString().trim();
    if (url.startsWith('data:image/')) {
      final int comma = url.indexOf(',');
      if (comma <= 0 || comma >= url.length - 1) {
        throw Exception('Image generation response contains invalid data URL.');
      }
      return _decodeBase64ImageBytes(
        url.substring(comma + 1),
        invalidMessage:
            'Image generation response contains invalid data URL base64.',
      );
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final http.Response response = await _client.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Image generation URL download failed: ${response.statusCode}',
        );
      }
      return response.bodyBytes;
    }

    throw Exception(
      'Image generation response is missing b64_json or downloadable url.',
    );
  }

  Future<_PreparedEditImage> _prepareReferenceImage(String path) async {
    final File file = File(path.trim());
    if (!await file.exists()) {
      throw Exception('Reference image file does not exist.');
    }
    final Uint8List original = await file.readAsBytes();
    if (original.isEmpty) {
      throw Exception('Reference image file is empty.');
    }
    final img.Image? decoded = img.decodeImage(original);
    if (decoded == null) {
      throw Exception('Reference image format is not supported.');
    }
    img.Image normalized = img.bakeOrientation(decoded);
    final int longest = normalized.width > normalized.height
        ? normalized.width
        : normalized.height;
    if (longest > kAiImageEditMaxReferenceEdge) {
      normalized = img.copyResize(
        normalized,
        width: normalized.width >= normalized.height
            ? kAiImageEditMaxReferenceEdge
            : null,
        height: normalized.height > normalized.width
            ? kAiImageEditMaxReferenceEdge
            : null,
        interpolation: img.Interpolation.average,
      );
    }
    final Uint8List pngBytes = Uint8List.fromList(img.encodePng(normalized));
    final String stem = p
        .basenameWithoutExtension(file.path)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return _PreparedEditImage(
      fileName: '${stem.isEmpty ? 'reference' : stem}.png',
      mimeType: 'image/png',
      bytes: pngBytes,
    );
  }

  Uint8List _decodeBase64ImageBytes(
    String value, {
    required String invalidMessage,
  }) {
    try {
      return base64Decode(value.trim());
    } catch (_) {
      throw Exception(invalidMessage);
    }
  }

  Future<Directory> _resolveOutputDir() async {
    final DateTime now = DateTime.now();
    final String month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final Directory? dir = await PathService.getInternalAppDir(
      'output/ai/generated_images/$month',
    );
    if (dir == null) {
      throw Exception('Failed to resolve generated image output directory.');
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _buildFileName({
    required int createdAt,
    required String toolCallId,
    required int index,
    required String outputFormat,
  }) {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    final String ts =
        '${dt.year}${two(dt.month)}${two(dt.day)}_${two(dt.hour)}${two(dt.minute)}${two(dt.second)}_${three(dt.millisecond)}';
    final String safeCall = toolCallId
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final String ext = outputFormat == 'jpeg' ? 'jpg' : outputFormat;
    return '${ts}_${safeCall.isEmpty ? 'tool' : safeCall}_${index + 1}.$ext';
  }

  String _mimeForOutputFormat(String outputFormat) {
    switch (outputFormat) {
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/png';
    }
  }

  String _extractUsageJson(Map<String, dynamic> obj) {
    final Object? usage = obj['usage'];
    if (usage == null) return '';
    try {
      return jsonEncode(usage);
    } catch (_) {
      return '';
    }
  }

  Future<void> _markEndpointSuccess(AIEndpoint endpoint) async {
    final int? keyId = endpoint.providerKeyId;
    if (keyId == null) return;
    await AIProvidersService.instance.markProviderKeySuccess(keyId);
  }

  Future<void> _markEndpointFailure({
    required AIEndpoint endpoint,
    required Object error,
  }) async {
    final int? keyId = endpoint.providerKeyId;
    if (keyId == null) return;
    final String text = error.toString().toLowerCase();
    final String errorType =
        text.contains('401') || text.contains('403') || text.contains('api key')
        ? 'auth_failed'
        : 'retryable';
    await AIProvidersService.instance.markProviderKeyFailure(
      keyId: keyId,
      errorType: errorType,
      errorMessage: _cleanError(error.toString()),
      incrementFailure: errorType == 'retryable',
      resetFailureCount: errorType == 'auth_failed',
    );
  }

  String _cleanError(String value) {
    final String t = value.trim();
    if (t.startsWith('Exception: ')) return t.substring('Exception: '.length);
    return t;
  }

  String _clip(String text, int maxChars) {
    final String t = text.trim();
    if (t.length <= maxChars) return t;
    return '${t.substring(0, maxChars)}...';
  }
}

class _PreparedEditImage {
  const _PreparedEditImage({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}
