import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/user_memory_service.dart';

void main() {
  test('sliceLines returns requested 1-based line window', () {
    const String text = 'a\nb\nc\nd\ne';

    expect(UserMemoryService.sliceLines(text, fromLine: 1, lines: 2), 'a\nb');
    expect(
      UserMemoryService.sliceLines(text, fromLine: 2, lines: 3),
      'b\nc\nd',
    );
    expect(UserMemoryService.sliceLines(text, fromLine: 5, lines: 10), 'e');
    expect(UserMemoryService.sliceLines(text, fromLine: 6, lines: 10), '');
  });
}
