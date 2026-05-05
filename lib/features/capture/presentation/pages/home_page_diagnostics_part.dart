part of 'home_page.dart';

extension _HomePageDiagnosticsPart on _HomePageState {
  Future<void> _checkPermissionIssues({bool autoOpenDiagnostic = false}) async {
    try {
      final permissionService = PermissionService.instance;
      final permissions = await permissionService.checkAllPermissions();
      final hasIssues = _hasPermissionIssuesFrom(permissions);

      if (mounted) {
        _homeSetState(() {
          _hasPermissionIssues = hasIssues;
        });
      }
      await _refreshRuntimeDiagnosticDrawer(
        permissions: permissions,
        autoOpen: autoOpenDiagnostic,
      );
    } catch (e) {
      if (mounted) {
        _homeSetState(() {
          _hasPermissionIssues = true; // 如果检查失败，认为有问题
        });
      }
      await _refreshRuntimeDiagnosticDrawer(autoOpen: autoOpenDiagnostic);
    }
  }

  bool _hasPermissionIssuesFrom(Map<String, bool> permissions) {
    final storageGranted = permissions['storage'] ?? false;
    final notificationGranted = permissions['notification'] ?? false;
    final accessibilityEnabled = permissions['accessibility'] ?? false;
    final usageStatsGranted = permissions['usage_stats'] ?? false;
    return !storageGranted ||
        !notificationGranted ||
        !accessibilityEnabled ||
        !usageStatsGranted;
  }

  List<String> _missingPermissionLabels(Map<String, bool> permissions) {
    final missing = <String>[];
    if (!(permissions['notification'] ?? false)) {
      missing.add('通知权限');
    }
    if (!(permissions['accessibility'] ?? false)) {
      missing.add('无障碍服务');
    }
    if (!(permissions['usage_stats'] ?? false)) {
      missing.add('使用情况访问');
    }
    if (!(permissions['storage'] ?? true)) {
      missing.add('存储权限');
    }
    return missing;
  }

  Future<void> _refreshRuntimeDiagnosticDrawer({
    Map<String, bool>? permissions,
    bool autoOpen = false,
  }) async {
    final permissionService = PermissionService.instance;
    Map<String, bool>? resolvedPermissions = permissions;
    if (resolvedPermissions == null) {
      try {
        resolvedPermissions = await permissionService.checkAllPermissions();
      } catch (_) {
        resolvedPermissions = null;
      }
    }

    final nativeDiagnostic = await permissionService
        .getPendingRuntimeDiagnostic();
    final diagnostic = await _buildRuntimeDiagnosticData(
      permissions: resolvedPermissions,
      nativeDiagnostic: nativeDiagnostic,
    );

    if (!mounted) return;

    if (diagnostic == null) {
      _homeSetState(() {
        _runtimeDiagnostic = null;
        _runtimeDiagnosticExpanded = false;
      });
      return;
    }

    if (_dismissedDiagnosticIds.contains(diagnostic.id)) {
      _homeSetState(() {
        _runtimeDiagnostic = null;
        _runtimeDiagnosticExpanded = false;
      });
      return;
    }

    final shouldAutoOpen =
        autoOpen && diagnostic.id != _lastAutoOpenedDiagnosticId;

    _homeSetState(() {
      _runtimeDiagnostic = diagnostic;
      if (shouldAutoOpen) {
        _runtimeDiagnosticExpanded = true;
        _lastAutoOpenedDiagnosticId = diagnostic.id;
      }
    });
  }

