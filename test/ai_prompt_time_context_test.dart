import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/ai_prompt_time_context.dart';

void main() {
  test('buildPromptLocalDateTime includes seconds and timezone offset', () {
    final DateTime now = DateTime.utc(2026, 3, 24, 16, 37, 14);

    expect(buildPromptLocalDateTime(now), '2026-03-24T16:37:14+00:00');
  });

  test(
    'buildCurrentDateTimeSystemMessage includes authoritative time hint',
    () {
      final DateTime now = DateTime.utc(2026, 3, 24, 16, 37, 14);

      final String zh = buildCurrentDateTimeSystemMessage(
        const Locale('zh'),
        now: now,
      );
      final String en = buildCurrentDateTimeSystemMessage(
        const Locale('en'),
        now: now,
      );

      expect(zh, contains('2026-03-24T16:37:14+00:00'));
      expect(zh, contains('当前设备本地日期时间'));
      expect(zh, contains('今天 / 明天 / 昨天 / 现在'));

      expect(en, contains('2026-03-24T16:37:14+00:00'));
      expect(en, contains('Current device-local datetime'));
      expect(en, contains('today / tomorrow / yesterday / now'));
    },
  );
}
