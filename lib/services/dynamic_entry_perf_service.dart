import 'dart:async';

import 'flutter_logger.dart';

class DynamicEntryPerfService {
  DynamicEntryPerfService._();

  static final DynamicEntryPerfService instance = DynamicEntryPerfService._();

  static const String logTag = 'DynamicEnter';

  int _nextSessionId = 0;
  int? _sessionId;
  Stopwatch? _stopwatch;

  int beginSession({required String source, String? detail}) {
    _sessionId = ++_nextSessionId;
    _stopwatch = Stopwatch()..start();
    _write('session.begin', detail: _mergeDetail('source=$source', detail));
    return _sessionId!;
  }

  int ensureSession({required String source, String? detail}) {
    final int? current = _sessionId;
    final Stopwatch? sw = _stopwatch;
    if (current != null && sw != null && sw.isRunning) {
      return current;
    }
    return beginSession(source: source, detail: detail);
  }

  void mark(String step, {String? detail}) {
    if (_sessionId == null || _stopwatch == null) return;
    _write(step, detail: detail);
  }

  void finish(String step, {String? detail}) {
    if (_sessionId == null || _stopwatch == null) return;
    _write(step, detail: _mergeDetail(detail, 'finished'));
    _stopwatch
      ?..stop()
      ..reset();
    _stopwatch = null;
    _sessionId = null;
  }

  String _mergeDetail(String? a, String? b) {
    final List<String> parts = <String>[];
    final String a1 = (a ?? '').trim();
    final String b1 = (b ?? '').trim();
    if (a1.isNotEmpty) parts.add(a1);
    if (b1.isNotEmpty) parts.add(b1);
    return parts.join(' | ');
  }

  void _write(String step, {String? detail}) {
    final int? sessionId = _sessionId;
    final Stopwatch? sw = _stopwatch;
    if (sessionId == null || sw == null) return;
    final String d = (detail ?? '').trim();
    final String msg = d.isEmpty
        ? 'session#$sessionId +${sw.elapsedMilliseconds}ms $step'
        : 'session#$sessionId +${sw.elapsedMilliseconds}ms $step | $d';
    unawaited(FlutterLogger.nativeInfo(logTag, msg));
  }
}