  Future<_HomeRuntimeDiagnostic?> _buildRuntimeDiagnosticData({
    required Map<String, bool>? permissions,
    required Map<String, dynamic>? nativeDiagnostic,
  }) async {
    final resolvedPermissions = permissions ?? const <String, bool>{};
    final missingPermissions = permissions == null
        ? const <String>[]
        : _missingPermissionLabels(resolvedPermissions);
    final hasPermissionIssues = missingPermissions.isNotEmpty;
    if (!hasPermissionIssues && nativeDiagnostic == null) {
      return null;
    }

    final permissionService = PermissionService.instance;
    final fallbackLogFile =
        nativeDiagnostic?['logFilePath']?.toString().trim().isNotEmpty == true
        ? nativeDiagnostic!['logFilePath'].toString()
        : await _getTodayInfoLogPath();
    final nativeCopyText = nativeDiagnostic?['copyText']?.toString().trim();
    final nativeSummary = nativeDiagnostic?['summary']?.toString().trim();
    final nativeDetectedAt = _formatDiagnosticTime(
      nativeDiagnostic?['detectedAt'],
    );

    if (hasPermissionIssues) {
      final permissionReport = await permissionService.getPermissionReport();
      final details = <String>[
        '缺失权限：${missingPermissions.join('、')}',
        if (nativeSummary != null && nativeSummary.isNotEmpty)
          '最近异常：$nativeSummary',
        if (nativeDetectedAt != null) '诊断记录时间：$nativeDetectedAt',
        if (fallbackLogFile != null && fallbackLogFile.isNotEmpty)
          '日志文件：$fallbackLogFile',
      ];
      final summary = nativeSummary != null && nativeSummary.isNotEmpty
          ? '检测到权限异常，同时存在最近一次运行异常记录。'
          : '检测到权限状态异常，可能导致通知还在但无法正常截屏。';
      final buffer = StringBuffer()
        ..writeln('首页运行诊断')
        ..writeln('================')
        ..writeln('诊断类型: permission_issue')
        ..writeln('缺失权限: ${missingPermissions.join(', ')}');
      if (permissionReport != null && permissionReport.trim().isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(permissionReport.trim());
      }
      if (nativeCopyText != null && nativeCopyText.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('最近一次运行异常')
          ..writeln(nativeCopyText);
      }
      if (fallbackLogFile != null && fallbackLogFile.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln('建议打开日志文件: $fallbackLogFile');
      }
      return _HomeRuntimeDiagnostic(
        id: 'permission:${missingPermissions.join('|')}:${nativeDiagnostic?['id'] ?? '-'}',
        title: '检测到权限或运行异常',
        summary: summary,
        details: details,
        copyText: buffer.toString().trim(),
        filePath: fallbackLogFile,
        nativeIssueId: nativeDiagnostic?['id']?.toString(),
        showSettingsAction: true,
      );
    }

    final details = <String>[
      if (nativeDetectedAt != null) '诊断记录时间：$nativeDetectedAt',
      if (nativeDiagnostic?['summary'] != null &&
          nativeDiagnostic!['summary'].toString().trim().isNotEmpty)
        '异常摘要：${nativeDiagnostic['summary']}',
      if (fallbackLogFile != null && fallbackLogFile.isNotEmpty)
        '日志文件：$fallbackLogFile',
    ];
    return _HomeRuntimeDiagnostic(
      id:
          nativeDiagnostic?['id']?.toString() ??
          'runtime:${DateTime.now().millisecondsSinceEpoch}',
      title: nativeDiagnostic?['title']?.toString() ?? '检测到运行异常',
      summary: nativeDiagnostic?['summary']?.toString() ?? '检测到最近一次运行异常。',
      details: details,
      copyText: nativeCopyText?.isNotEmpty == true
          ? nativeCopyText!
          : [
              '首页运行诊断',
              '================',
              '诊断类型: ${nativeDiagnostic?['type'] ?? 'runtime_issue'}',
              if (nativeSummary != null && nativeSummary.isNotEmpty)
                '摘要: $nativeSummary',
              if (nativeDetectedAt != null) '诊断记录时间: $nativeDetectedAt',
              if (fallbackLogFile != null && fallbackLogFile.isNotEmpty)
                '日志文件: $fallbackLogFile',
            ].join('\n'),
      filePath: fallbackLogFile,
      nativeIssueId: nativeDiagnostic?['id']?.toString(),
    );
  }

