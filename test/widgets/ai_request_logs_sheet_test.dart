import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/models/ai_request_log.dart';
import 'package:screen_memo/widgets/ai_request_logs_sheet.dart';
import 'package:screen_memo/widgets/ai_request_logs_viewer.dart';

void main() {
  testWidgets('AIRequestLogsSheet is shown as bottom sheet, not AlertDialog', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await AIRequestLogsSheet.show(
                      context: context,
                      title: 'Request/Response Logs',
                      body: const Text('logs-body'),
                    );
                  },
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Request/Response Logs'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('AIRequestLogsSheet expandBody gives the body finite height', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await AIRequestLogsSheet.show(
                      context: context,
                      title: 'Request/Response Logs',
                      expandBody: true,
                      body: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints c) {
                          final bool finite =
                              c.maxHeight.isFinite && c.maxHeight > 0;
                          return Text(finite ? 'finite-body' : 'infinite-body');
                        },
                      ),
                    );
                  },
                  child: const Text('open-expand'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-expand'));
    await tester.pumpAndSettle();

    expect(find.text('finite-body'), findsOneWidget);
    expect(find.text('infinite-body'), findsNothing);
  });

  testWidgets(
    'AIRequestLogsViewer renders tab panels and can switch to request tab',
    (WidgetTester tester) async {
      final String rawReq = [
        '=== AI Request',
        'segment_id=123',
        'provider=openai',
        'model=gpt-4.1-mini',
        'prompt:',
        'hello world',
      ].join('\n');
      final AIRequestTrace trace = AIRequestTrace(
        source: AIRequestLogSource.aiTrace,
        rawBlocks: <String>[rawReq],
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AIRequestLogsViewer.traces(
              traces: <AIRequestTrace>[trace],
              scrollable: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Prompt'), findsNothing);

      await tester.tap(find.text('Request').first);
      await tester.pumpAndSettle();

      expect(find.text('Prompt'), findsOneWidget);
      expect(find.textContaining('hello world'), findsOneWidget);
    },
  );

  testWidgets(
    'segment trace viewer shows four equal tabs and supports bottom-area swipe',
    (WidgetTester tester) async {
      final String rawReq = [
        '=== AI Request ===',
        'segment_id=123',
        'provider=openai',
        'model=gpt-4.1-mini',
        'prompt:',
        'first line',
        '   ',
        'second line',
      ].join('\n');
      final String rawResp = [
        'data: {"choices":[{"delta":{"content":"hello"}}]}',
        '',
        '   ',
        'data: {"choices":[{"delta":{"content":" world"}}]}',
      ].join('\n');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 420,
              child: AIRequestLogsViewer.fromSegmentTrace(
                rawRequest: rawReq,
                rawResponse: rawResp,
                scrollable: true,
                maxHeight: 420,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Request'), findsOneWidget);
      expect(find.text('Response'), findsOneWidget);
      expect(find.text('Raw Response'), findsOneWidget);

      final Rect rect = tester.getRect(find.byType(AIRequestLogsViewer));
      final Offset bottomBlankArea = Offset(rect.center.dx, rect.bottom - 12);
      await tester.dragFrom(bottomBlankArea, const Offset(-220, 0));
      await tester.pumpAndSettle();

      expect(find.text('Prompt'), findsOneWidget);
      expect(find.textContaining('second line'), findsOneWidget);

      await tester.dragFrom(bottomBlankArea, const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('hello world'), findsOneWidget);

      await tester.dragFrom(bottomBlankArea, const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('data: {"choices"'), findsOneWidget);
    },
  );
}
