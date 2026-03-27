import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/ai_prompt_time_context.dart';
import 'package:screen_memo/utils/app_ref_markdown.dart';

void main() {
  test('normalizeCodeWrappedAppRefs unwraps app markers in backticks', () {
    const String input =
        '在 `[app: 支付宝|com.eg.android.AlipayGphone]` 和 `[app: 一木记账]` 间对账';
    const String expected =
        '在 [app: 支付宝|com.eg.android.AlipayGphone] 和 [app: 一木记账] 间对账';

    expect(normalizeCodeWrappedAppRefs(input), expected);
  });

  test('normalizeCodeWrappedAppRefs keeps normal inline code unchanged', () {
    const String input = '请保留 `final answer = 42;` 这样的代码';

    expect(normalizeCodeWrappedAppRefs(input), input);
  });

  test('buildAppMarkerSystemMessage forbids markdown wrappers', () {
    final String zh = buildAppMarkerSystemMessage(const Locale('zh'));
    final String en = buildAppMarkerSystemMessage(const Locale('en'));

    expect(zh, contains('[app: 应用名]'));
    expect(zh, isNot(contains('`[app: 应用名]`')));
    expect(zh, contains('不要再包裹反引号'));

    expect(en, contains('[app: App Name]'));
    expect(en, isNot(contains('`[app: App Name]`')));
    expect(en, contains('without wrapping it in backticks'));
  });
}
