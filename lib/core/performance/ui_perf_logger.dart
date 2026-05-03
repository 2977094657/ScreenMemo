import 'package:flutter/foundation.dart';

@immutable
class UiPerfEvent {
  const UiPerfEvent({
    required this.seq,
    required this.elapsedMs,
    required this.name,
    this.detail,
  });

  final int seq;
  final int elapsedMs;
  final String name;
  final String? detail;

  String formatLine() {
    final String d = (detail ?? '').trim();
    if (d.isEmpty) return '+${elapsedMs}ms $name';
    return '+${elapsedMs}ms $name | $d';
  }
}

/// Lightweight, UI-friendly perf logger (keeps a bounded in-memory ring).
///
/// Intended for in-page timing overlays (e.g. AI chat image render pipeline).
class UiPerfLogger {
  UiPerfLogger({this.scope = '', int maxEvents = 200})
    : _maxEvents = maxEvents.clamp(20, 2000),
      _sw = Stopwatch()..start();

  final String scope;
  final Stopwatch _sw;
  final int _maxEvents;

  int _seq = 0;

  final ValueNotifier<List<UiPerfEvent>> events =
      ValueNotifier<List<UiPerfEvent>>(<UiPerfEvent>[]);

  int get elapsedMs => _sw.elapsedMilliseconds;

  void log(String name, {String? detail}) {
    final UiPerfEvent ev = UiPerfEvent(
      seq: _seq++,
      elapsedMs: _sw.elapsedMilliseconds,
      name: name,
      detail: detail,
    );
    final List<UiPerfEvent> next = List<UiPerfEvent>.from(events.value)
      ..add(ev);
    if (next.length > _maxEvents) {
      next.removeRange(0, next.length - _maxEvents);
    }
    events.value = next;
  }

  void clear({bool restart = true}) {
    events.value = <UiPerfEvent>[];
    if (restart) {
      _sw
        ..reset()
        ..start();
      _seq = 0;
    }
  }

  void dispose() {
    events.dispose();
  }
}