  String? _formatDiagnosticTime(dynamic rawValue) {
    final millis = rawValue is num
        ? rawValue.toInt()
        : int.tryParse(rawValue?.toString() ?? '');
    if (millis == null || millis <= 0) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Future<String?> _getTodayInfoLogPath() async {
    final dir = await FlutterLogger.getTodayLogsDir();
    if (dir == null || dir.trim().isEmpty) return null;
    final normalized = dir.replaceAll('\\', '/');
    final segments = normalized.split('/');
    final day = segments.isEmpty ? '' : segments.last;
    if (day.isEmpty) return null;
    final separator = dir.contains('\\') ? '\\' : '/';
    return '$dir$separator${day}_info.log';
  }

  Future<void> _copyRuntimeDiagnostic() async {
    final diagnostic = _runtimeDiagnostic;
    if (diagnostic == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: diagnostic.copyText));
      if (!mounted) return;
      UINotifier.success(
        context,
        AppLocalizations.of(context).runtimeDiagnosticCopied,
      );
    } catch (_) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).runtimeDiagnosticCopyFailed,
      );
    }
  }

  Future<void> _openRuntimeDiagnosticFile() async {
    final diagnostic = _runtimeDiagnostic;
    final filePath = diagnostic?.filePath;
    if (diagnostic == null || filePath == null || filePath.trim().isEmpty) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).runtimeDiagnosticNoFileToOpen,
      );
      return;
    }

    final opened = await PermissionService.instance.openDiagnosticFile(
      filePath,
    );
    if (!mounted) return;
    if (opened) {
      UINotifier.info(
        context,
        AppLocalizations.of(context).runtimeDiagnosticOpenAttempted,
      );
    } else {
      await Clipboard.setData(ClipboardData(text: filePath));
      if (!mounted) return;
      UINotifier.warning(
        context,
        AppLocalizations.of(context).runtimeDiagnosticOpenFallbackCopiedPath,
      );
    }
  }

  Future<void> _dismissRuntimeDiagnosticDrawer() async {
    final diagnostic = _runtimeDiagnostic;
    if (diagnostic == null) return;
    _dismissedDiagnosticIds.add(diagnostic.id);
    final nativeIssueId = diagnostic.nativeIssueId;
    if (nativeIssueId != null && nativeIssueId.isNotEmpty) {
      await PermissionService.instance.markRuntimeDiagnosticHandled(
        nativeIssueId,
      );
    }
    if (!mounted) return;
    _homeSetState(() {
      _runtimeDiagnostic = null;
      _runtimeDiagnosticExpanded = false;
    });
  }

  Future<void> _openSettingsFromDiagnostic() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(themeService: widget.themeService),
      ),
    );
    if (!mounted) return;
    await _checkPermissionIssues(autoOpenDiagnostic: true);
  }

  /// 检查截屏开关状态是否需要自动关闭
  Future<void> _checkScreenshotToggleState() async {
    // 如果截屏开关是关闭状态，无需检查
    if (!_screenshotEnabled) return;

    try {
      // 实时检查权限状态
      final permissionService = PermissionService.instance;
      final permissions = await permissionService.checkAllPermissions();

      // 检查所有关键权限
      final storageGranted = permissions['storage'] ?? false;
      final notificationGranted = permissions['notification'] ?? false;
      final accessibilityEnabled = permissions['accessibility'] ?? false;
      final usageStatsGranted = permissions['usage_stats'] ?? false;

      final hasPermissionIssues =
          !storageGranted ||
          !notificationGranted ||
          !accessibilityEnabled ||
          !usageStatsGranted;

      // 如果有权限问题，自动关闭截屏开关
      if (hasPermissionIssues) {
        await _appService.saveScreenshotEnabled(false);
        if (mounted) {
          _homeSetState(() {
            _screenshotEnabled = false;
          });

          UINotifier.info(
            context,
            AppLocalizations.of(context).autoDisabledDueToPermissions,
            duration: const Duration(seconds: 3),
          );
        }
      }
    } catch (e) {
      print('检查截屏开关状态失败: $e');
    }
  }
}
