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
    debugPrint('[启动] 标记：$label @${ts}毫秒');
  }

  /// 开始计时某个步骤
  static void begin(String name) {
    _stopwatches[name]?.stop();
    _stopwatches[name] = Stopwatch()..start();
    if (!enabled) return;
    debugPrint('[启动] 开始：$name');
  }

  /// 结束计时并打印耗时
  static void end(String name) {
    final sw = _stopwatches[name];
    if (sw != null) {
      sw.stop();
      if (enabled) {
        debugPrint('[启动] 结束：$name，耗时 ${sw.elapsedMilliseconds} 毫秒');
      }
      _stopwatches.remove(name);
    } else {
      if (enabled) {
        debugPrint('[启动] 结束：$name（无计时器）');
      }
    }
  }
}
