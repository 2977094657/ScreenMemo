import 'package:flutter/foundation.dart';

/// 启动阶段性能记录工具
class StartupProfiler {
  static final Map<String, Stopwatch> _stopwatches = <String, Stopwatch>{};

  /// 标记一个时间点
  static void mark(String label) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[STARTUP] mark: $label @${ts}ms');
  }

  /// 开始计时某个步骤
  static void begin(String name) {
    _stopwatches[name]?.stop();
    _stopwatches[name] = Stopwatch()..start();
    debugPrint('[STARTUP] begin: $name');
  }

  /// 结束计时并打印耗时
  static void end(String name) {
    final sw = _stopwatches[name];
    if (sw != null) {
      sw.stop();
      debugPrint('[STARTUP] end: $name -> ${sw.elapsedMilliseconds}ms');
      _stopwatches.remove(name);
    } else {
      debugPrint('[STARTUP] end: $name (no stopwatch)');
    }
  }
}
