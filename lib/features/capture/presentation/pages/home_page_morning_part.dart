part of 'home_page.dart';

extension _HomePageMorningPart on _HomePageState {
  String get _todayKey {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-${two(now.day)}';
  }

  Future<void> _preloadMorningInsights() async {
    try {
      final insights = await _dailySummaryService.loadMorningInsights(
        _todayKey,
      );
      if (!mounted) return;
      if (insights != null && insights.tips.isNotEmpty) {
        _homeSetState(() {
          _resetMorningDeckForInsights(insights);
          _morningInsights = insights;
          if (_morningTipIndex >= insights.tips.length) {
            _morningTipIndex = -1;
            _currentMorningTip = null;
          }
        });
      } else {
        _homeSetState(() {
          _morningInsights = null;
          _morningTipIndex = -1;
          _currentMorningTip = null;
          _clearMorningDeck();
        });
      }
    } catch (_) {
      // 静默忽略，避免影响首屏加载
    }
  }

  Future<void> _cycleMorningTip({bool ensureGenerate = false}) async {
    if (ensureGenerate && _morningGenerationRunning) {
      if (!mounted) return;
      _homeSetState(() {
        _morningInsights = null;
        _morningTipIndex = -1;
        _currentMorningTip = null;
        _clearMorningDeck();
      });
      return;
    }

    try {
      MorningInsights? insights;

      if (ensureGenerate) {
        insights = await _dailySummaryService.loadMorningInsights(_todayKey);
        if (!mounted) return;

        final bool missing = insights == null || insights.tips.isEmpty;
        if (missing) {
          if (_morningGenerationRunning) {
            _homeSetState(() {
              _morningInsights = null;
              _morningTipIndex = -1;
              _currentMorningTip = null;
              _clearMorningDeck();
            });
            return;
          }

          _homeSetState(() {
            _morningGenerationRunning = true;
            _morningInsights = null;
            _morningTipIndex = -1;
            _currentMorningTip = null;
            _clearMorningDeck();
          });
          MorningInsights? generated;
          try {
            generated = await _dailySummaryService.generateMorningInsights(
              _todayKey,
            );
            if (!mounted) return;
            if (generated == null || generated.tips.isEmpty) {
              _homeSetState(() {
                _morningInsights = null;
                _morningTipIndex = -1;
                _currentMorningTip = null;
                _clearMorningDeck();
              });
            } else {
              _applyMorningInsights(generated);
            }
          } catch (_) {
            if (!mounted) return;
            _homeSetState(() {
              _morningInsights = null;
              _morningTipIndex = -1;
              _currentMorningTip = null;
              _clearMorningDeck();
            });
          } finally {
            if (mounted) {
              _homeSetState(() {
                _morningGenerationRunning = false;
              });
            } else {
              _morningGenerationRunning = false;
            }
          }
          return;
        }
      }

      insights ??= await _dailySummaryService.fetchOrGenerateMorningInsights(
        _todayKey,
      );
      if (!mounted) return;
      if (insights == null || insights.tips.isEmpty) {
        _homeSetState(() {
          _morningInsights = insights;
          _morningTipIndex = -1;
          _currentMorningTip = null;
          _clearMorningDeck();
        });
        return;
      }

      _applyMorningInsights(insights);
    } catch (_) {
      if (!mounted) return;
      _homeSetState(() {
        _morningTipIndex = -1;
        _currentMorningTip = null;
        _clearMorningDeck();
      });
    }
  }

  void _clearMorningDeck() {
    _morningTipDeck = <int>[];
    _morningTipDeckSignature = null;
    _lastMorningTipIndex = null;
  }

  void _resetMorningDeckForInsights(MorningInsights insights) {
    final String signature = _buildMorningDeckSignature(insights);
    if (_morningTipDeckSignature != signature) {
      _morningTipDeckSignature = signature;
      _morningTipDeck = <int>[];
      _lastMorningTipIndex = null;
    }
  }

  String _buildMorningDeckSignature(MorningInsights insights) {
    return '${insights.dateKey}|${insights.sourceDateKey}|${insights.tips.length}|${insights.createdAt}';
  }

  void _rebuildMorningDeck(int total, {int? exclude}) {
    if (total <= 0) {
      _morningTipDeck = <int>[];
      return;
    }
    final List<int> indices = List<int>.generate(total, (index) => index);
    indices.shuffle(_random);
    if (exclude != null &&
        total > 1 &&
        indices.isNotEmpty &&
        indices.first == exclude) {
      final int swapIndex = indices.indexWhere((value) => value != exclude, 1);
      if (swapIndex != -1) {
        final int temp = indices[0];
        indices[0] = indices[swapIndex];
        indices[swapIndex] = temp;
      }
    }
    _morningTipDeck = indices;
  }

  void _applyMorningInsights(MorningInsights insights) {
    if (!mounted) return;
    final List<MorningInsightEntry> tips = insights.tips;
    _resetMorningDeckForInsights(insights);
    if (_morningTipDeck.isEmpty) {
      _rebuildMorningDeck(tips.length, exclude: _lastMorningTipIndex);
    }
    int nextIndex;
    if (_morningTipDeck.isNotEmpty) {
      nextIndex = _morningTipDeck.removeAt(0);
    } else {
      nextIndex = tips.length <= 1 ? 0 : _random.nextInt(tips.length);
      if (_lastMorningTipIndex != null &&
          tips.length > 1 &&
          nextIndex == _lastMorningTipIndex) {
        nextIndex = (nextIndex + 1) % tips.length;
      }
    }
    _homeSetState(() {
      _morningInsights = insights;
      _morningTipIndex = nextIndex;
      _currentMorningTip = tips[nextIndex];
    });
    _lastMorningTipIndex = nextIndex;
  }

  Future<void> _openMorningSummary() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DailySummaryPage(dateKey: _todayKey)),
    );
  }

  Future<void> _handleHomeRefresh() async {
    IndicatorResult result = IndicatorResult.success;
    final now = DateTime.now();
    final l10n = AppLocalizations.of(context);

    if (!_isMorningInsightsAvailable(now)) {
      _homeSetState(() {
        _morningCooldownMessage = null;
        _morningCooldownUntil = null;
        _morningInsights = null;
        _morningTipIndex = -1;
        _currentMorningTip = null;
        _clearMorningDeck();
      });
      _refreshController.finishRefresh(result);
      return;
    }

    if (_morningCooldownUntil != null && now.isBefore(_morningCooldownUntil!)) {
      _homeSetState(() {
        _morningCooldownMessage = l10n.homeMorningTipsCooldownMessage;
      });
      _refreshController.finishRefresh(result);
      return;
    }

    _morningRefreshHistory.removeWhere(
      (ts) => now.difference(ts) > _HomePageState._morningRefreshWindow,
    );
    if (_morningRefreshHistory.length >=
        _HomePageState._morningMaxRefreshInWindow) {
      _homeSetState(() {
        _morningCooldownUntil = now.add(
          _HomePageState._morningCooldownDuration,
        );
        _morningCooldownMessage = l10n.homeMorningTipsCooldownMessage;
      });
      _refreshController.finishRefresh(result);
      return;
    }

    try {
      _morningRefreshHistory.add(now);
      await _loadData(soft: true);
      await _cycleMorningTip(ensureGenerate: true);
      if (mounted) {
        _homeSetState(() {
          _morningCooldownMessage = null;
        });
      }
    } catch (_) {
      result = IndicatorResult.fail;
    } finally {
      if (mounted) {
        _refreshController.finishRefresh(result);
      }
    }
  }
}
