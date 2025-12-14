import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../constants/user_settings_keys.dart';
import '../services/embedding_service.dart';
import '../services/screenshot_database.dart';
import '../services/user_settings_service.dart';
import '../theme/app_theme.dart';

class _SemanticHit {
  final double score;
  final int sampleId;
  final int segmentId;
  final int captureTime;
  final String filePath;
  final String appName;

  const _SemanticHit({
    required this.score,
    required this.sampleId,
    required this.segmentId,
    required this.captureTime,
    required this.filePath,
    required this.appName,
  });
}

class EmbeddingDebugPage extends StatefulWidget {
  const EmbeddingDebugPage({super.key});

  @override
  State<EmbeddingDebugPage> createState() => _EmbeddingDebugPageState();
}

class _EmbeddingDebugPageState extends State<EmbeddingDebugPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _dimensionsController = TextEditingController(text: '2048');

  // 批量向量化（限制：仅最新窗口 ≤1000，按时间间隔抽样）
  final TextEditingController _embedBatchSizeController =
      TextEditingController(text: '1000');
  final TextEditingController _embedConcurrencyController =
      TextEditingController(text: '2');
  final TextEditingController _embedMaxImagesPerRequestController =
      TextEditingController(text: '20');
  final TextEditingController _embedIntervalSecondsController =
      TextEditingController(text: '30');
  final TextEditingController _embedMaxRequestMbController =
      TextEditingController(text: '3');
  bool _embedTryMultiImageRequest = true;
  bool _embedRunning = false;
  bool _embedCancelRequested = false;
  int _embedTotal = 0;
  int _embedProcessed = 0;
  int _embedOk = 0;
  int _embedFail = 0;
  int _embedSkippedMissingFile = 0;
  String _embedSummary = '';

  // 统计：在“最新窗口”内，已有向量 vs 总数
  bool _coverageLoading = false;
  int _coverageTotal = 0;
  int _coverageEmbedded = 0;

  // 语义搜索最小测试
  final TextEditingController _semanticQueryController = TextEditingController();
  final TextEditingController _semanticCandidateLimitController =
      TextEditingController(text: '1000');
  bool _semanticRunning = false;
  String _semanticSummary = '';
  List<_SemanticHit> _semanticHits = <_SemanticHit>[];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _restoreDebugUiState();
    await _loadEmbeddingSettings();
    await _refreshEmbeddingCoverage();
  }

  Future<void> _restoreDebugUiState() async {
    try {
      final String? apiKey = await UserSettingsService.instance.getString(
        UserSettingKeys.embeddingDebugApiKey,
      );
      final String? baseUrl = await UserSettingsService.instance.getString(
        UserSettingKeys.embeddingDebugBaseUrl,
      );
      final String? model = await UserSettingsService.instance.getString(
        UserSettingKeys.embeddingDebugModel,
      );
      final String? dims = await UserSettingsService.instance.getString(
        UserSettingKeys.embeddingDebugDimensions,
      );

      final String? embedBatch = await UserSettingsService.instance.getString(
        UserSettingKeys.embeddingDebugEmbeddingBatchSize,
      );
      final String? embedConc = await UserSettingsService.instance.getString(
        UserSettingKeys.embeddingDebugEmbeddingConcurrency,
      );
      final String? embedMaxImages = await UserSettingsService.instance.getString(
        UserSettingKeys.embeddingDebugEmbeddingMaxImagesPerRequest,
      );
      final String? embedIntervalSec = await UserSettingsService.instance.getString(
        UserSettingKeys.embeddingDebugEmbeddingIntervalSeconds,
      );
      final bool tryMulti = await UserSettingsService.instance.getBool(
        UserSettingKeys.embeddingDebugTryMultiImageRequest,
        defaultValue: true,
      );
      final String? semCandidates = await UserSettingsService.instance.getString(
        UserSettingKeys.embeddingDebugSemanticCandidateLimit,
      );

      if (!mounted) return;
      setState(() {
        if (apiKey != null) _apiKeyController.text = apiKey;
        _baseUrlController.text = (baseUrl == null || baseUrl.trim().isEmpty)
            ? 'https://ark.cn-beijing.volces.com/api/v3'
            : baseUrl.trim();
        _modelController.text = (model == null || model.trim().isEmpty)
            ? 'doubao-embedding-vision-250615'
            : model.trim();
        if (dims != null) _dimensionsController.text = dims.trim();
        if (embedBatch != null) _embedBatchSizeController.text = embedBatch.trim();
        if (embedConc != null) _embedConcurrencyController.text = embedConc.trim();
        if (embedMaxImages != null) _embedMaxImagesPerRequestController.text = embedMaxImages.trim();
        if (embedIntervalSec != null) _embedIntervalSecondsController.text = embedIntervalSec.trim();
        _embedTryMultiImageRequest = tryMulti;
        if (semCandidates != null) _semanticCandidateLimitController.text = semCandidates.trim();
      });
    } catch (_) {}
  }

  Future<void> _persistDebugUiState() async {
    String? normOrNull(String s) {
      final String t = s.trim();
      return t.isEmpty ? null : t;
    }

    try {
      await UserSettingsService.instance.setString(
        UserSettingKeys.embeddingDebugApiKey,
        normOrNull(_apiKeyController.text),
      );
      await UserSettingsService.instance.setString(
        UserSettingKeys.embeddingDebugBaseUrl,
        normOrNull(_baseUrlController.text),
      );
      await UserSettingsService.instance.setString(
        UserSettingKeys.embeddingDebugModel,
        normOrNull(_modelController.text),
      );
      await UserSettingsService.instance.setString(
        UserSettingKeys.embeddingDebugDimensions,
        normOrNull(_dimensionsController.text),
      );
      await UserSettingsService.instance.setString(
        UserSettingKeys.embeddingDebugEmbeddingBatchSize,
        normOrNull(_embedBatchSizeController.text),
      );
      await UserSettingsService.instance.setString(
        UserSettingKeys.embeddingDebugEmbeddingConcurrency,
        normOrNull(_embedConcurrencyController.text),
      );
      await UserSettingsService.instance.setString(
        UserSettingKeys.embeddingDebugEmbeddingMaxImagesPerRequest,
        normOrNull(_embedMaxImagesPerRequestController.text),
      );
      await UserSettingsService.instance.setString(
        UserSettingKeys.embeddingDebugEmbeddingIntervalSeconds,
        normOrNull(_embedIntervalSecondsController.text),
      );
      await UserSettingsService.instance.setBool(
        UserSettingKeys.embeddingDebugTryMultiImageRequest,
        _embedTryMultiImageRequest,
      );
      await UserSettingsService.instance.setString(
        UserSettingKeys.embeddingDebugSemanticCandidateLimit,
        normOrNull(_semanticCandidateLimitController.text),
      );
    } catch (_) {}
  }

  Future<void> _loadEmbeddingSettings() async {
    try {
      final int mb = await EmbeddingService.instance.getMaxRequestMb();
      if (!mounted) return;
      setState(() {
        _embedMaxRequestMbController.text = mb.toString();
      });
    } catch (_) {}
  }

  Future<void> _applyEmbeddingMaxRequestMb() async {
    final int? v = int.tryParse(_embedMaxRequestMbController.text.trim());
    if (v == null || v <= 0) {
      setState(() {
        _embedSummary = '请求体积上限（MB）无效';
      });
      return;
    }
    try {
      await EmbeddingService.instance.setMaxRequestMb(v);
      await _persistDebugUiState();
      final int mb = await EmbeddingService.instance.getMaxRequestMb();
      if (!mounted) return;
      setState(() {
        _embedMaxRequestMbController.text = mb.toString();
        _embedSummary = '已保存请求体积上限：$mb MB';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _embedSummary = '保存请求体积上限失败：$e';
      });
    }
  }

  /// 刷新“最新窗口”内的向量覆盖率统计：
  /// - total：窗口内样本总数（≤ latestWindow）
  /// - embedded：窗口内已有向量的数量
  Future<void> _refreshEmbeddingCoverage() async {
    if (_coverageLoading) return;

    if (mounted) {
      setState(() {
        _coverageLoading = true;
      });
    }

    try {
      final db = await ScreenshotDatabase.instance.database;

      final List<Map<String, Object?>> rows = await db.rawQuery(
        '''
        SELECT
          (SELECT COUNT(*) FROM segment_samples) AS total,
          (SELECT COUNT(*) FROM embeddings) AS embedded
        ''',
      );

      final Map<String, Object?> row = rows.isEmpty ? <String, Object?>{} : rows.first;
      final int total = (row['total'] is int) ? row['total'] as int : int.tryParse('${row['total']}') ?? 0;
      final int embedded = (row['embedded'] is int) ? row['embedded'] as int : int.tryParse('${row['embedded']}') ?? 0;

      if (mounted) {
        setState(() {
          _coverageTotal = total;
          _coverageEmbedded = embedded;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _embedSummary = '统计失败：$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _coverageLoading = false;
        });
      }
    }
  }


  void _stopEmbeddingsBackfill() {
    if (!_embedRunning) return;
    setState(() {
      _embedCancelRequested = true;
      _embedSummary = '正在停止...';
    });
  }

  Future<void> _runEmbeddingsBackfillAll() async {
    if (_embedRunning) return;

    await _persistDebugUiState();

    // 分页大小：每次从数据库读取多少条“缺失向量”的样本
    int pageSize = int.tryParse(_embedBatchSizeController.text.trim()) ?? 1000;
    if (pageSize < 1) pageSize = 1000;
    if (pageSize > 5000) pageSize = 5000;

    // 约束：按时间间隔抽样（默认 30 秒 1 张）
    int intervalSec = int.tryParse(_embedIntervalSecondsController.text.trim()) ?? 30;
    if (intervalSec < 1) intervalSec = 1;
    if (intervalSec > 24 * 60 * 60) intervalSec = 24 * 60 * 60;
    final int intervalMs = intervalSec * 1000;

    // 约束：每次请求最多 20 张
    int maxImagesPerRequest =
        int.tryParse(_embedMaxImagesPerRequestController.text.trim()) ?? 20;
    if (maxImagesPerRequest < 1) maxImagesPerRequest = 1;
    if (maxImagesPerRequest > 20) maxImagesPerRequest = 20;

    int concurrency = int.tryParse(_embedConcurrencyController.text.trim()) ?? 2;
    if (concurrency < 1) concurrency = 1;
    if (concurrency > 8) concurrency = 8;

    final int maxRequestMb =
        int.tryParse(_embedMaxRequestMbController.text.trim()) ??
            await EmbeddingService.instance.getMaxRequestMb();

    final String apiKey = _apiKeyController.text.trim();
    final String baseUrlText = _baseUrlController.text.trim();
    final String modelText = _modelController.text.trim();
    final String dimensionsText = _dimensionsController.text.trim();
    final int? dimensions =
        dimensionsText.isEmpty ? null : int.tryParse(dimensionsText);

    setState(() {
      _embedRunning = true;
      _embedCancelRequested = false;
      _embedTotal = 0;
      _embedProcessed = 0;
      _embedOk = 0;
      _embedFail = 0;
      _embedSkippedMissingFile = 0;
      _embedSummary = '准备中...';
    });

    int? asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    try {
      // 将 UI 里的 maxRequestMb 写入设置，确保逐图请求也走同一上限校验
      await EmbeddingService.instance.setMaxRequestMb(maxRequestMb);
      final int limitBytes = maxRequestMb * 1024 * 1024;

      final EmbeddingResolvedConfig cfg =
          await EmbeddingService.instance.resolveEmbeddingConfig(
        context: 'embedding',
        apiKeyOverride: apiKey.isEmpty ? null : apiKey,
        baseUrlOverride: baseUrlText.isEmpty ? null : baseUrlText,
        modelOverride: modelText.isEmpty ? null : modelText,
      );

      // 若用户填了不合理的值，启动时直接纠正并持久化（避免“实际用 20，UI 显示 30”）
      final bool needFixMaxPerReq =
          _embedMaxImagesPerRequestController.text.trim() != maxImagesPerRequest.toString();
      final bool needFixPageSize =
          _embedBatchSizeController.text.trim() != pageSize.toString();
      final bool needFixInterval =
          _embedIntervalSecondsController.text.trim() != intervalSec.toString();
      if (needFixMaxPerReq || needFixPageSize || needFixInterval) {
        if (!mounted) return;
        setState(() {
          if (needFixMaxPerReq) {
            _embedMaxImagesPerRequestController.text = maxImagesPerRequest.toString();
          }
          if (needFixPageSize) {
            _embedBatchSizeController.text = pageSize.toString();
          }
          if (needFixInterval) {
            _embedIntervalSecondsController.text = intervalSec.toString();
          }
        });
        await _persistDebugUiState();
      }

      int? lastSelectedTs;
      int filteredByInterval = 0;
      int scanned = 0;
      int queued = 0;
      int? beforeTs;
      int? beforeId;

      final List<Map<String, dynamic>> pending = <Map<String, dynamic>>[];

      Future<void> flushPending() async {
        if (_embedCancelRequested) return;
        if (pending.isEmpty) return;

        final List<Map<String, dynamic>> batch = List<Map<String, dynamic>>.from(pending);
        pending.clear();

        final List<String> paths = batch
            .map((e) => ((e['file_path'] as String?) ?? '').trim())
            .where((p) => p.isNotEmpty)
            .toList();

        // 理论上 paths 与 batch 等长；这里做一次保护，避免空 path 造成错位。
        if (paths.length != batch.length) {
          _embedFail += batch.length;
          _embedProcessed += batch.length;
          if (mounted) {
            setState(() {
              _embedSummary =
                  '运行中... 已处理=$_embedProcessed/$_embedTotal 成功=$_embedOk 失败=$_embedFail 缺文件=$_embedSkippedMissingFile 已扫描=$scanned 已入队=$queued 过滤(间隔)=$filteredByInterval';
            });
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return;
        }

        try {
          if (_embedTryMultiImageRequest) {
            final List<List<double>> vectors =
                await EmbeddingService.instance.embedImageFilesBatchBestEffort(
              filePaths: paths,
              apiKey: cfg.apiKey,
              baseUrl: cfg.baseUrl,
              model: cfg.model,
              dimensions: dimensions,
              maxImagesPerRequest: maxImagesPerRequest,
              maxRequestBytesOverride: limitBytes,
              tryMultiImageRequest: true,
            );

            final int n = vectors.length < batch.length ? vectors.length : batch.length;
            for (int i = 0; i < n; i++) {
              if (_embedCancelRequested) break;
              final int sid = asInt(batch[i]['id']) ?? 0;
              final int seg = asInt(batch[i]['segment_id']) ?? 0;
              if (sid <= 0 || seg <= 0) {
                _embedFail++;
                continue;
              }
              try {
                await ScreenshotDatabase.instance.saveEmbeddingForSample(
                  sampleId: sid,
                  segmentId: seg,
                  embedding: vectors[i],
                  modelVersion: cfg.model,
                );
                _embedOk++;
              } catch (_) {
                _embedFail++;
              }
            }
            if (n < batch.length) {
              _embedFail += (batch.length - n);
            }
          } else {
            // 逐图并发处理（每次最多 20 张，且可调并发）
            final List<Future<void>> inflight = <Future<void>>[];

            Future<void> runOne(int i) async {
              final int sid = asInt(batch[i]['id']) ?? 0;
              final int seg = asInt(batch[i]['segment_id']) ?? 0;
              final String path = paths[i];
              if (sid <= 0 || seg <= 0 || path.trim().isEmpty) {
                _embedFail++;
                return;
              }
              try {
                final List<double> vec = await EmbeddingService.instance.embedImageFile(
                  filePath: path,
                  apiKey: cfg.apiKey,
                  baseUrl: cfg.baseUrl,
                  model: cfg.model,
                  dimensions: dimensions,
                );
                await ScreenshotDatabase.instance.saveEmbeddingForSample(
                  sampleId: sid,
                  segmentId: seg,
                  embedding: vec,
                  modelVersion: cfg.model,
                );
                _embedOk++;
              } catch (_) {
                _embedFail++;
              }
            }

            for (int i = 0; i < batch.length; i++) {
              if (_embedCancelRequested) break;
              inflight.add(runOne(i));
              if (inflight.length >= concurrency) {
                await Future.wait(inflight);
                inflight.clear();
              }
            }
            if (inflight.isNotEmpty) {
              await Future.wait(inflight);
            }
          }
        } catch (_) {
          // 整批失败：回退逐图 best-effort，确保可以继续跑下去
          for (int i = 0; i < batch.length; i++) {
            if (_embedCancelRequested) break;
            final int sid = asInt(batch[i]['id']) ?? 0;
            final int seg = asInt(batch[i]['segment_id']) ?? 0;
            final String path = paths[i];
            if (sid <= 0 || seg <= 0 || path.trim().isEmpty) {
              _embedFail++;
              continue;
            }
            try {
              final List<double> vec = await EmbeddingService.instance.embedImageFile(
                filePath: path,
                apiKey: cfg.apiKey,
                baseUrl: cfg.baseUrl,
                model: cfg.model,
                dimensions: dimensions,
              );
              await ScreenshotDatabase.instance.saveEmbeddingForSample(
                sampleId: sid,
                segmentId: seg,
                embedding: vec,
                modelVersion: cfg.model,
              );
              _embedOk++;
            } catch (_) {
              _embedFail++;
            }
          }
        }

        _embedProcessed += batch.length;

        if (mounted) {
          setState(() {
            _embedSummary =
                '运行中... 已处理=$_embedProcessed/$_embedTotal 成功=$_embedOk 失败=$_embedFail 缺文件=$_embedSkippedMissingFile 已扫描=$scanned 已入队=$queued 过滤(间隔)=$filteredByInterval';
          });
        }

        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      if (!mounted) return;
      setState(() {
        _embedSummary =
            '运行中... 全量扫描缺失向量样本，分页=$pageSize，间隔=${intervalSec}s，每次最多$maxImagesPerRequest张，MB上限=$maxRequestMb';
      });

      while (!_embedCancelRequested) {
        final List<Map<String, dynamic>> candidates =
            await ScreenshotDatabase.instance.listSamplesMissingEmbeddingsCursor(
          limit: pageSize,
          segmentId: null,
          beforeCaptureTime: beforeTs,
          beforeId: beforeId,
        );
        if (candidates.isEmpty) break;

        for (final r in candidates) {
          if (_embedCancelRequested) break;

          scanned++;
          final int? sid = asInt(r['id']);
          final int? seg = asInt(r['segment_id']);
          final int? ts = asInt(r['capture_time']);
          final String path = (r['file_path'] as String?) ?? '';
          if (sid == null || seg == null || ts == null || path.trim().isEmpty) {
            continue;
          }

          if (lastSelectedTs != null && (lastSelectedTs - ts) < intervalMs) {
            filteredByInterval++;
            continue;
          }

          if (!File(path).existsSync()) {
            _embedSkippedMissingFile++;
            continue;
          }

          pending.add(r);
          queued++;
          lastSelectedTs = ts;

          if (pending.length >= maxImagesPerRequest) {
            if (mounted) {
              setState(() {
                _embedTotal = queued;
              });
            }
            await flushPending();
          }
        }

        final int? lastTs = asInt(candidates.last['capture_time']);
        final int? lastId = asInt(candidates.last['id']);
        if (lastTs == null || lastId == null) break;
        beforeTs = lastTs;
        beforeId = lastId;

        if (mounted) {
          setState(() {
            _embedTotal = queued;
            _embedSummary =
                '运行中... 已处理=$_embedProcessed/$_embedTotal 成功=$_embedOk 失败=$_embedFail 缺文件=$_embedSkippedMissingFile 已扫描=$scanned 已入队=$queued 过滤(间隔)=$filteredByInterval';
          });
        }
      }

      if (!_embedCancelRequested) {
        if (mounted) {
          setState(() {
            _embedTotal = queued;
          });
        }
        await flushPending();
      }

      if (!mounted) return;
      setState(() {
        _embedSummary = _embedCancelRequested
            ? '已停止。已处理=$_embedProcessed/$_embedTotal 成功=$_embedOk 失败=$_embedFail 缺文件=$_embedSkippedMissingFile'
            : '完成。已处理=$_embedProcessed/$_embedTotal 成功=$_embedOk 失败=$_embedFail 缺文件=$_embedSkippedMissingFile';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _embedSummary = '向量回填失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _embedRunning = false;
          _embedCancelRequested = false;
        });
        await _refreshEmbeddingCoverage();
      }
    }
  }

  String _fmtTs(int ms) {
    String two(int v) => v.toString().padLeft(2, '0');
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Future<void> _runSemanticSearch() async {
    if (_semanticRunning) return;

    await _persistDebugUiState();

    final String query = _semanticQueryController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _semanticSummary = '查询不能为空';
      });
      return;
    }

    int latestWindow =
        int.tryParse(_semanticCandidateLimitController.text.trim()) ?? 1000;
    if (latestWindow < 1) latestWindow = 1;
    if (latestWindow > 1000) latestWindow = 1000;

    const int topK = 20;

    final String apiKey = _apiKeyController.text.trim();
    final String baseUrlText = _baseUrlController.text.trim();
    final String modelText = _modelController.text.trim();
    final String dimensionsText = _dimensionsController.text.trim();
    final int? dimensions =
        dimensionsText.isEmpty ? null : int.tryParse(dimensionsText);

    int? asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    setState(() {
      _semanticRunning = true;
      _semanticHits = <_SemanticHit>[];
      _semanticSummary = '正在生成查询向量...';
    });

    try {
      final EmbeddingResolvedConfig cfg =
          await EmbeddingService.instance.resolveEmbeddingConfig(
        context: 'embedding',
        apiKeyOverride: apiKey.isEmpty ? null : apiKey,
        baseUrlOverride: baseUrlText.isEmpty ? null : baseUrlText,
        modelOverride: modelText.isEmpty ? null : modelText,
      );

      final List<double> qvec = await EmbeddingService.instance.embedText(
        text: query,
        apiKey: cfg.apiKey,
        baseUrl: cfg.baseUrl,
        model: cfg.model,
        dimensions: dimensions,
      );
      double normQ = 0.0;
      for (final v in qvec) {
        normQ += v * v;
      }
      normQ = math.sqrt(normQ);
      if (normQ <= 0) {
        throw Exception('查询向量范数为 0');
      }

      setState(() {
        _semanticSummary = '正在加载候选向量...';
      });

      final List<Map<String, dynamic>> candidates =
          await ScreenshotDatabase.instance.listEmbeddingsInLatestSamplesWindow(
        latestSamplesLimit: latestWindow,
        segmentId: null,
      );
      if (candidates.isEmpty) {
        setState(() {
          _semanticSummary = '未找到任何向量，请先回填向量（默认最新 1000 张、30 秒抽样）。';
        });
        return;
      }

      final List<_SemanticHit> hits = <_SemanticHit>[];
      for (final Map<String, dynamic> row in candidates) {
        final Object? embObj = row['embedding'];
        if (embObj is! Uint8List) continue;
        if (embObj.lengthInBytes < 4 || embObj.lengthInBytes % 4 != 0) continue;
        // sqflite 可能返回“带偏移”的 Uint8List 视图（offsetInBytes 不是 4 的倍数）
        // asFloat32List 要求 byteOffset 必须 4 字节对齐，因此这里做一次拷贝保证对齐。
        Uint8List bytes = embObj;
        if (bytes.offsetInBytes % 4 != 0) {
          bytes = Uint8List.fromList(bytes);
        }

        final Float32List floats = bytes.buffer.asFloat32List(
          bytes.offsetInBytes,
          bytes.lengthInBytes ~/ 4,
        );
        if (floats.length != qvec.length) {
          continue;
        }

        double dot = 0.0;
        double normC = 0.0;
        for (int i = 0; i < floats.length; i++) {
          final double c = floats[i].toDouble();
          dot += qvec[i] * c;
          normC += c * c;
        }
        final double denom = normQ * math.sqrt(normC);
        if (denom <= 0) continue;

        final double score = dot / denom;
        final int sid = asInt(row['sample_id']) ?? 0;
        final int segId = asInt(row['segment_id']) ?? 0;
        final int ts = asInt(row['capture_time']) ?? 0;
        final String path = (row['file_path'] as String?) ?? '';
        final String app = (row['app_name'] as String?) ?? '';
        if (sid <= 0 || segId <= 0 || path.trim().isEmpty) continue;

        hits.add(_SemanticHit(
          score: score,
          sampleId: sid,
          segmentId: segId,
          captureTime: ts,
          filePath: path,
          appName: app,
        ));
      }

      hits.sort((a, b) => b.score.compareTo(a.score));
      final List<_SemanticHit> top = hits.take(topK).toList();

      if (!mounted) return;
      setState(() {
        _semanticHits = top;
        _semanticSummary =
            '完成。窗口=最新$latestWindow张，候选向量=${candidates.length}，TopK=${top.length}，提供商=${cfg.providerName ?? ''}，模型=${cfg.model}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _semanticSummary = '语义搜索失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _semanticRunning = false;
        });
      }
    }
  }

  // （已整理）旧的“批量测试/写库验证/回填缺失”逻辑已移除，统一使用下方“批量向量化”。

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _dimensionsController.dispose();
    _embedBatchSizeController.dispose();
    _embedConcurrencyController.dispose();
    _embedMaxImagesPerRequestController.dispose();
    _embedIntervalSecondsController.dispose();
    _embedMaxRequestMbController.dispose();
    _semanticQueryController.dispose();
    _semanticCandidateLimitController.dispose();
    super.dispose();
  }

  // （已整理）旧的“单张测试/批量测试”逻辑已移除。

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Embedding 调试'),
        // 说明：显式关闭 Material3 的表面着色，避免顶部出现“发白的小条/遮挡”观感。
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      // 说明：这里不再包 SafeArea，避免顶部/底部出现额外留白条；
      // AppBar 已处理状态栏 inset，列表本身可滚动避免被导航栏遮挡。
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing4),
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppTheme.spacing4),
          children: [
            // ═══════════════════════════════════════════
            // 区块 1：API 配置
            // ═══════════════════════════════════════════
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacing3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('API 配置', style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppTheme.spacing2),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        hintText: '留空使用默认',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    TextField(
                      controller: _baseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        hintText: '留空使用豆包默认',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    TextField(
                      controller: _modelController,
                      decoration: const InputDecoration(
                        labelText: '模型 ID',
                        hintText: '留空使用默认',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    TextField(
                      controller: _dimensionsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '向量维度',
                        hintText: '例如 2048',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppTheme.spacing3),

            // ═══════════════════════════════════════════
            // 区块 2：批量向量化
            // ═══════════════════════════════════════════
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacing3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '批量向量化',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (_embedRunning)
                          Text(
                            '运行中',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    Text(
                      '已向量化：$_coverageEmbedded / $_coverageTotal',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    TextField(
                      controller: _embedBatchSizeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '分页大小',
                        hintText: '默认 1000',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    TextField(
                      controller: _embedConcurrencyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '并发数',
                        hintText: '例如 2',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    TextField(
                      controller: _embedMaxImagesPerRequestController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '单次最大图片数（≤20）',
                        hintText: '默认 20',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    TextField(
                      controller: _embedIntervalSecondsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '抽样间隔（秒）',
                        hintText: '默认 30',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    TextField(
                      controller: _embedMaxRequestMbController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '单次请求最大体积（MB）',
                        hintText: '例如 3',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    Row(
                      children: [
                        Switch(
                          value: _embedTryMultiImageRequest,
                          onChanged: _embedRunning
                              ? null
                              : (v) {
                                  setState(() {
                                    _embedTryMultiImageRequest = v;
                                  });
                                  _persistDebugUiState();
                                },
                        ),
                        Expanded(
                          child: Text(
                            '尝试多图请求（失败回退逐图）',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (_coverageLoading)
                          const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        TextButton(
                          onPressed: (_embedRunning || _coverageLoading)
                              ? null
                              : _refreshEmbeddingCoverage,
                          child: const Text('刷新'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacing3),
                    Wrap(
                      spacing: AppTheme.spacing2,
                      runSpacing: AppTheme.spacing2,
                      children: [
                        ElevatedButton(
                          onPressed: _embedRunning ? null : _runEmbeddingsBackfillAll,
                          child: const Text('开始批量向量化'),
                        ),
                        OutlinedButton(
                          onPressed: _embedRunning ? _stopEmbeddingsBackfill : null,
                          child: const Text('停止'),
                        ),
                        OutlinedButton(
                          onPressed: _embedRunning ? null : _applyEmbeddingMaxRequestMb,
                          child: const Text('保存设置'),
                        ),
                        OutlinedButton(
                          onPressed: _embedRunning
                              ? null
                              : () async {
                                  final bool? ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) {
                                      return AlertDialog(
                                        title: const Text('清空向量库'),
                                        content: const Text('将删除所有向量数据，是否继续？'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(ctx).pop(false),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.of(ctx).pop(true),
                                            child: const Text('确认'),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                  if (ok != true) return;
                                  try {
                                    final int deleted = await ScreenshotDatabase.instance.clearAllEmbeddings();
                                    if (!mounted) return;
                                    setState(() {
                                      _embedSummary = '已清空：删除 $deleted 条向量';
                                    });
                                    await _refreshEmbeddingCoverage();
                                  } catch (e) {
                                    if (!mounted) return;
                                    setState(() {
                                      _embedSummary = '清空失败：$e';
                                    });
                                  }
                                },
                          child: const Text('清空向量库'),
                        ),
                      ],
                    ),
                    if (_embedRunning) ...[
                      const SizedBox(height: AppTheme.spacing2),
                      LinearProgressIndicator(
                        value: _embedTotal > 0
                            ? (_embedProcessed / _embedTotal).clamp(0.0, 1.0)
                            : null,
                      ),
                    ],
                    const SizedBox(height: AppTheme.spacing2),
                    Text(
                      '队列=$_embedTotal  处理=$_embedProcessed  成功=$_embedOk  失败=$_embedFail',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (_embedSummary.trim().isNotEmpty) ...[
                      const SizedBox(height: AppTheme.spacing1),
                      SelectableText(
                        _embedSummary,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppTheme.spacing3),

            // ═══════════════════════════════════════════
            // 区块 3：语义搜索
            // ═══════════════════════════════════════════
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacing3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '语义搜索',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (_semanticRunning)
                          const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    TextField(
                      controller: _semanticQueryController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '文本描述',
                        hintText: '描述你想找的画面/内容',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    TextField(
                      controller: _semanticCandidateLimitController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '窗口大小（≤1000，TopK固定20）',
                        hintText: '默认 1000',
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _semanticRunning ? null : _runSemanticSearch,
                        child: const Text('开始语义搜索'),
                      ),
                    ),
                    if (_semanticSummary.trim().isNotEmpty) ...[
                      const SizedBox(height: AppTheme.spacing2),
                      SelectableText(
                        _semanticSummary,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (_semanticHits.isNotEmpty) ...[
                      const SizedBox(height: AppTheme.spacing3),
                      ...List<Widget>.generate(_semanticHits.length, (i) {
                        final _SemanticHit hit = _semanticHits[i];
                        final String title =
                            '#${i + 1}  ${hit.score.toStringAsFixed(3)}  ${_fmtTs(hit.captureTime)}  ${hit.appName}';
                        final bool exists = File(hit.filePath).existsSync();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: AppTheme.spacing1),
                              SelectableText(
                                hit.filePath,
                                style: theme.textTheme.bodySmall,
                              ),
                              if (exists) ...[
                                const SizedBox(height: AppTheme.spacing1),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                                  child: Image.file(
                                    File(hit.filePath),
                                    width: double.infinity,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ],
                              const Divider(height: AppTheme.spacing4),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                  ),
                ),
              ),

          ],
        ),
      ),
    );
  }
}
