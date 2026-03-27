import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphic/graphic.dart';
import 'package:screen_memo/widgets/chat_markdown_chart.dart';
import 'package:screen_memo/widgets/markdown_math.dart';

void main() {
  test('ChartSpecV1 parses all supported chart types', () {
    final Map<String, String> payloads = <String, String>{
      'line':
          '{"type":"line","title":"Trend","x":["Mon","Tue"],"series":[{"name":"Count","data":[1,2]}]}',
      'bar':
          '{"type":"bar","title":"Compare","x":["A","B"],"series":[{"name":"Count","data":[3,4]}]}',
      'area':
          '{"type":"area","title":"Area","x":["A","B"],"series":[{"name":"Count","data":[3,4]}]}',
      'pie':
          '{"type":"pie","title":"Share","x":["A","B"],"series":[{"name":"Share","data":[40,60]}]}',
      'scatter':
          '{"type":"scatter","title":"Scatter","x":["P1","P2"],"series":[{"name":"Value","data":[7,9]}]}',
    };

    for (final MapEntry<String, String> entry in payloads.entries) {
      final ChatChartSpecV1? spec = ChatChartSpecV1.tryParseJson(entry.value);
      expect(spec, isNotNull, reason: entry.key);
    }
  });

  test('ChartSpecV1 rejects invalid schema', () {
    expect(
      ChatChartSpecV1.tryParseJson(
        '{"type":"pie","x":["A","B"],"series":[{"data":[1]},{"data":[2]}]}',
      ),
      isNull,
    );
    expect(
      ChatChartSpecV1.tryParseJson(
        '{"type":"line","x":["A"],"series":[{"data":[1,2]}]}',
      ),
      isNull,
    );
    expect(
      ChatChartSpecV1.tryParseJson(
        '{"type":"heatmap","series":[{"data":[1]}]}',
      ),
      isNull,
    );
    expect(ChatChartSpecV1.tryParseJson('{not-json}'), isNull);
  });

  test('chart-v1 fence payload round-trips for copy/share', () {
    const String rawJson =
        '{"type":"bar","x":["A","B"],"series":[{"name":"Count","data":[1,2]}]}';

    final String fence = buildChartV1FenceMarkdown(rawJson);
    expect(extractChartV1FencePayload(fence), rawJson);
    expect(fence, contains(rawJson));
  });

  test('preprocess leaves chart fences intact for block syntax parsing', () {
    const String completed = '''
Before

```chart-v1
{"type":"line","x":["Mon","Tue"],"series":[{"name":"Count","data":[1,2]}]}
```

After
''';
    final String processed = preprocessForChatMarkdown(completed);
    expect(processed, contains('```chart-v1'));
    expect(processed, isNot(contains('<$kChartBlockTag>')));

    const String incomplete = '''
Before

```chart-v1
{"type":"line","x":["Mon","Tue"],"series":[{"name":"Count","data":[1,2]}]}
''';
    final String incompleteProcessed = preprocessForChatMarkdown(incomplete);
    expect(incompleteProcessed, contains('```chart-v1'));
    expect(incompleteProcessed, isNot(contains('<$kChartBlockTag>')));
  });

  testWidgets('Markdown renders text and chart block together', (
    WidgetTester tester,
  ) async {
    const String markdown = '''
Before chart

```chart-v1
{"type":"line","title":"Recent trend","x":["Mon","Tue","Wed"],"series":[{"name":"Count","data":[1,2,3]}],"y":{"label":"Shots"},"note":"Trend is rising."}
```

After chart
''';

    final MarkdownMathConfig config = MarkdownMathConfig();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: preprocessForChatMarkdown(markdown),
            builders: config.builders,
            blockSyntaxes: config.blockSyntaxes,
            inlineSyntaxes: config.inlineSyntaxes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChatMarkdownChartBlock), findsOneWidget);
    expect(find.byType(Chart), findsOneWidget);
    expect(find.text('Recent trend'), findsOneWidget);
    expect(find.text('Trend is rising.'), findsOneWidget);
    expect(
      find.textContaining('Before chart', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('After chart', findRichText: true),
      findsOneWidget,
    );

    final Size size = tester.getSize(find.byType(ChatMarkdownChartBlock));
    expect(size.height, greaterThan(200));
    expect(size.width, greaterThan(0));
  });

  testWidgets('invalid chart block degrades to raw fenced code', (
    WidgetTester tester,
  ) async {
    const String markdown = '''
```chart-v1
{"type":"pie","x":["A","B"],"series":[{"data":[1]},{"data":[2]}]}
```
''';
    final MarkdownMathConfig config = MarkdownMathConfig();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: preprocessForChatMarkdown(markdown),
            builders: config.builders,
            blockSyntaxes: config.blockSyntaxes,
            inlineSyntaxes: config.inlineSyntaxes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Chart), findsNothing);
    expect(find.byType(ChatMarkdownChartBlock), findsOneWidget);
    expect(find.textContaining('```chart-v1'), findsOneWidget);
  });

  testWidgets('incomplete chart fence does not render chart widget', (
    WidgetTester tester,
  ) async {
    const String markdown = '''
Before

```chart-v1
{"type":"line","x":["Mon","Tue"],"series":[{"name":"Count","data":[1,2]}]}
''';
    final MarkdownMathConfig config = MarkdownMathConfig();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: preprocessForChatMarkdown(markdown),
            builders: config.builders,
            blockSyntaxes: config.blockSyntaxes,
            inlineSyntaxes: config.inlineSyntaxes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChatMarkdownChartBlock), findsNothing);
    expect(find.byType(Chart), findsNothing);
    expect(find.textContaining('```chart-v1'), findsOneWidget);
  });
}
