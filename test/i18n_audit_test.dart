import 'package:flutter_test/flutter_test.dart';

import '../tool/i18n_audit.dart' as audit;

void main() {
  test('i18n audit passes', () async {
    final int code = await audit.runI18nAudit(const ['--check']);
    expect(code, 0);
  });
}
