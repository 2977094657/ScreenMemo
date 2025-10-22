import 'package:flutter/foundation.dart';

/// 启动阶段性能记录工具
class StartupProfiler {
  // 统一开关：默认关闭，避免刷屏；仅需要时在调试处手动开启
  static bool enabled = false;
  static final Map<String, Stopwatch> _stopwatches = <String, Stopwatch>{};

  /// 标记一个时间点
  static void mark(String label) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    if (!enabled) return;
    debugPrint('[STARTUP] mark: $label @${ts}ms');
  }

  /// 开始计时某个步骤
  static void begin(String name) {
    _stopwatches[name]?.stop();
    _stopwatches[name] = Stopwatch()..start();
    if (!enabled) return;
    debugPrint('[STARTUP] begin: $name');
  }

  /// 结束计时并打印耗时
  static void end(String name) {
    final sw = _stopwatches[name];
    if (sw != null) {
      sw.stop();
      if (enabled) {
        debugPrint('[STARTUP] end: $name -> ${sw.elapsedMilliseconds}ms');
      }
      _stopwatches.remove(name);
    } else {
      if (enabled) {
        debugPrint('[STARTUP] end: $name (no stopwatch)');
      }
    }
  }
}
