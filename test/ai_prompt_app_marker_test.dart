import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/features/ai/application/ai_prompt_time_context.dart';

void main() {
  test('buildAppMarkerSystemMessage describes app marker formats', () {
    final String zh = buildAppMarkerSystemMessage(const Locale('zh'));
    final String en = buildAppMarkerSystemMessage(const Locale('en'));

    expect(zh, contains('[app: 应用名]'));
    expect(zh, contains('[app: 应用名|应用包名]'));
    expect(zh, contains('com.tencent.mm'));

    expect(en, contains('[app: App Name]'));
    expect(en, contains('[app: App Name|app.package.name]'));
    expect(en, contains('com.tencent.mobileqq'));
  });
}
