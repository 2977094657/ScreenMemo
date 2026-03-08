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
}
