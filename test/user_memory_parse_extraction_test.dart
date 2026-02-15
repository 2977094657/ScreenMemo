import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/user_memory_service.dart';

void main() {
  test('parseExtractionFromModelText handles JSON + evidence filtering', () {
    const String raw = '''
```json
{
  "items": [
    {
      "kind": "habit",
      "key": "ui_theme",
      "content": "Prefers dark mode.",
      "keywords": ["dark", "theme"],
      "confidence": 0.8,
      "evidence": ["a.png", "b.png"]
    }
  ]
}
```''';

    final items = UserMemoryService.parseExtractionFromModelText(
      raw,
      allowedEvidenceFilenames: const {'a.png'},
    );

    expect(items.length, 1);
    expect(items.first.kind, 'habit');
    expect(items.first.key, 'ui_theme');
    expect(items.first.content, 'Prefers dark mode.');
    expect(items.first.keywords, contains('dark'));
    expect(items.first.evidenceFilenames, ['a.png']);
  });

  test(
    'parseExtractionFromModelText extracts first JSON object from noisy output',
    () {
      const String raw = '''
Some preface text...
{
  "items": [
    "User likes short answers",
    {"kind":"weird","content":"Unknown kind becomes fact","evidence":"x.png"}
  ]
}
Some trailing text...''';

      final items = UserMemoryService.parseExtractionFromModelText(
        raw,
        allowedEvidenceFilenames: const {'x.png'},
      );

      expect(items.length, 2);
      expect(items[0].kind, 'fact');
      expect(items[0].content, 'User likes short answers');
      expect(items[1].kind, 'fact'); // sanitized
      expect(items[1].evidenceFilenames, ['x.png']);
    },
  );
}
