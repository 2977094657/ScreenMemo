import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/embedding_service.dart';
import '../services/screenshot_database.dart';
import '../theme/app_theme.dart';

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
  final TextEditingController _filePathController = TextEditingController();
  final TextEditingController _latestCountController = TextEditingController(text: '10');

  bool _isLoading = false;
  String _requestSummary = '';
  String _responseSummary = '';
  String _errorText = '';
  String _batchSummary = '';

  @override
  void initState() {
    super.initState();
    _baseUrlController.text = 'https://ark.cn-beijing.volces.com/api/v3';
    _modelController.text = 'doubao-embedding-vision-250615';
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _dimensionsController.dispose();
    _filePathController.dispose();
    _latestCountController.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    final String apiKey = _apiKeyController.text.trim();
    final String baseUrlText = _baseUrlController.text.trim();
    final String modelText = _modelController.text.trim();
    final String dimensionsText = _dimensionsController.text.trim();
    final String filePath = _filePathController.text.trim();

    if (apiKey.isEmpty) {
      setState(() {
        _errorText = 'API Key 不能为空';
      });
      return;
    }
    if (filePath.isEmpty) {
      setState(() {
        _errorText = '文件路径不能为空';
      });
      return;
    }

    final File file = File(filePath);
    final bool exists = await file.exists();
    int? fileSize;
    if (exists) {
      fileSize = await file.length();
    }
    final int limitBytes = await EmbeddingService.instance.maxRequestBytes();

    final int? dimensions = dimensionsText.isEmpty
        ? null
        : int.tryParse(dimensionsText);

    final String effectiveBaseLabel =
        baseUrlText.isEmpty ? '(使用默认)' : baseUrlText;
    final String effectiveModelLabel =
        modelText.isEmpty ? '(使用默认)' : modelText;
    final String effectiveDimLabel =
        dimensions == null ? '(使用默认)' : dimensions.toString();

    setState(() {
      _isLoading = true;
      _errorText = '';
      _responseSummary = '';
      _batchSummary = '';
      _requestSummary = 'filePath: $filePath\n'
          'fileExists: $exists\n'
          'fileSize: ${fileSize ?? 0} bytes\n'
          'limitBytes: $limitBytes bytes\n'
          'baseUrl: $effectiveBaseLabel\n'
          'model: $effectiveModelLabel\n'
          'dimensions: $effectiveDimLabel';
    });

    try {
      final List<double> embedding = await EmbeddingService.instance
          .embedImageFile(
        filePath: filePath,
        apiKey: apiKey,
        baseUrl: baseUrlText.isEmpty ? null : baseUrlText,
        model: modelText.isEmpty ? null : modelText,
        dimensions: dimensions,
      );
      if (!mounted) return;
      final int len = embedding.length;
      final int previewCount = len < 16 ? len : 16;
      final List<double> preview = embedding.take(previewCount).toList();
      setState(() {
        _responseSummary = '向量长度: $len\n'
            '前 $previewCount 个值: $preview';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _runLatestBatchTest() async {
    final String apiKey = _apiKeyController.text.trim();
    final String baseUrlText = _baseUrlController.text.trim();
    final String modelText = _modelController.text.trim();
    final String dimensionsText = _dimensionsController.text.trim();
    final String countText = _latestCountController.text.trim();

    if (apiKey.isEmpty) {
      setState(() {
        _errorText = 'API Key 不能为空';
      });
      return;
    }

    final int? count = int.tryParse(countText);
    if (count == null || count <= 0) {
      setState(() {
        _errorText = '数量必须是正整数';
      });
      return;
    }

    final int? dimensions = dimensionsText.isEmpty
        ? null
        : int.tryParse(dimensionsText);

    setState(() {
      _isLoading = true;
      _errorText = '';
      _responseSummary = '';
      _batchSummary = '';
      _requestSummary = '';
    });

    try {
      final List<Map<String, dynamic>> rows =
          await ScreenshotDatabase.instance.listLatestSamples(limit: count);
      if (!mounted) return;
      if (rows.isEmpty) {
        setState(() {
          _batchSummary = '数据库中没有可用的截图样本';
        });
        return;
      }

      final String effectiveBase = baseUrlText.isEmpty ? '' : baseUrlText;
      final String effectiveModel = modelText.isEmpty ? '' : modelText;

      int success = 0;
      int failed = 0;
      final List<String> previews = <String>[];

      for (int i = 0; i < rows.length; i++) {
        final Map<String, dynamic> row = rows[i];
        final Object? pathObj = row['file_path'];
        if (pathObj is! String) {
          failed++;
          continue;
        }
        final String path = pathObj;
        try {
          final List<double> embedding = await EmbeddingService.instance
              .embedImageFile(
            filePath: path,
            apiKey: apiKey,
            baseUrl: effectiveBase.isEmpty ? null : effectiveBase,
            model: effectiveModel.isEmpty ? null : effectiveModel,
            dimensions: dimensions,
          );
          success++;
          if (previews.length < 5) {
            final int len = embedding.length;
            previews.add('[$i] $path (len=$len)');
          }
        } catch (_) {
          failed++;
        }
      }

      if (!mounted) return;
      setState(() {
        _batchSummary = '阶段1: 从数据库读取最新样本 -> OK, 数量=${rows.length}\n'
            '阶段2: 调用 embedding 接口 -> 成功=$success, 失败=$failed\n'
            '预览:\n${previews.join('\n')}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Embedding 调试'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _apiKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                ),
              ),
              const SizedBox(height: AppTheme.spacing3),
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: '留空使用默认',
                ),
              ),
              const SizedBox(height: AppTheme.spacing3),
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: '模型 ID',
                  hintText: '留空使用默认',
                ),
              ),
              const SizedBox(height: AppTheme.spacing3),
              TextField(
                controller: _dimensionsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '向量维度',
                  hintText: '例如 2048，留空使用默认',
                ),
              ),
              const SizedBox(height: AppTheme.spacing3),
              TextField(
                controller: _filePathController,
                decoration: const InputDecoration(
                  labelText: '图片文件路径',
                ),
              ),
              const SizedBox(height: AppTheme.spacing3),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latestCountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '最新 N 张截图',
                        hintText: '例如 10',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing3),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _runLatestBatchTest,
                      child: const Text('批量测试'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacing3),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _runTest,
                  child: _isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('单张测试'),
                ),
              ),
              const SizedBox(height: AppTheme.spacing4),
              if (_requestSummary.isNotEmpty ||
                  _responseSummary.isNotEmpty ||
                  _errorText.isNotEmpty ||
                  _batchSummary.isNotEmpty)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_requestSummary.isNotEmpty) ...[
                          Text(
                            '请求概要',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppTheme.spacing1),
                          SelectableText(
                            _requestSummary,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: AppTheme.spacing3),
                        ],
                        if (_responseSummary.isNotEmpty) ...[
                          Text(
                            '响应概要',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppTheme.spacing1),
                          SelectableText(
                            _responseSummary,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: AppTheme.spacing3),
                        ],
                        if (_errorText.isNotEmpty) ...[
                          Text(
                            '错误信息',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(color: theme.colorScheme.error),
                          ),
                          const SizedBox(height: AppTheme.spacing1),
                          SelectableText(
                            _errorText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacing3),
                        ],
                        if (_batchSummary.isNotEmpty) ...[
                          Text(
                            '批量概要',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppTheme.spacing1),
                          SelectableText(
                            _batchSummary,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
