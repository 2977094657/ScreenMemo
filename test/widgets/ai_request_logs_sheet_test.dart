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
}
