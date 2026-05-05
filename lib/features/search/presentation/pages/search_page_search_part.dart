part of 'search_page.dart';

// ========== 搜索加载与分页处理 ==========
extension _SearchPageSearchPart on _SearchPageState {
  Future<void> _search(String query) async {
    if (!mounted) return;
    final int token = ++_searchToken;
    _searchSetState(() {
      _isLoading = query.isNotEmpty;
      _error = null;
      _results = <ScreenshotRecord>[];
      _filteredResults = <ScreenshotRecord>[];
      _totalResultsCount = 0;
      _segmentResults = <Map<String, dynamic>>[];
      _offset = 0;
      _segmentOffset = 0;
      _hasMore = false;
      _segmentHasMore = false;
      _segmentTotalCount = 0;
      _lastQuery = query;
      _usingAiImageMeta = false;
      _usingFavoriteNotes = false;
      _countingTotal = false;
      _segmentCountingTotal = false;
      _segmentSearchFinished = false;
      _segmentSearching = false;
      _docResults = <Map<String, dynamic>>[];
      _docOffset = 0;
      _docHasMore = false;
      _docLoadingMore = false;
      _docTotalCount = 0;
      _docCountingTotal = false;
      _docSearchFinished = false;
      _docSearching = false;
      _semanticResults = <ScreenshotRecord>[];
      _filteredSemanticResults = <ScreenshotRecord>[];
      _semanticTagsByPath.clear();
      _semanticAvailableTags = <String>{};
      _semanticSelectedTags = <String>{};
      _semanticOffset = 0;
      _semanticHasMore = false;
      _semanticLoadingMore = false;
      _semanticTotalCount = 0;
      _semanticCountingTotal = false;
      _semanticSearchFinished = false;
      _semanticSearching = false;
    });

    if (query.isEmpty) return;

    // 语义/动态/更多：保持“手动触发”，避免拖累首屏速度（见各 Tab 内的按钮）。

    try {
      final sw = Stopwatch()..start();
      final range = _currentTimeRange();
      final size = _currentSizeRange();

      // 第一批：快速返回少量结果
      final firstBatch = await ScreenshotService.instance
          .searchScreenshotsByOcrWithFallback(
            query,
            limit: _SearchPageState._firstBatchSize,
            offset: 0,
            startMillis: range?.$1,
            endMillis: range?.$2,
            minSize: size?.$1,
            maxSize: size?.$2,
          );

      if (!mounted || token != _searchToken) return;

      // OCR 无结果：回退 AI 图片元数据（tags/description）检索
      if (firstBatch.isEmpty) {
        final aiFirstRows = await ScreenshotDatabase.instance
            .searchAiImageMetaByText(
              query,
              limit: _SearchPageState._firstBatchSize,
              offset: 0,
              startMillis: range?.$1,
              endMillis: range?.$2,
              includeNsfw: true,
            );
        if (!mounted || token != _searchToken) return;
        final aiFirst = _mapAiImageMetaRowsToScreenshots(aiFirstRows);
        if (aiFirst.isNotEmpty) {
          _searchSetState(() {
            _usingAiImageMeta = true;
            _usingFavoriteNotes = false;
            _results = aiFirst;
            _totalResultsCount = aiFirst.length;
            _applyFilters();
            _isLoading = false;
            _hasMore = aiFirst.length >= _SearchPageState._firstBatchSize;
            _offset = aiFirst.length;
            _countingTotal = false; // 目前不做总数统计，避免额外开销
          });
          // ignore: unawaited_futures
          _preloadNsfwForScreenshots(aiFirst, token: token);

          // AI 首批不足：直接结束
          if (aiFirst.length < _SearchPageState._firstBatchSize) {
            if (mounted && token == _searchToken) {
              _searchSetState(() {
                _isLoading = false;
                _hasMore = false;
                _loadingMore = false;
                _countingTotal = false;
              });
            }
            return;
          }

          // AI 第二批：补齐到一页
          final aiMoreRows = await ScreenshotDatabase.instance
              .searchAiImageMetaByText(
                query,
                limit:
                    _SearchPageState._pageSize -
                    _SearchPageState._firstBatchSize,
                offset: _SearchPageState._firstBatchSize,
                startMillis: range?.$1,
                endMillis: range?.$2,
                includeNsfw: true,
              );
          if (!mounted || token != _searchToken) return;
          final aiMore = _mapAiImageMetaRowsToScreenshots(aiMoreRows);
          final allAi = [...aiFirst, ...aiMore];
          final bool hasMoreData = allAi.length >= _SearchPageState._pageSize;
          _searchSetState(() {
            _usingAiImageMeta = true;
            _usingFavoriteNotes = false;
            _results = allAi;
            _totalResultsCount = allAi.length;
            _applyFilters();
            _offset = allAi.length;
            _hasMore = hasMoreData;
            _isLoading = false;
            _countingTotal = false;
          });
          if (aiMore.isNotEmpty) {
            // ignore: unawaited_futures
            _preloadNsfwForScreenshots(aiMore, token: token);
          }
          return;
        }

        // AI 仍为空：回退收藏备注（SearchIndex）检索
        final favFirst = await _searchFavoriteNoteScreenshots(
          query,
          limit: _SearchPageState._firstBatchSize,
          offset: 0,
          startMillis: range?.$1,
          endMillis: range?.$2,
        );
        if (!mounted || token != _searchToken) return;
        if (favFirst.isNotEmpty) {
          _searchSetState(() {
            _usingAiImageMeta = false;
            _usingFavoriteNotes = true;
            _results = favFirst;
            _totalResultsCount = favFirst.length;
            _applyFilters();
            _isLoading = false;
            _hasMore = favFirst.length >= _SearchPageState._firstBatchSize;
            _offset = favFirst.length;
            _countingTotal = false;
          });
          // ignore: unawaited_futures
          _preloadNsfwForScreenshots(favFirst, token: token);
        }

        if (favFirst.length < _SearchPageState._firstBatchSize) {
          if (mounted && token == _searchToken) {
            _searchSetState(() {
              _isLoading = false;
              _hasMore = false;
              _loadingMore = false;
              _countingTotal = false;
            });
          }
          return;
        }

        final favMore = await _searchFavoriteNoteScreenshots(
          query,
          limit: _SearchPageState._pageSize - _SearchPageState._firstBatchSize,
          offset: _SearchPageState._firstBatchSize,
          startMillis: range?.$1,
          endMillis: range?.$2,
        );
        if (!mounted || token != _searchToken) return;
        final allFav = [...favFirst, ...favMore];
        final bool hasMoreData = allFav.length >= _SearchPageState._pageSize;
        _searchSetState(() {
          _usingAiImageMeta = false;
          _usingFavoriteNotes = true;
          _results = allFav;
          _totalResultsCount = allFav.length;
          _applyFilters();
          _offset = allFav.length;
          _hasMore = hasMoreData;
          _isLoading = false;
          _countingTotal = false;
        });
        if (favMore.isNotEmpty) {
          // ignore: unawaited_futures
          _preloadNsfwForScreenshots(favMore, token: token);
        }
        return;
      }

      // 立即显示首批结果
      if (firstBatch.isNotEmpty) {
        _searchSetState(() {
          _results = firstBatch;
          _totalResultsCount = firstBatch.length;
          _applyFilters();
          _isLoading = false;
          _hasMore = firstBatch.length >= _SearchPageState._firstBatchSize;
        });
        // ignore: unawaited_futures
        _preloadNsfwForScreenshots(firstBatch, token: token);
      }

      sw.stop();
      try {
        print('[搜索] 首批：${firstBatch.length} 条，耗时 ${sw.elapsedMilliseconds} 毫秒');
      } catch (_) {}

      // 如果首批不足，说明没有更多数据
      if (firstBatch.length < _SearchPageState._firstBatchSize) {
        if (mounted && token == _searchToken) {
          _searchSetState(() {
            _isLoading = false;
            _hasMore = false;
          });
        }
        return;
      }

      // 第二批：后台加载更多结果
      final sw2 = Stopwatch()..start();
      final moreBatch = await ScreenshotService.instance
          .searchScreenshotsByOcrWithFallback(
            query,
            limit:
                _SearchPageState._pageSize - _SearchPageState._firstBatchSize,
            offset: _SearchPageState._firstBatchSize,
            startMillis: range?.$1,
            endMillis: range?.$2,
            minSize: size?.$1,
            maxSize: size?.$2,
          );

      if (!mounted || token != _searchToken) return;

      final allResults = [...firstBatch, ...moreBatch];
      final bool hasMoreData = allResults.length >= _SearchPageState._pageSize;

      _searchSetState(() {
        _results = allResults;
        _totalResultsCount = allResults.length;
        _applyFilters();
        _offset = allResults.length;
        _hasMore = hasMoreData;
        _isLoading = false;
        _countingTotal = hasMoreData;
      });
      if (moreBatch.isNotEmpty) {
        // ignore: unawaited_futures
        _preloadNsfwForScreenshots(moreBatch, token: token);
      }

      sw2.stop();
      try {
        print('[搜索] 总计：${allResults.length} 条（+${sw2.elapsedMilliseconds} 毫秒）');
      } catch (_) {}

      if (!hasMoreData) {
        return;
      }

      // 后台统计总数
      ScreenshotService.instance
          .countScreenshotsByOcrWithFallback(
            query,
            startMillis: range?.$1,
            endMillis: range?.$2,
            minSize: size?.$1,
            maxSize: size?.$2,
          )
          .then((total) {
            if (!mounted || token != _searchToken) return;
            _searchSetState(() {
              _totalResultsCount = total;
              _countingTotal = false;
            });
          })
          .catchError((_) {
            if (!mounted || token != _searchToken) return;
            _searchSetState(() {
              _countingTotal = false;
            });
          });
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      _searchSetState(() {
        _error = AppLocalizations.of(context).searchFailedError(e.toString());
        _isLoading = false;
        _countingTotal = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_lastQuery.isEmpty) return;
    final int token = _searchToken;
    _searchSetState(() => _loadingMore = true);
    try {
      final sw = Stopwatch()..start();
      final range = _currentTimeRange();
      final size = _currentSizeRange();

      // 按当前检索来源加载更多
      final List<ScreenshotRecord> more;
      if (_usingAiImageMeta) {
        final rows = await ScreenshotDatabase.instance.searchAiImageMetaByText(
          _lastQuery,
          limit: _SearchPageState._pageSize,
          offset: _offset,
          startMillis: range?.$1,
          endMillis: range?.$2,
          includeNsfw: true,
        );
        more = _mapAiImageMetaRowsToScreenshots(rows);
      } else if (_usingFavoriteNotes) {
        more = await _searchFavoriteNoteScreenshots(
          _lastQuery,
          limit: _SearchPageState._pageSize,
          offset: _offset,
          startMillis: range?.$1,
          endMillis: range?.$2,
        );
      } else {
        more = await ScreenshotService.instance
            .searchScreenshotsByOcrWithFallback(
              _lastQuery,
              limit: _SearchPageState._pageSize,
              offset: _offset,
              startMillis: range?.$1,
              endMillis: range?.$2,
              minSize: size?.$1,
              maxSize: size?.$2,
            );
      }
      if (!mounted || token != _searchToken) return;
      _searchSetState(() {
        if (more.isEmpty) {
          _hasMore = false;
        } else {
          _results.addAll(more);
          // OCR 模式保持总结果数为数据库统计的总数；AI/收藏备注模式则以“已加载数量”为准
          if (_usingAiImageMeta || _usingFavoriteNotes) {
            _totalResultsCount = _results.length;
          }
          _applyFilters();
          _offset += more.length;
          _hasMore = more.length >= _SearchPageState._pageSize;
        }
        _loadingMore = false;
      });
      if (more.isNotEmpty) {
        // ignore: unawaited_futures
        _preloadNsfwForScreenshots(more, token: token);
      }
      sw.stop();
      try {
        print(
          '[搜索] 加载更多：获取=' +
              more.length.toString() +
              ' 偏移=' +
              _offset.toString() +
              ' 还有更多=' +
              _hasMore.toString() +
              ' 耗时=' +
              sw.elapsedMilliseconds.toString(),
        );
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      _searchSetState(() {
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  // ==================== 动态搜索相关方法 ====================

  /// 搜索动态内容
  Future<void> _searchSegments(String query) async {
    if (!mounted) return;
    final int token = _searchToken;

    if (query.isEmpty) {
      if (mounted && token == _searchToken) {
        _searchSetState(() {
          _segmentResults = <Map<String, dynamic>>[];
          _segmentTotalCount = 0;
          _segmentOffset = 0;
          _segmentHasMore = false;
          _segmentSearchFinished = false;
          _segmentSearching = false;
          _availableTags = <String>{};
          _selectedTags = <String>{};
        });
      }
      return;
    }

    // 手动触发：标记为“正在搜索”，并清空旧结果
    _searchSetState(() {
      _segmentSearching = true;
      _segmentResults = <Map<String, dynamic>>[];
      _segmentOffset = 0;
      _segmentHasMore = false;
      _segmentTotalCount = 0;
      _segmentCountingTotal = false;
      _availableTags = <String>{};
      _selectedTags = <String>{};
      _segmentSearchFinished = false;
    });

    try {
      final range = _currentTimeRange();
      final results = await ScreenshotDatabase.instance.searchSegmentsByText(
        query,
        limit: _SearchPageState._pageSize,
        offset: 0,
        startMillis: range?.$1,
        endMillis: range?.$2,
      );

      if (!mounted || token != _searchToken) return;

      // 提取标签（使用统一解析和清洗逻辑）
      final Set<String> tags = <String>{};
      for (final seg in results) {
        final String categoriesRaw = (seg['categories'] as String?) ?? '';
        final String outputText = (seg['output_text'] as String?) ?? '';
        final String structuredJson = (seg['structured_json'] as String?) ?? '';

        final Map<String, dynamic>? sj = _tryParseJson(structuredJson);
        final List<String> segTags = _extractCategories({
          'categories': categoriesRaw,
          'output_text': outputText,
        }, sj);

        for (final t in segTags) {
          if (t.trim().isEmpty) continue;
          tags.add(t);
        }
      }

      _searchSetState(() {
        _segmentSearching = false;
        _segmentResults = results;
        _segmentOffset = results.length;
        _segmentHasMore = results.length >= _SearchPageState._pageSize;
        _segmentTotalCount = results.length;
        _segmentCountingTotal = _segmentHasMore;
        _availableTags = tags;
        _selectedTags = <String>{}; // 重置标签筛选
        _segmentSearchFinished = true;
      });

      // 如果还有更多，后台统计总数
      if (_segmentHasMore) {
        ScreenshotDatabase.instance
            .countSegmentsByText(
              query,
              startMillis: range?.$1,
              endMillis: range?.$2,
            )
            .then((total) {
              if (!mounted || token != _searchToken) return;
              _searchSetState(() {
                _segmentTotalCount = total;
                _segmentCountingTotal = false;
                _segmentSearchFinished = true;
              });
            })
            .catchError((_) {
              if (!mounted || token != _searchToken) return;
              _searchSetState(() {
                _segmentCountingTotal = false;
                _segmentSearchFinished = true;
              });
            });
      }
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      _searchSetState(() {
        _segmentSearching = false;
        _segmentResults = <Map<String, dynamic>>[];
        _segmentCountingTotal = false;
        _segmentSearchFinished = true;
      });
    }
  }

  /// 加载更多动态
  Future<void> _loadMoreSegments() async {
    if (_lastQuery.isEmpty || _segmentLoadingMore || !_segmentHasMore) return;
    _searchSetState(() => _segmentLoadingMore = true);
    try {
      final range = _currentTimeRange();
      final more = await ScreenshotDatabase.instance.searchSegmentsByText(
        _lastQuery,
        limit: _SearchPageState._pageSize,
        offset: _segmentOffset,
        startMillis: range?.$1,
        endMillis: range?.$2,
      );
      if (!mounted) return;
      _searchSetState(() {
        if (more.isEmpty) {
          _segmentHasMore = false;
        } else {
          _segmentResults.addAll(more);
          _segmentOffset += more.length;
          _segmentHasMore = more.length >= _SearchPageState._pageSize;
        }
        _segmentLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      _searchSetState(() {
        _segmentLoadingMore = false;
        _segmentHasMore = false;
      });
    }
  }

  // ==================== “语义”搜索（ai_image_meta） ====================

  List<String> _parseAiImageTags(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(growable: false);
      }
      if (decoded is String) {
        return decoded
            .split(RegExp(r'[，,;；\s]+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(growable: false);
      }
    } catch (_) {}
    return s
        .split(RegExp(r'[，,;；\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  void _applySemanticTagFilter() {
    if (_semanticSelectedTags.isEmpty) {
      _filteredSemanticResults = List<ScreenshotRecord>.from(_semanticResults);
      return;
    }
    _filteredSemanticResults = _semanticResults
        .where((s) {
          final Set<String> tags =
              _semanticTagsByPath[s.filePath] ?? const <String>{};
          return _semanticSelectedTags.every((t) => tags.contains(t));
        })
        .toList(growable: false);
  }

  Future<void> _searchSemantic(String query) async {
    if (!mounted) return;
    final int token = _searchToken;

    final String q = query.trim();
    if (q.isEmpty) {
      if (!mounted || token != _searchToken) return;
      _searchSetState(() {
        _semanticSearching = false;
        _semanticSearchFinished = false;
        _semanticResults = <ScreenshotRecord>[];
        _filteredSemanticResults = <ScreenshotRecord>[];
        _semanticTagsByPath.clear();
        _semanticAvailableTags = <String>{};
        _semanticSelectedTags = <String>{};
        _semanticOffset = 0;
        _semanticHasMore = false;
        _semanticLoadingMore = false;
        _semanticTotalCount = 0;
        _semanticCountingTotal = false;
      });
      return;
    }

    _searchSetState(() {
      _semanticSearching = true;
      _semanticSearchFinished = false;
      _semanticResults = <ScreenshotRecord>[];
      _filteredSemanticResults = <ScreenshotRecord>[];
      _semanticTagsByPath.clear();
      _semanticAvailableTags = <String>{};
      _semanticSelectedTags = <String>{};
      _semanticOffset = 0;
      _semanticHasMore = false;
      _semanticLoadingMore = false;
      _semanticTotalCount = 0;
      _semanticCountingTotal = false;
    });

    try {
      final range = _currentTimeRange();
      final rows = await ScreenshotDatabase.instance.searchAiImageMetaByText(
        q,
        limit: _SearchPageState._pageSize,
        offset: 0,
        startMillis: range?.$1,
        endMillis: range?.$2,
        includeNsfw: true,
      );
      if (!mounted || token != _searchToken) return;

      final List<ScreenshotRecord> shots = <ScreenshotRecord>[];
      final Map<String, Set<String>> tagsByPath = <String, Set<String>>{};
      final Set<String> availableTags = <String>{};

      for (final r in rows) {
        final String fp = (r['file_path'] as String?)?.trim() ?? '';
        if (fp.isEmpty) continue;
        final int capture = (r['capture_time'] as int?) ?? 0;
        final String tagsJson = (r['tags_json'] as String?)?.trim() ?? '';
        final List<String> tags = _parseAiImageTags(tagsJson);
        if (tags.isNotEmpty) {
          tagsByPath[fp] = tags.toSet();
          availableTags.addAll(tags);
        }
        shots.add(
          ScreenshotRecord(
            id: null,
            appPackageName: (r['app_package_name'] as String?) ?? '',
            appName: (r['app_name'] as String?) ?? '',
            filePath: fp,
            captureTime: DateTime.fromMillisecondsSinceEpoch(
              capture > 0 ? capture : DateTime.now().millisecondsSinceEpoch,
            ),
            fileSize: 0,
            isDeleted: false,
            pageUrl: null,
            ocrText: null,
          ),
        );
      }

      _searchSetState(() {
        _semanticSearching = false;
        _semanticResults = shots;
        _semanticTagsByPath
          ..clear()
          ..addAll(tagsByPath);
        _semanticAvailableTags = availableTags;
        _semanticSelectedTags = <String>{};
        _semanticOffset = shots.length;
        _semanticHasMore = rows.length >= _SearchPageState._pageSize;
        _semanticTotalCount = shots.length;
        _semanticCountingTotal = false;
        _semanticSearchFinished = true;
        _applySemanticTagFilter();
      });

      // ignore: unawaited_futures
      _preloadNsfwForScreenshots(shots, token: token);
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      _searchSetState(() {
        _semanticSearching = false;
        _semanticResults = <ScreenshotRecord>[];
        _filteredSemanticResults = <ScreenshotRecord>[];
        _semanticHasMore = false;
        _semanticLoadingMore = false;
        _semanticCountingTotal = false;
        _semanticSearchFinished = true;
      });
    }
  }

  Future<void> _loadMoreSemantic() async {
    if (_lastQuery.isEmpty || _semanticLoadingMore || !_semanticHasMore) return;
    _searchSetState(() => _semanticLoadingMore = true);
    final int token = _searchToken;
    try {
      final range = _currentTimeRange();
      final rows = await ScreenshotDatabase.instance.searchAiImageMetaByText(
        _lastQuery,
        limit: _SearchPageState._pageSize,
        offset: _semanticOffset,
        startMillis: range?.$1,
        endMillis: range?.$2,
        includeNsfw: true,
      );
      if (!mounted || token != _searchToken) return;

      final List<ScreenshotRecord> moreShots = <ScreenshotRecord>[];
      final Set<String> newlyAvailableTags = <String>{};

      for (final r in rows) {
        final String fp = (r['file_path'] as String?)?.trim() ?? '';
        if (fp.isEmpty) continue;
        final int capture = (r['capture_time'] as int?) ?? 0;
        final String tagsJson = (r['tags_json'] as String?)?.trim() ?? '';
        final List<String> tags = _parseAiImageTags(tagsJson);
        if (tags.isNotEmpty) {
          _semanticTagsByPath[fp] = tags.toSet();
          newlyAvailableTags.addAll(tags);
        }
        moreShots.add(
          ScreenshotRecord(
            id: null,
            appPackageName: (r['app_package_name'] as String?) ?? '',
            appName: (r['app_name'] as String?) ?? '',
            filePath: fp,
            captureTime: DateTime.fromMillisecondsSinceEpoch(
              capture > 0 ? capture : DateTime.now().millisecondsSinceEpoch,
            ),
            fileSize: 0,
            isDeleted: false,
            pageUrl: null,
            ocrText: null,
          ),
        );
      }

      _searchSetState(() {
        if (moreShots.isEmpty) {
          _semanticHasMore = false;
        } else {
          _semanticResults.addAll(moreShots);
          _semanticOffset += moreShots.length;
          _semanticHasMore = rows.length >= _SearchPageState._pageSize;
          if (newlyAvailableTags.isNotEmpty) {
            _semanticAvailableTags = {
              ..._semanticAvailableTags,
              ...newlyAvailableTags,
            };
          }
          _semanticTotalCount = _semanticResults.length;
          _applySemanticTagFilter();
        }
        _semanticLoadingMore = false;
      });

      if (moreShots.isNotEmpty) {
        // ignore: unawaited_futures
        _preloadNsfwForScreenshots(moreShots, token: token);
      }
    } catch (_) {
      if (!mounted) return;
      _searchSetState(() {
        _semanticLoadingMore = false;
        _semanticHasMore = false;
      });
    }
  }

  // ==================== “更多”搜索（SearchIndex） ====================

  Future<void> _searchDocs(String query) async {
    if (!mounted) return;
    final int token = _searchToken;

    if (query.trim().isEmpty) {
      if (mounted && token == _searchToken) {
        _searchSetState(() {
          _docResults = <Map<String, dynamic>>[];
          _docTotalCount = 0;
          _docOffset = 0;
          _docHasMore = false;
          _docSearchFinished = false;
          _docSearching = false;
          _docLoadingMore = false;
          _docCountingTotal = false;
        });
      }
      return;
    }

    // 先清空再加载（保持按需触发：仅在“更多”Tab 内调用）
    _searchSetState(() {
      _docSearching = true;
      _docResults = <Map<String, dynamic>>[];
      _docTotalCount = 0;
      _docOffset = 0;
      _docHasMore = false;
      _docLoadingMore = false;
      _docCountingTotal = false;
      _docSearchFinished = false;
    });

    try {
      final range = _currentTimeRange();

      // 同步/追赶索引（兜底：兼容原生端写入）
      await ScreenshotDatabase.instance.syncSearchIndex(
        sources: _SearchPageState._docIndexSources,
      );
      if (!mounted || token != _searchToken) return;

      final results = await ScreenshotDatabase.instance.searchSearchDocsByText(
        query,
        docTypes: _docSelectedTypes.isEmpty
            ? _SearchPageState._docTabTypes
            : _docSelectedTypes,
        limit: _SearchPageState._pageSize,
        offset: 0,
        startMillis: range?.$1,
        endMillis: range?.$2,
      );
      if (!mounted || token != _searchToken) return;

      _searchSetState(() {
        _docSearching = false;
        _docResults = results;
        _docOffset = results.length;
        _docHasMore = results.length >= _SearchPageState._pageSize;
        _docTotalCount = results.length;
        _docCountingTotal = false;
        _docSearchFinished = true;
      });
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      _searchSetState(() {
        _docSearching = false;
        _docResults = <Map<String, dynamic>>[];
        _docCountingTotal = false;
        _docSearchFinished = true;
      });
    }
  }

  Future<void> _loadMoreDocs() async {
    if (_lastQuery.isEmpty || _docLoadingMore || !_docHasMore) return;
    _searchSetState(() => _docLoadingMore = true);
    try {
      final range = _currentTimeRange();
      final more = await ScreenshotDatabase.instance.searchSearchDocsByText(
        _lastQuery,
        docTypes: _docSelectedTypes.isEmpty
            ? _SearchPageState._docTabTypes
            : _docSelectedTypes,
        limit: _SearchPageState._pageSize,
        offset: _docOffset,
        startMillis: range?.$1,
        endMillis: range?.$2,
      );
      if (!mounted) return;
      _searchSetState(() {
        if (more.isEmpty) {
          _docHasMore = false;
        } else {
          _docResults.addAll(more);
          _docOffset += more.length;
          _docHasMore = more.length >= _SearchPageState._pageSize;
          _docTotalCount = _docResults.length;
        }
        _docLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      _searchSetState(() {
        _docLoadingMore = false;
        _docHasMore = false;
      });
    }
  }

  /// 格式化时间显示
  String _formatSegmentTime(int startMs, int endMs) {
    final start = DateTime.fromMillisecondsSinceEpoch(startMs);
    final end = DateTime.fromMillisecondsSinceEpoch(endMs);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final startDay = DateTime(start.year, start.month, start.day);

    String dateStr;
    if (startDay == today) {
      dateStr = AppLocalizations.of(context).filterTimeToday;
    } else if (startDay == yesterday) {
      dateStr = AppLocalizations.of(context).filterTimeYesterday;
    } else {
      dateStr = '${start.month}/${start.day}';
    }

    final startTime =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final endTime =
        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';

    return '$dateStr $startTime-$endTime';
  }

  String _todayKey() {
    final now = DateTime.now();
    final String y = now.year.toString().padLeft(4, '0');
    final String m = now.month.toString().padLeft(2, '0');
    final String d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  // 应用筛选条件（数据库层已做时间和大小过滤，此处仅同步结果列表）
  void _applyFilters() {
    // 数据库查询时已传入 startMillis/endMillis 和 minSize/maxSize，
    // 返回的 _results 已经是过滤后的数据，无需再次过滤
    _filteredResults = List.from(_results);
    // 清理超出范围的 itemKeys，避免内存泄漏
    _itemKeys.removeWhere((index, _) => index >= _filteredResults.length);
    // 重置可见范围，等待下一帧计算
    _visibleStartIndex = 0;
    _visibleEndIndex = -1;
  }
}
