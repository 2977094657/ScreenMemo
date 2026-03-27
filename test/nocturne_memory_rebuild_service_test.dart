import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/nocturne_memory_rebuild_service.dart';

void main() {
  test('memory rebuild parser accepts compact tuple format', () {
    const String raw = '''
[
  {create_memory,core://my_user/organizations,shuixingbozi_dayuan,用户会在哔哩哔哩浏览 UP 主“水星波子大圆”的内容。},
  {update_memory,core://my_user/interests,- 会持续浏览《戴森球计划》相关内容}
]
''';

    final List<NocturneMemoryAction> actions =
        NocturneMemoryRebuildService.parseModelOutput(content: raw);

    expect(actions, hasLength(2));
    expect(actions.first.tool, 'create_memory');
    expect(actions.first.args['title'], 'shuixingbozi_dayuan');
    expect(actions.last.tool, 'update_memory');
    expect(actions.last.args['append'], contains('戴森球计划'));
  });

  test('memory rebuild parser accepts empty list sentinel', () {
    final List<NocturneMemoryAction> none =
        NocturneMemoryRebuildService.parseModelOutput(content: '[]');
    expect(none, isEmpty);
  });

  test('memory rebuild parser preserves commas in compact fields', () {
    const String raw = '''
[
  {create_memory,core://my_user/organizations,shuixingbozi_dayuan,用户会在哔哩哔哩浏览 UP 主“水星波子大圆”的内容，也会看评论区讨论。},
  {update_memory,core://my_user/interests,- 会持续浏览《戴森球计划》相关内容，包括玩法优化、战斗/航行画面与评论区讨论。}
]
''';

    final List<NocturneMemoryAction> actions =
        NocturneMemoryRebuildService.parseModelOutput(content: raw);

    expect(actions, hasLength(2));
    expect(actions.first.args['content'], contains('评论区讨论'));
    expect(actions.last.args['append'], contains('玩法优化、战斗/航行画面'));
  });

  test('memory rebuild parser rejects NO_ACTIONS sentinel', () {
    expect(
      () =>
          NocturneMemoryRebuildService.parseModelOutput(content: 'NO_ACTIONS'),
      throwsA(isA<FormatException>()),
    );
  });

  test('memory rebuild parser rejects malformed compact format', () {
    expect(
      () => NocturneMemoryRebuildService.parseModelOutput(
        content: '[{update_memory,core://my_user/interests,- 会持续浏览《戴森球计划》相关内容}',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('memory rebuild parser rejects legacy json format', () {
    expect(
      () => NocturneMemoryRebuildService.parseModelOutput(
        content:
            '{"actions":[{"tool":"update_memory","args":{"uri":"core://my_user/preferences","append":"\\n- 喜欢深色主题"}}]}',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
