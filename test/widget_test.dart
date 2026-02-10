// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_memo/main.dart';
import 'package:screen_memo/services/intent_analysis_service.dart';
import 'package:screen_memo/services/weekly_summary_service.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ScreenMemoApp(
        initialShowOnboarding: true,
        isFirstLaunch: true,
      ),
    );
    // Let post-frame callbacks / zero-duration timers settle.
    await tester.pump();
    // Smoke-test: app widget tree mounts without throwing.
    expect(find.byType(MaterialApp), findsOneWidget);
    // Advance fake time a bit to flush internal zero-delay timers (e.g. scroll physics).
    await tester.pump(const Duration(seconds: 1));
  });

  test('IntentAnalysisService basic structure fallback', () async {
    final svc = IntentAnalysisService.instance;
    final r = await svc.analyze('测试一个不明确的查询');
    expect(r.intentSummary.isNotEmpty, true);
    expect(r.hasValidRange, false);
    expect(r.sqlFill.containsKey('segments_between'), false);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('WeeklySummaryService sanitizeWeeklyRows removes overlapping weeks', () {
    final rows = <Map<String, dynamic>>[
      {
        'week_start_date': '2025-12-06',
        'week_end_date': '2025-12-12',
      },
      {
        'week_start_date': '2025-12-01',
        'week_end_date': '2025-12-07',
      },
      {
        'week_start_date': '2025-11-29',
        'week_end_date': '2025-12-05',
      },
    ];

    final sanitized = WeeklySummaryService.sanitizeWeeklyRows(rows);
    expect(
      sanitized.map((e) => e['week_start_date']).toList(),
      ['2025-12-06', '2025-11-29'],
    );
  });
}
