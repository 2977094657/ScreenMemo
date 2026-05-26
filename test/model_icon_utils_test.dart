import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/core/utils/model_icon_utils.dart';

void main() {
  group('ModelIconUtils.getIconPath', () {
    test('treats GPT Codex models with spark suffix as OpenAI models', () {
      expect(
        ModelIconUtils.getIconPath('gpt-5.3-codex-spark'),
        'assets/icons/ai/openai.svg',
      );
      expect(
        ModelIconUtils.getIconPath('gpt-5.3-codex-spark-openai-compact'),
        'assets/icons/ai/openai.svg',
      );
    });

    test('keeps real Spark model names on the Spark icon', () {
      expect(
        ModelIconUtils.getIconPath('spark-max'),
        'assets/icons/ai/spark-color.svg',
      );
      expect(
        ModelIconUtils.getIconPath('iflytek-spark'),
        'assets/icons/ai/spark-color.svg',
      );
    });
  });
}
