import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/user_memory_service.dart';

void main() {
  test('UserMemoryPath.parse dispatches known path kinds', () {
    expect(
      UserMemoryPath.parse('profile:user').kind,
      UserMemoryPathKind.profileUser,
    );
    expect(
      UserMemoryPath.parse('profile:auto').kind,
      UserMemoryPathKind.profileAuto,
    );

    final UserMemoryPath item = UserMemoryPath.parse('item:123');
    expect(item.kind, UserMemoryPathKind.item);
    expect(item.itemId, 123);

    final UserMemoryPath daily = UserMemoryPath.parse('daily:2026-02-14');
    expect(daily.kind, UserMemoryPathKind.daily);
    expect(daily.dateKey, '2026-02-14');

    final UserMemoryPath weekly = UserMemoryPath.parse('weekly:2026-02-10');
    expect(weekly.kind, UserMemoryPathKind.weekly);
    expect(weekly.dateKey, '2026-02-10');

    final UserMemoryPath morning = UserMemoryPath.parse('morning:2026-02-14');
    expect(morning.kind, UserMemoryPathKind.morning);
    expect(morning.dateKey, '2026-02-14');
  });

  test('UserMemoryPath.parse returns unknown for invalid paths', () {
    expect(UserMemoryPath.parse('').kind, UserMemoryPathKind.unknown);
    expect(UserMemoryPath.parse('item:0').kind, UserMemoryPathKind.unknown);
    expect(UserMemoryPath.parse('daily:').kind, UserMemoryPathKind.unknown);
    expect(UserMemoryPath.parse('xxx').kind, UserMemoryPathKind.unknown);
  });
}
