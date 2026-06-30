import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/core/utils/json_string_field_extractor.dart';

void main() {
  test('extracts normal overall_summary from a JSON object', () {
    expect(
      extractOverallSummaryFromRaw(
        r'{"overall_summary":"hello\nworld","timeline":[]}',
      ),
      'hello\nworld',
    );
  });

  test('extracts from a DB preview fragment that starts at the key', () {
    expect(
      extractOverallSummaryFromRaw(
        r'"overall_summary":"preview summary","timeline":[]',
      ),
      'preview summary',
    );
  });

  test('returns a safe prefix when the preview cuts before closing quote', () {
    expect(
      extractOverallSummaryFromRaw(r'"overall_summary":"preview\nsummary'),
      'preview\nsummary',
    );
  });

  test('extracts when JSON was stored as an escaped JSON string fragment', () {
    expect(
      extractOverallSummaryFromRaw(
        r'\"overall_summary\":\"escaped\nsummary\",\"timeline\":[]',
      ),
      'escaped\nsummary',
    );
  });

  test('does not stop on unescaped quotes inside model output text', () {
    expect(
      extractOverallSummaryFromRaw(
        r'{"overall_summary":"opened "Settings" and continued","timeline":[]}',
      ),
      'opened "Settings" and continued',
    );
  });
}
